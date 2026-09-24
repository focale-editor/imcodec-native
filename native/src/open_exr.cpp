#include "raster_codecs.h"

#include <ImfChannelList.h>
#include <ImfChromaticities.h>
#include <ImfFrameBuffer.h>
#include <ImfHeader.h>
#include <ImfIO.h>
#include <ImfInputFile.h>
#include <ImfOutputFile.h>
#include <ImfStandardAttributes.h>
#include <ImathMatrix.h>
#include <half.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <string>

namespace imcodec {
namespace {
namespace exr = OPENEXR_IMF_NAMESPACE;
namespace math = IMATH_NAMESPACE;
class ExrInput final : public exr::IStream {
 public:
  ExrInput(const uint8_t* bytes, size_t size) : IStream("memory"), bytes_(bytes), size_(size) {}
  bool read(char* output, int count) override {
    if (count < 0 || size_t(count) > size_ - position_) throw std::runtime_error("Truncated OpenEXR input");
    std::memcpy(output, bytes_ + position_, count);
    position_ += count;
    return position_ < size_;
  }
  uint64_t tellg() override { return position_; }
  void seekg(uint64_t position) override {
    if (position > size_) throw std::runtime_error("OpenEXR seek exceeds input");
    position_ = static_cast<size_t>(position);
  }
 private:
  const uint8_t* bytes_;
  size_t size_;
  size_t position_ = 0;
};
class ExrOutput final : public exr::OStream {
 public:
  ExrOutput(std::vector<uint8_t>& bytes, size_t limit) : OStream("memory"), bytes_(bytes), limit_(limit) {}
  void write(const char* data, int count) override {
    if (count < 0 || size_t(count) > limit_ - position_) throw std::runtime_error("Encoded OpenEXR exceeds its byte limit");
    const size_t end = position_ + count;
    if (end > bytes_.size()) bytes_.resize(end);
    if (count) std::memcpy(bytes_.data() + position_, data, count);
    position_ = end;
  }
  uint64_t tellp() override { return position_; }
  void seekp(uint64_t position) override {
    if (position > limit_) throw std::runtime_error("Encoded OpenEXR exceeds its byte limit");
    position_ = static_cast<size_t>(position);
  }
 private:
  std::vector<uint8_t>& bytes_;
  size_t limit_;
  size_t position_ = 0;
};
uint32_t exr_integer(const uint8_t* bytes) {
  return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 | uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
}
// Bound header attributes before OpenEXR allocates their decoded values.
void validate_exr_header(const uint8_t* bytes, size_t size, const RasterLimits& limits, bool inspect) {
  if (!bytes || size < 9 || exr_integer(bytes) != 20000630 || (exr_integer(bytes + 4) & 0xff) != 2) throw std::runtime_error("Invalid OpenEXR header");
  if (exr_integer(bytes + 4) & 0x1800) throw std::runtime_error("Deep and multipart OpenEXR images are unsupported");
  size_t position = 8;
  size_t attributes = 0;
  const size_t maximum = std::max({limits.icc, limits.metadata, size_t(65536)});
  while (position < size && bytes[position]) {
    if (++attributes > 1024 || position > maximum) throw std::runtime_error("OpenEXR header exceeds its metadata limit");
    const char* name = reinterpret_cast<const char*>(bytes + position);
    for (int field = 0; field < 2; ++field) {
      size_t count = 0;
      while (position < size && bytes[position]) {
        if (++count > 255) throw std::runtime_error("Invalid OpenEXR attribute name");
        ++position;
      }
      if (position == size) throw std::runtime_error("Truncated OpenEXR attribute name");
      ++position;
    }
    if (size - position < 4) throw std::runtime_error("Truncated OpenEXR attribute size");
    const size_t length = exr_integer(bytes + position);
    position += 4;
    if (length > size - position || length > maximum || position > maximum - length) throw std::runtime_error("OpenEXR attribute exceeds its metadata limit");
    if (std::strcmp(name, "dataWindow") == 0 && length == 16) {
      const int64_t width = int64_t(static_cast<int32_t>(exr_integer(bytes + position + 8))) - static_cast<int32_t>(exr_integer(bytes + position)) + 1;
      const int64_t height = int64_t(static_cast<int32_t>(exr_integer(bytes + position + 12))) - static_cast<int32_t>(exr_integer(bytes + position + 4)) + 1;
      if (width < 1 || height < 1) throw std::runtime_error("Invalid OpenEXR data window");
      pixel_bytes(width, height, inspect ? 1 : 16, limits.pixels, inspect ? std::numeric_limits<size_t>::max() : limits.bytes);
    }
    if (std::strcmp(name, "tiles") == 0 && length == 9) {
      pixel_bytes(exr_integer(bytes + position), exr_integer(bytes + position + 4), 16,
                  limits.pixels, inspect ? std::numeric_limits<size_t>::max() : limits.bytes);
    }
    position += length;
  }
  if (position == size) throw std::runtime_error("Truncated OpenEXR header");
}
// The bridge serializes OpenEXR calls; restore its global limits on every exit.
struct ExrHeaderLimits {
  int width, height, tile_width, tile_height;
  explicit ExrHeaderLimits(int maximum) {
    exr::Header::getMaxImageSize(width, height);
    exr::Header::getMaxTileSize(tile_width, tile_height);
    exr::Header::setMaxImageSize(maximum, maximum);
    exr::Header::setMaxTileSize(maximum, maximum);
  }
  ~ExrHeaderLimits() {
    exr::Header::setMaxImageSize(width, height);
    exr::Header::setMaxTileSize(tile_width, tile_height);
  }
};
float finite(float value) { return std::isfinite(value) ? value : 0; }
float linear_to_srgb(float value) {
  const float absolute = std::abs(value);
  return std::copysign(absolute <= 0.0031308f ? absolute * 12.92f : 1.055f * std::pow(absolute, 1.0f / 2.4f) - 0.055f, value);
}
float srgb_to_linear(uint8_t sample) {
  const float value = sample / 255.0f;
  return value <= 0.04045f ? value / 12.92f : std::pow((value + 0.055f) / 1.055f, 2.4f);
}
math::M44f to_srgb(const exr::Header& header) {
  const exr::Chromaticities target;
  if (!exr::hasChromaticities(header)) return math::M44f();
  const auto source = exr::chromaticities(header);
  if (!(source.white.y > 0) || !(source.red.y > 0) || !(source.green.y > 0) || !(source.blue.y > 0)) throw std::runtime_error("Invalid OpenEXR chromaticities");
  // Imath uses row vectors. Adapt the authored white to D65 with Bradford.
  const math::M44f bradford(0.8951f, -0.7502f, 0.0389f, 0,
                          0.2664f, 1.7135f, -0.0685f, 0,
                          -0.1614f, 0.0367f, 1.0296f, 0,
                          0, 0, 0, 1);
  const math::V3f white(source.white.x / source.white.y, 1, (1 - source.white.x - source.white.y) / source.white.y);
  const math::V3f d65(target.white.x / target.white.y, 1, (1 - target.white.x - target.white.y) / target.white.y);
  const math::V3f cones = white * bradford;
  const math::V3f destination = d65 * bradford;
  math::M44f scale;
  for (int i = 0; i < 3; ++i) {
    if (!std::isfinite(cones[i]) || std::abs(cones[i]) < 1e-8f) throw std::runtime_error("Invalid OpenEXR white point");
    scale[i][i] = destination[i] / cones[i];
  }
  const math::M44f matrix = exr::RGBtoXYZ(source, 1) * bradford * scale * bradford.inverse() * exr::XYZtoRGB(target, 1);
  for (int y = 0; y < 4; ++y) for (int x = 0; x < 4; ++x) if (!std::isfinite(matrix[y][x])) throw std::runtime_error("Invalid OpenEXR colour matrix");
  return matrix;
}
}

void read_exr(imcodec_result& result, const uint8_t* bytes, size_t size,
              const RasterLimits& limits, bool inspect) {
  validate_exr_header(bytes, size, limits, inspect);
  const int maximum = static_cast<int>(std::min<size_t>(limits.pixels, INT32_MAX));
  ExrHeaderLimits header_limits(maximum);
  ExrInput stream(bytes, size);
  exr::InputFile image(stream, 0);
  const exr::Header& header = image.header();
  const auto& window = header.dataWindow();
  const int64_t width = int64_t(window.max.x) - window.min.x + 1;
  const int64_t height = int64_t(window.max.y) - window.min.y + 1;
  if (width < 1 || height < 1 || width > INT32_MAX || height > INT32_MAX) throw std::runtime_error("Invalid OpenEXR data window");
  result.width = static_cast<size_t>(width);
  result.height = static_cast<size_t>(height);
  const auto& channels = header.channels();
  std::string prefix;
  bool rgb = channels.findChannel("R") && channels.findChannel("G") && channels.findChannel("B");
  bool gray = channels.findChannel("Y");
  if (!rgb && !gray) {
    for (auto it = channels.begin(); it != channels.end(); ++it) {
      const std::string name(it.name());
      const size_t dot = name.rfind('.');
      if (dot == std::string::npos) continue;
      const std::string candidate = name.substr(0, dot + 1);
      rgb = channels.findChannel(candidate + "R") && channels.findChannel(candidate + "G") && channels.findChannel(candidate + "B");
      gray = channels.findChannel(candidate + "Y");
      if (rgb || gray) { prefix = candidate; break; }
    }
  }
  if (!rgb && !gray) throw std::runtime_error("OpenEXR has no RGB or luminance channels");
  size_t channel_bytes = 0;
  for (auto it = channels.begin(); it != channels.end(); ++it) {
    channel_bytes += it.channel().type == exr::HALF ? 2 : 4;
    if (channel_bytes > 256) throw std::runtime_error("OpenEXR contains too many channels");
  }
  result.source_depth = 16;
  const std::string names[4] = {prefix + (rgb ? "R" : "Y"), prefix + "G", prefix + "B", prefix + "A"};
  for (int c = 0; c < 4; ++c) {
    const auto* channel = channels.findChannel(names[c]);
    if (!channel) continue;
    if (channel->xSampling != 1 || channel->ySampling != 1) throw std::runtime_error("Subsampled OpenEXR colour channels are unsupported");
    if (channel->type != exr::HALF) result.source_depth = 32;
  }
  if (inspect) return;
  result.depth = limits.preserve ? 32 : 8;
  const size_t length = pixel_bytes(result.width, result.height, result.depth / 2, limits.pixels, limits.bytes);
  // Include source channels and the float conversion raster in working limits.
  pixel_bytes(result.width, result.height, std::max<size_t>(16, channel_bytes), limits.pixels, limits.bytes);
  if (header.hasTileDescription()) {
    const auto& tile = header.tileDescription();
    pixel_bytes(tile.xSize, tile.ySize, std::max<size_t>(16, channel_bytes), limits.pixels, limits.bytes);
  }
  std::vector<float> pixels(result.width * result.height * 4);
  exr::FrameBuffer frame;
  for (int c = 0; c < 4; ++c) {
    if (!rgb && (c == 1 || c == 2)) continue;
    frame.insert(names[c], exr::Slice::Make(exr::FLOAT, pixels.data() + c, window, sizeof(float) * 4, result.width * sizeof(float) * 4, 1, 1, c == 3 ? 1 : 0));
  }
  image.setFrameBuffer(frame);
  image.readPixels(window.min.y, window.max.y);
  const math::M44f matrix = to_srgb(header);
  result.buffers[0].resize(length);
  for (size_t i = 0; i < pixels.size(); i += 4) {
    math::V3f color(finite(pixels[i]), finite(pixels[i + (rgb ? 1 : 0)]), finite(pixels[i + (rgb ? 2 : 0)]));
    color = color * matrix;
    const float values[4] = {linear_to_srgb(finite(color.x)), linear_to_srgb(finite(color.y)), linear_to_srgb(finite(color.z)), std::clamp(finite(pixels[i + 3]), 0.0f, 1.0f)};
    for (int c = 0; c < 4; ++c) {
      if (result.depth == 32) {
        uint32_t bits;
        std::memcpy(&bits, &values[c], 4);
        for (int b = 0; b < 4; ++b) result.buffers[0][(i + c) * 4 + b] = (bits >> (8 * b)) & 255;
      } else result.buffers[0][i + c] = static_cast<uint8_t>(std::clamp(values[c], 0.0f, 1.0f) * 255 + 0.5f);
    }
  }
}

void encode_exr(imcodec_result& result, const uint8_t* rgba, int width, int height,
                int compression, size_t max_bytes) {
  if (compression != 0 && compression != 2 && compression != 3) throw std::runtime_error("Invalid OpenEXR compression");
  ExrOutput stream(result.buffers[0], max_bytes);
  exr::Header header(width, height);
  header.compression() = static_cast<exr::Compression>(compression);
  exr::addChromaticities(header, exr::Chromaticities());
  const char* names[4] = {"R", "G", "B", "A"};
  for (const char* name : names) header.channels().insert(name, exr::Channel(exr::HALF));
  exr::OutputFile image(stream, header, 0);
  std::vector<math::half> row(size_t(width) * 4);
  for (int y = 0; y < height; ++y) {
    for (size_t i = 0; i < row.size(); ++i) row[i] = i % 4 == 3 ? rgba[size_t(y) * row.size() + i] / 255.0f : srgb_to_linear(rgba[size_t(y) * row.size() + i]);
    exr::FrameBuffer frame;
    for (int c = 0; c < 4; ++c) frame.insert(names[c], exr::Slice::Make(exr::HALF, row.data() + c, math::V2i(0, y), width, 1, sizeof(math::half) * 4, size_t(width) * sizeof(math::half) * 4));
    image.setFrameBuffer(frame);
    image.writePixels(1);
  }
}
}
