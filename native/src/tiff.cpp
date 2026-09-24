#include "raster_codecs.h"

#include <tiffio.h>
#include <algorithm>
#include <cstdarg>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>

namespace imcodec {
namespace {
struct TiffStream {
  const uint8_t* input = nullptr;
  size_t size = 0;
  size_t position = 0;
  std::vector<uint8_t>* output = nullptr;
  size_t limit = 0;
  bool failed = false;
  char error[256] = {};
};
tmsize_t tiff_read(thandle_t handle, void* buffer, tmsize_t count) {
  auto& stream = *static_cast<TiffStream*>(handle);
  if (count < 0 || stream.position > stream.size) return 0;
  const size_t length = std::min<size_t>(count, stream.size - stream.position);
  if (length) std::memcpy(buffer, stream.input + stream.position, length);
  stream.position += length;
  return static_cast<tmsize_t>(length);
}
tmsize_t tiff_write(thandle_t handle, void* buffer, tmsize_t count) {
  auto& stream = *static_cast<TiffStream*>(handle);
  if (!stream.output || count < 0 || stream.position > stream.limit || size_t(count) > stream.limit - stream.position) {
    stream.failed = true;
    return 0;
  }
  try {
    const size_t end = stream.position + count;
    if (end > stream.output->size()) stream.output->resize(end);
    if (count) std::memcpy(stream.output->data() + stream.position, buffer, count);
    stream.position = end;
    stream.size = stream.output->size();
    return count;
  } catch (...) {
    stream.failed = true;
    return 0;
  }
}
toff_t tiff_seek(thandle_t handle, toff_t offset, int origin) {
  auto& stream = *static_cast<TiffStream*>(handle);
  const uint64_t base = origin == SEEK_SET ? 0 : origin == SEEK_CUR ? stream.position : stream.size;
  uint64_t position;
  if (origin != SEEK_SET && offset > uint64_t(INT64_MAX)) {
    const uint64_t backward = ~offset + 1;
    if (backward > base) return toff_t(-1);
    position = base - backward;
  } else {
    if (offset > std::numeric_limits<uint64_t>::max() - base) return toff_t(-1);
    position = base + offset;
  }
  if (position > (stream.output ? stream.limit : stream.size)) return toff_t(-1);
  stream.position = static_cast<size_t>(position);
  return position;
}
int tiff_close(thandle_t) { return 0; }
toff_t tiff_size(thandle_t handle) { return static_cast<TiffStream*>(handle)->size; }
int tiff_map(thandle_t, void**, toff_t*) { return 0; }
void tiff_unmap(thandle_t, void*, toff_t) {}
int tiff_error(TIFF*, void* user, const char*, const char* format, va_list args) {
  auto& stream = *static_cast<TiffStream*>(user);
  std::vsnprintf(stream.error, sizeof(stream.error), format, args);
  stream.failed = true;
  return 1;
}
int tiff_warning(TIFF*, void*, const char*, const char*, va_list) { return 1; }
Owned<TIFF, TIFFClose> open_tiff(TiffStream& stream, const char* mode, size_t allocation_limit) {
  Owned<TIFFOpenOptions, TIFFOpenOptionsFree> options(TIFFOpenOptionsAlloc(), TIFFOpenOptionsFree);
  if (!options) throw std::bad_alloc();
  const auto limit = static_cast<tmsize_t>(std::min<size_t>(allocation_limit, std::numeric_limits<tmsize_t>::max()));
  TIFFOpenOptionsSetMaxSingleMemAlloc(options.get(), limit);
  TIFFOpenOptionsSetMaxCumulatedMemAlloc(options.get(), limit);
  TIFFOpenOptionsSetErrorHandlerExtR(options.get(), tiff_error, &stream);
  TIFFOpenOptionsSetWarningHandlerExtR(options.get(), tiff_warning, &stream);
  Owned<TIFF, TIFFClose> image(TIFFClientOpenExt("memory", mode, &stream, tiff_read, tiff_write,
      tiff_seek, tiff_close, tiff_size, tiff_map, tiff_unmap, options.get()), TIFFClose);
  if (!image) throw std::runtime_error(stream.error[0] ? stream.error : "Invalid TIFF input");
  return image;
}
void tiff_blob(TIFF* image, uint32_t tag, std::vector<uint8_t>& output, size_t limit) {
  uint32_t size = 0;
  void* data = nullptr;
  if (limit && TIFFGetField(image, tag, &size, &data)) {
    if (size > limit) throw std::runtime_error("TIFF metadata exceeds its byte limit");
    if (size && data) output.assign(static_cast<uint8_t*>(data), static_cast<uint8_t*>(data) + size);
  }
}
size_t oriented_pixel(size_t x, size_t y, size_t width, size_t height, uint16_t orientation) {
  switch (orientation) {
    case 2: return y * width + width - 1 - x;
    case 3: return (height - 1 - y) * width + width - 1 - x;
    case 4: return (height - 1 - y) * width + x;
    case 5: return x * height + y;
    case 6: return x * height + height - 1 - y;
    case 7: return (width - 1 - x) * height + height - 1 - y;
    case 8: return (width - 1 - x) * height + y;
    default: return y * width + x;
  }
}
double sample_value(const uint8_t* bytes, uint16_t bits, uint16_t format) {
  if (format == SAMPLEFORMAT_IEEEFP) {
    float value;
    std::memcpy(&value, bytes, 4);
    return std::isfinite(value) ? value : 0;
  }
  if (bits == 16) {
    uint16_t value;
    std::memcpy(&value, bytes, 2);
    return value / 65535.0;
  }
  return *bytes / 255.0;
}
void store_sample(uint8_t* target, double value, size_t depth) {
  if (depth == 32) {
    const float sample = static_cast<float>(value);
    uint32_t bits;
    std::memcpy(&bits, &sample, 4);
    for (int i = 0; i < 4; ++i) target[i] = (bits >> (8 * i)) & 255;
  } else {
    const unsigned sample = static_cast<unsigned>(std::clamp(value, 0.0, 1.0) * (depth == 16 ? 65535 : 255) + 0.5);
    target[0] = sample & 255;
    if (depth == 16) target[1] = sample >> 8;
  }
}
}

void read_tiff(imcodec_result& result, const uint8_t* bytes, size_t size,
               const RasterLimits& limits, bool inspect) {
  TiffStream stream{bytes, size};
  auto image = open_tiff(stream, "rm", std::max({limits.bytes, limits.icc, limits.metadata, size_t(65536)}));
  uint32_t width = 0, height = 0;
  uint16_t bits = 1, samples = 1, format = SAMPLEFORMAT_UINT, photometric = 0;
  uint16_t planar = PLANARCONFIG_CONTIG, orientation = ORIENTATION_TOPLEFT;
  if (!TIFFGetField(image.get(), TIFFTAG_IMAGEWIDTH, &width) || !TIFFGetField(image.get(), TIFFTAG_IMAGELENGTH, &height) || !width || !height) throw std::runtime_error("Invalid TIFF dimensions");
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_BITSPERSAMPLE, &bits);
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_SAMPLESPERPIXEL, &samples);
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_SAMPLEFORMAT, &format);
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_PLANARCONFIG, &planar);
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_ORIENTATION, &orientation);
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_PHOTOMETRIC, &photometric);
  if (orientation < 1 || orientation > 8) throw std::runtime_error("Invalid TIFF orientation");
  result.width = width;
  result.height = height;
  result.source_depth = bits;
  const bool cmyk = photometric == PHOTOMETRIC_SEPARATED;
  uint16_t inks = INKSET_CMYK;
  if (cmyk) TIFFGetFieldDefaulted(image.get(), TIFFTAG_INKSET, &inks);
  if (cmyk && inks != INKSET_CMYK) throw std::runtime_error("Unsupported TIFF ink set");
  result.color_model = cmyk ? 1 : 0;
  tiff_blob(image.get(), TIFFTAG_ICCPROFILE, result.buffers[1], limits.icc);
  tiff_blob(image.get(), TIFFTAG_XMLPACKET, result.buffers[3], limits.metadata);
  if (inspect) return;
  const bool rgb = photometric == PHOTOMETRIC_RGB;
  const bool gray = photometric == PHOTOMETRIC_MINISBLACK || photometric == PHOTOMETRIC_MINISWHITE;
  const unsigned colors = cmyk ? 4 : rgb ? 3 : 1;
  const bool direct = (rgb || gray || cmyk) && samples >= colors && samples <= colors + 1 &&
      ((format == SAMPLEFORMAT_UINT && (bits == 8 || bits == 16)) || (format == SAMPLEFORMAT_IEEEFP && bits == 32));
  if (!direct && limits.preserve && (bits > 8 || cmyk)) throw std::runtime_error("Unsupported exact TIFF sample layout");
  result.depth = direct && limits.preserve ? bits : 8;
  const size_t output_channels = cmyk && limits.preserve && direct ? 5 : 4;
  result.buffers[0].resize(pixel_bytes(width, height, output_channels * (result.depth / 8), limits.pixels, limits.bytes));
  if (orientation >= 5) std::swap(result.width, result.height);
  if (!direct) {
    // libtiff's compatibility raster is associated RGBA8. Normalize orientation
    // ourselves and undo association to satisfy Imcodec's straight-alpha API.
    std::vector<uint32_t> raster(size_t(width) * height);
    TIFFSetField(image.get(), TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT);
    if (!TIFFReadRGBAImageOriented(image.get(), width, height, raster.data(), ORIENTATION_TOPLEFT, 1)) throw std::runtime_error("TIFF raster decoding failed");
    for (size_t y = 0; y < height; ++y) for (size_t x = 0; x < width; ++x) {
      const uint32_t pixel = raster[y * width + x];
      uint8_t* target = result.buffers[0].data() + oriented_pixel(x, y, width, height, orientation) * 4;
      const unsigned alpha = TIFFGetA(pixel);
      target[0] = alpha ? std::min(255u, (TIFFGetR(pixel) * 255u + alpha / 2) / alpha) : 0;
      target[1] = alpha ? std::min(255u, (TIFFGetG(pixel) * 255u + alpha / 2) / alpha) : 0;
      target[2] = alpha ? std::min(255u, (TIFFGetB(pixel) * 255u + alpha / 2) / alpha) : 0;
      target[3] = alpha;
    }
    result.color_model = 0;
    if (cmyk) result.buffers[1].clear();
    return;
  }
  if (cmyk && !limits.preserve) {
    result.color_model = 0;
    result.buffers[1].clear();
  }
  if (planar != PLANARCONFIG_CONTIG && planar != PLANARCONFIG_SEPARATE) throw std::runtime_error("Unsupported TIFF planar layout");
  uint16_t extra_count = 0;
  uint16_t* extras = nullptr;
  TIFFGetFieldDefaulted(image.get(), TIFFTAG_EXTRASAMPLES, &extra_count, &extras);
  const bool alpha = samples == colors + 1 && extra_count == 1 && extras &&
      (extras[0] == EXTRASAMPLE_ASSOCALPHA || extras[0] == EXTRASAMPLE_UNASSALPHA);
  const bool associated = alpha && extras[0] == EXTRASAMPLE_ASSOCALPHA;
  const size_t planes = planar == PLANARCONFIG_SEPARATE ? samples : 1;
  const size_t sample_bytes = bits / 8;
  const bool tiled = TIFFIsTiled(image.get());
  uint32_t block_width = width, block_height = 0;
  if (tiled) {
    TIFFGetField(image.get(), TIFFTAG_TILEWIDTH, &block_width);
    TIFFGetField(image.get(), TIFFTAG_TILELENGTH, &block_height);
  } else TIFFGetFieldDefaulted(image.get(), TIFFTAG_ROWSPERSTRIP, &block_height);
  if (!block_width || !block_height) throw std::runtime_error("Invalid TIFF block dimensions");
  if (!tiled) block_height = std::min(block_height, height);
  const uint64_t block_size = tiled ? TIFFTileSize64(image.get()) : TIFFStripSize64(image.get());
  if (!block_size || block_size > limits.bytes / planes || block_size > size_t(std::numeric_limits<tmsize_t>::max())) throw std::runtime_error("TIFF block exceeds its decoded-byte limit");
  std::vector<uint8_t> block(static_cast<size_t>(block_size) * planes);
  for (uint64_t y = 0; y < height; y += block_height) for (uint64_t x = 0; x < width; x += block_width) {
    const size_t rows = std::min<uint64_t>(block_height, height - y);
    const size_t columns = std::min<uint64_t>(block_width, width - x);
    const size_t stride = size_t(block_width) * (planes == 1 ? samples : 1) * sample_bytes;
    if (rows > block_size / stride) throw std::runtime_error("Invalid TIFF block layout");
    for (size_t plane = 0; plane < planes; ++plane) {
      const uint32_t index = tiled ? TIFFComputeTile(image.get(), x, y, 0, plane) : TIFFComputeStrip(image.get(), y, plane);
      const tmsize_t decoded = tiled ? TIFFReadEncodedTile(image.get(), index, block.data() + plane * block_size, block_size) : TIFFReadEncodedStrip(image.get(), index, block.data() + plane * block_size, block_size);
      if (decoded < 0 || size_t(decoded) < rows * stride) throw std::runtime_error("Incomplete TIFF block");
    }
    for (size_t row = 0; row < rows; ++row) for (size_t column = 0; column < columns; ++column) {
      double values[5] = {0, 0, 0, 0, 1};
      for (unsigned c = 0; c < samples; ++c) {
        const size_t offset = planes == 1 ? row * stride + (column * samples + c) * sample_bytes : c * block_size + row * stride + column * sample_bytes;
        values[c] = sample_value(block.data() + offset, bits, format);
      }
      const double opacity = alpha ? std::clamp(values[colors], 0.0, 1.0) : 1;
      if (gray) {
        if (photometric == PHOTOMETRIC_MINISWHITE) values[0] = 1 - values[0];
        values[1] = values[2] = values[0];
      }
      if (associated) for (unsigned c = 0; c < colors; ++c) values[c] = opacity > 0 ? values[c] / opacity : 0;
      if (cmyk && !limits.preserve) {
        const double black = 1 - values[3];
        for (int c = 0; c < 3; ++c) values[c] = (1 - values[c]) * black;
      }
      values[output_channels - 1] = opacity;
      uint8_t* target = result.buffers[0].data() + oriented_pixel(x + column, y + row, width, height, orientation) * output_channels * (result.depth / 8);
      for (size_t c = 0; c < output_channels; ++c) store_sample(target + c * (result.depth / 8), values[c], result.depth);
    }
  }
  if (stream.failed) throw std::runtime_error(stream.error);
}

