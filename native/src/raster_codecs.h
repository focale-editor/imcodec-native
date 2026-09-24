#ifndef IMCODEC_RASTER_CODECS_H
#define IMCODEC_RASTER_CODECS_H

#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

// A result owns every byte returned through the C API, including error text.
struct imcodec_result {
  size_t width = 0;
  size_t height = 0;
  size_t depth = 8;
  size_t source_depth = 8;
  size_t color_model = 0;  // 0 = RGB, 1 = CMYK.
  std::vector<uint8_t> buffers[4];
  char error[512] = {};
};

namespace imcodec {
template <typename T, auto release>
using Owned = std::unique_ptr<T, decltype(release)>;

inline size_t pixel_bytes(size_t width, size_t height, size_t bytes_per_pixel,
                          size_t max_pixels, size_t max_bytes) {
  if (!width || !height || !max_pixels || !max_bytes ||
      width > max_pixels / height || width > max_bytes / height / bytes_per_pixel) {
    throw std::runtime_error("Image dimensions exceed the pixel or decoded-byte limit");
  }
  return width * height * bytes_per_pixel;
}

struct Writer {
  std::vector<uint8_t>& bytes;
  size_t limit;
  bool append(const uint8_t* data, size_t size) noexcept {
    if (size > limit - bytes.size()) return false;
    try {
      bytes.insert(bytes.end(), data, data + size);
      return true;
    } catch (...) {
      return false;
    }
  }
};

struct RasterLimits {
  size_t pixels;
  size_t bytes;
  size_t icc;
  size_t metadata;
  bool preserve;
};

void read_png(imcodec_result&, const uint8_t*, size_t, const RasterLimits&, bool);
void read_jpeg(imcodec_result&, const uint8_t*, size_t, const RasterLimits&, bool);
void read_qoi(imcodec_result&, const uint8_t*, size_t, const RasterLimits&, bool);
void read_tiff(imcodec_result&, const uint8_t*, size_t, const RasterLimits&, bool);
void read_exr(imcodec_result&, const uint8_t*, size_t, const RasterLimits&, bool);
void encode_png(imcodec_result&, const uint8_t*, int, int, int, size_t);
void encode_jpeg(imcodec_result&, const uint8_t*, int, int, int, int, size_t);
void encode_qoi(imcodec_result&, const uint8_t*, int, int, size_t);
void encode_tiff(imcodec_result&, const uint8_t*, int, int, int, size_t);
void encode_exr(imcodec_result&, const uint8_t*, int, int, int, size_t);
}
#endif
