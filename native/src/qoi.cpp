#include "raster_codecs.h"

#define QOI_IMPLEMENTATION
#define QOI_NO_STDIO
#include <qoi.h>
#include <cstdlib>
#include <cstring>
#include <limits>

namespace imcodec {
namespace {
uint32_t qoi_integer(const uint8_t* bytes) {
  return uint32_t(bytes[0]) << 24 | uint32_t(bytes[1]) << 16 | uint32_t(bytes[2]) << 8 | bytes[3];
}
// The reference decoder tolerates incomplete streams. Validate opcode bounds,
// the exact pixel count and the end marker before giving it untrusted input.
void validate_qoi(const uint8_t* bytes, size_t size, size_t pixels) {
  static const uint8_t end[8] = {0, 0, 0, 0, 0, 0, 0, 1};
  if (size < 22 || std::memcmp(bytes + size - 8, end, 8)) throw std::runtime_error("Invalid QOI end marker");
  size_t position = 14;
  size_t decoded = 0;
  while (position < size - 8 && decoded < pixels) {
    const uint8_t code = bytes[position++];
    const size_t extra = code == 0xfe ? 3 : code == 0xff ? 4 : (code & 0xc0) == 0x80 ? 1 : 0;
    if (extra > size - 8 - position) throw std::runtime_error("Truncated QOI opcode");
    position += extra;
    const size_t run = code < 0xfe && (code & 0xc0) == 0xc0 ? (code & 0x3f) + 1 : 1;
    if (run > pixels - decoded) throw std::runtime_error("QOI run exceeds image dimensions");
    decoded += run;
  }
  if (decoded != pixels || position != size - 8) throw std::runtime_error("QOI pixel data does not match its dimensions");
}
}
void read_qoi(imcodec_result& result, const uint8_t* bytes, size_t size,
              const RasterLimits& limits, bool inspect) {
  if (!bytes || size < 22 || size > std::numeric_limits<int>::max() ||
      std::memcmp(bytes, "qoif", 4) || (bytes[12] != 3 && bytes[12] != 4) || bytes[13] > 1) {
    throw std::runtime_error("Invalid QOI header");
  }
  result.width = qoi_integer(bytes + 4);
  result.height = qoi_integer(bytes + 8);
  const size_t length = pixel_bytes(result.width, result.height, 4, limits.pixels, limits.bytes);
  if (inspect) return;
  validate_qoi(bytes, size, length / 4);
  qoi_desc description{};
  Owned<void, std::free> pixels(qoi_decode(bytes, static_cast<int>(size), &description, 4), std::free);
  if (!pixels) throw std::runtime_error("QOI decoding failed");
  const auto* data = static_cast<const uint8_t*>(pixels.get());
  result.buffers[0].assign(data, data + length);
}
void encode_qoi(imcodec_result& result, const uint8_t* rgba, int width, int height, size_t max_bytes) {
  // qoi_encode allocates its worst-case output in one block; enforce the bound
  // before it allocates, even if a particular image could compress smaller.
  const size_t pixels = size_t(width) * height;
  if (max_bytes < 22 || pixels > (max_bytes - 22) / 5 || pixels >= QOI_PIXELS_MAX ||
      pixels > (size_t(std::numeric_limits<int>::max()) - 22) / 5) {
    throw std::runtime_error("QOI encoder allocation exceeds its byte limit");
  }
  const qoi_desc description{static_cast<unsigned>(width), static_cast<unsigned>(height), 4, QOI_SRGB};
  int size = 0;
  Owned<void, std::free> encoded(qoi_encode(rgba, &description, &size), std::free);
  if (!encoded || size < 1) throw std::runtime_error("QOI encoding failed");
  const auto* data = static_cast<const uint8_t*>(encoded.get());
  result.buffers[0].assign(data, data + size);
}
}