void encode_tiff(imcodec_result& result, const uint8_t* rgba, int width, int height,
                 int compression, size_t max_bytes) {
  if (compression < 0 || compression > 1) throw std::runtime_error("Invalid TIFF compression");
  TiffStream stream{};
  stream.output = &result.buffers[0];
  stream.limit = max_bytes;
  auto image = open_tiff(stream, "wl", std::max<size_t>(max_bytes, 65536));
  const uint16_t alpha = EXTRASAMPLE_UNASSALPHA;
  if (!TIFFSetField(image.get(), TIFFTAG_IMAGEWIDTH, width) ||
      !TIFFSetField(image.get(), TIFFTAG_IMAGELENGTH, height) ||
      !TIFFSetField(image.get(), TIFFTAG_SAMPLESPERPIXEL, 4) ||
      !TIFFSetField(image.get(), TIFFTAG_BITSPERSAMPLE, 8) ||
      !TIFFSetField(image.get(), TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB) ||
      !TIFFSetField(image.get(), TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG) ||
      !TIFFSetField(image.get(), TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT) ||
      !TIFFSetField(image.get(), TIFFTAG_COMPRESSION, compression ? COMPRESSION_PACKBITS : COMPRESSION_NONE) ||
      !TIFFSetField(image.get(), TIFFTAG_EXTRASAMPLES, 1, &alpha) ||
      !TIFFSetField(image.get(), TIFFTAG_ROWSPERSTRIP, TIFFDefaultStripSize(image.get(), 0))) throw std::runtime_error("Could not configure TIFF encoder");
  for (int y = 0; y < height; ++y) {
    if (TIFFWriteScanline(image.get(), const_cast<uint8_t*>(rgba + size_t(y) * width * 4), y) < 0) throw std::runtime_error("TIFF encoding failed or exceeded its byte limit");
  }
  if (!TIFFWriteDirectory(image.get())) throw std::runtime_error("TIFF directory exceeds its byte limit");
  image.reset();
  if (stream.failed) throw std::runtime_error("TIFF encoding failed or exceeded its byte limit");
}
}
