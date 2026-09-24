#include "raster_codecs.h"

#include <png.h>
#include <zlib.h>
#include <algorithm>
#include <cstdio>
#include <cstring>

namespace imcodec {
namespace {
// Keep state on the heap: libpng errors longjmp to the caller's guard.
struct PngState {
  png_structp png = nullptr;
  png_infop info = nullptr;
  bool writing = false;
  const uint8_t* input = nullptr;
  size_t size = 0;
  size_t position = 0;
  Writer* writer = nullptr;
  std::vector<png_bytep> rows;
  char error[256] = {};
  ~PngState() {
    if (writing) png_destroy_write_struct(&png, &info);
    else png_destroy_read_struct(&png, &info, nullptr);
  }
};
void png_failure(png_structp png, png_const_charp message) {
  auto* state = static_cast<PngState*>(png_get_error_ptr(png));
  std::snprintf(state->error, sizeof(state->error), "%s", message);
  png_longjmp(png, 1);
}
void png_warning(png_structp png, png_const_charp message) { png_failure(png, message); }
void png_read(png_structp png, png_bytep output, png_size_t size) {
  auto* state = static_cast<PngState*>(png_get_io_ptr(png));
  if (size > state->size - state->position) png_error(png, "Truncated PNG input");
  std::memcpy(output, state->input + state->position, size);
  state->position += size;
}
void png_write(png_structp png, png_bytep input, png_size_t size) {
  auto* state = static_cast<PngState*>(png_get_io_ptr(png));
  if (!state->writer->append(input, size)) png_error(png, "Encoded PNG exceeds its byte limit or available memory");
}
void png_flush(png_structp) {}
// Inspection skips IDAT pixels but still reads EXIF/XMP placed after them.
void inspect_png_chunks(imcodec_result& result, const uint8_t* bytes, size_t size, size_t limit) {
  size_t position = 8;
  bool image = false;
  while (position <= size && size - position >= 12) {
    const uint8_t* chunk = bytes + position;
    const size_t count = png_get_uint_32(chunk);
    if (count > size - position - 12) throw std::runtime_error("Truncated PNG chunk");
    const uint8_t* data = chunk + 8;
    const auto expected = png_get_uint_32(data + count);
    if (crc32(crc32(0, chunk + 4, 4), data, static_cast<uInt>(count)) != expected) throw std::runtime_error("Invalid PNG chunk checksum");
    if (std::memcmp(chunk + 4, "IDAT", 4) == 0) image = true;
    if (limit && std::memcmp(chunk + 4, "eXIf", 4) == 0) {
      if (count > limit) throw std::runtime_error("PNG EXIF metadata exceeds its byte limit");
      result.buffers[2].assign(data, data + count);
    }
    if (limit && std::memcmp(chunk + 4, "iTXt", 4) == 0 && count >= 22 &&
        std::memcmp(data, "XML:com.adobe.xmp\0", 18) == 0) {
      const bool compressed = data[18] == 1;
      if (data[18] > 1 || data[19] != 0) throw std::runtime_error("Invalid PNG XMP compression");
      size_t offset = 20;
      for (int field = 0; field < 2; ++field) {
        while (offset < count && data[offset]) ++offset;
        if (offset == count) throw std::runtime_error("Truncated PNG XMP header");
        ++offset;
      }
      if (!compressed) {
        if (count - offset > limit) throw std::runtime_error("PNG XMP metadata exceeds its byte limit");
        result.buffers[3].assign(data + offset, data + count);
      } else {
        std::vector<uint8_t> unpacked(limit + 1);
        uLongf length = unpacked.size();
        if (uncompress(unpacked.data(), &length, data + offset, count - offset) != Z_OK || length > limit) throw std::runtime_error("Invalid or oversized PNG XMP metadata");
        unpacked.resize(length);
        result.buffers[3] = std::move(unpacked);
      }
    }
    position += count + 12;
    if (std::memcmp(chunk + 4, "IEND", 4) == 0) {
      if (count || !image || position != size) throw std::runtime_error("Invalid PNG end chunk");
      return;
    }
  }
  throw std::runtime_error("Truncated PNG container");
}

void png_metadata(imcodec_result& result, PngState& state, const RasterLimits& limits) {
  png_charp name = nullptr;
  int method = 0;
  png_bytep profile = nullptr;
  png_uint_32 size = 0;
  if (png_get_iCCP(state.png, state.info, &name, &method, &profile, &size)) {
    if (size > limits.icc) throw std::runtime_error("PNG ICC profile exceeds its byte limit");
    result.buffers[1].assign(profile, profile + size);
  }
  if (limits.metadata && png_get_eXIf_1(state.png, state.info, &size, &profile)) {
    if (size > limits.metadata) throw std::runtime_error("PNG EXIF metadata exceeds its byte limit");
    result.buffers[2].assign(profile, profile + size);
  }
  png_textp text = nullptr;
  const int count = png_get_text(state.png, state.info, &text, nullptr);
  for (int i = 0; limits.metadata && i < count; ++i) {
    if (std::strcmp(text[i].key, "XML:com.adobe.xmp") != 0) continue;
    const size_t length = text[i].itxt_length ? text[i].itxt_length : text[i].text_length;
    if (length > limits.metadata) throw std::runtime_error("PNG XMP metadata exceeds its byte limit");
    result.buffers[3].assign(text[i].text, text[i].text + length);
  }
}
}

void read_png(imcodec_result& result, const uint8_t* bytes, size_t size,
              const RasterLimits& limits, bool inspect) {
  auto state = std::make_unique<PngState>();
  state->input = bytes;
  state->size = size;
  state->png = png_create_read_struct(PNG_LIBPNG_VER_STRING, state.get(), png_failure, png_warning);
  if (!state->png) throw std::bad_alloc();
  state->info = png_create_info_struct(state->png);
  if (!state->info) throw std::bad_alloc();
  if (setjmp(png_jmpbuf(state->png))) throw std::runtime_error(state->error);
  png_set_read_fn(state->png, state.get(), png_read);
  png_set_user_limits(state->png, static_cast<png_uint_32>(std::min<size_t>(limits.pixels, PNG_UINT_31_MAX)),
                      static_cast<png_uint_32>(std::min<size_t>(limits.pixels, PNG_UINT_31_MAX)));
  png_set_chunk_malloc_max(state->png, std::max(limits.icc, limits.metadata));
  png_set_chunk_cache_max(state->png, 128);
  png_set_crc_action(state->png, PNG_CRC_ERROR_QUIT, PNG_CRC_ERROR_QUIT);
  png_read_info(state->png, state->info);
  result.width = png_get_image_width(state->png, state->info);
  result.height = png_get_image_height(state->png, state->info);
  result.source_depth = png_get_bit_depth(state->png, state->info);
  result.depth = limits.preserve && result.source_depth == 16 ? 16 : 8;
  png_metadata(result, *state, limits);
  if (inspect) {
    inspect_png_chunks(result, bytes, size, limits.metadata);
    return;
  }
  result.buffers[0].resize(pixel_bytes(result.width, result.height, result.depth / 2, limits.pixels, limits.bytes));
  const int color = png_get_color_type(state->png, state->info);
  if (color == PNG_COLOR_TYPE_PALETTE) png_set_palette_to_rgb(state->png);
  if (color == PNG_COLOR_TYPE_GRAY && result.source_depth < 8) png_set_expand_gray_1_2_4_to_8(state->png);
  const bool transparent = png_get_valid(state->png, state->info, PNG_INFO_tRNS);
  if (transparent) png_set_tRNS_to_alpha(state->png);
  if (color == PNG_COLOR_TYPE_GRAY || color == PNG_COLOR_TYPE_GRAY_ALPHA) png_set_gray_to_rgb(state->png);
  if (!(color & PNG_COLOR_MASK_ALPHA) && !transparent) png_set_add_alpha(state->png, result.depth == 16 ? 65535 : 255, PNG_FILLER_AFTER);
  if (result.source_depth == 16) {
    if (result.depth == 8) png_set_scale_16(state->png);
    else png_set_swap(state->png);  // Imcodec's uint16 storage is little-endian.
  }
  png_set_interlace_handling(state->png);
  png_read_update_info(state->png, state->info);
  const size_t stride = result.width * result.depth / 2;
  if (png_get_rowbytes(state->png, state->info) != stride) throw std::runtime_error("Unexpected PNG output layout");
  state->rows.resize(result.height);
  for (size_t y = 0; y < result.height; ++y) state->rows[y] = result.buffers[0].data() + y * stride;
  png_read_image(state->png, state->rows.data());
  png_read_end(state->png, state->info);
  png_metadata(result, *state, limits);
}

void encode_png(imcodec_result& result, const uint8_t* rgba, int width, int height,
                int level, size_t max_bytes) {
  if (level < 0 || level > 9) throw std::runtime_error("Invalid PNG compression level");
  Writer writer{result.buffers[0], max_bytes};
  auto state = std::make_unique<PngState>();
  state->writing = true;
  state->writer = &writer;
  state->png = png_create_write_struct(PNG_LIBPNG_VER_STRING, state.get(), png_failure, png_warning);
  if (!state->png) throw std::bad_alloc();
  state->info = png_create_info_struct(state->png);
  if (!state->info) throw std::bad_alloc();
  if (setjmp(png_jmpbuf(state->png))) throw std::runtime_error(state->error);
  png_set_write_fn(state->png, state.get(), png_write, png_flush);
  png_set_IHDR(state->png, state->info, width, height, 8, PNG_COLOR_TYPE_RGBA,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
  png_set_compression_level(state->png, level);
  png_write_info(state->png, state->info);
  for (int y = 0; y < height; ++y) png_write_row(state->png, rgba + size_t(y) * width * 4);
  png_write_end(state->png, state->info);
}
}
