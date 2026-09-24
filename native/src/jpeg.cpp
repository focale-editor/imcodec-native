#include "raster_codecs.h"

#include <cstdio>
#include <jpeglib.h>
#include <jerror.h>
#include <algorithm>
#include <array>
#include <csetjmp>
#include <cstring>
#include <limits>

namespace imcodec {
namespace {
struct JpegError {
  jpeg_error_mgr base{};
  std::jmp_buf jump;
  char message[JMSG_LENGTH_MAX] = {};
};
void jpeg_failure(j_common_ptr codec) {
  auto* error = reinterpret_cast<JpegError*>(codec->err);
  codec->err->format_message(codec, error->message);
  std::longjmp(error->jump, 1);
}
void jpeg_message(j_common_ptr codec, int level) {
  if (level < 0) jpeg_failure(codec);
}
struct JpegReader {
  jpeg_decompress_struct codec{};
  JpegError error;
  std::vector<uint8_t> row;
  std::vector<J12SAMPLE> row12;
  std::vector<J16SAMPLE> row16;
  JpegReader() {
    codec.err = jpeg_std_error(&error.base);
    error.base.error_exit = jpeg_failure;
    error.base.emit_message = jpeg_message;
  }
  ~JpegReader() { jpeg_destroy_decompress(&codec); }
};
struct JpegWriter {
  jpeg_compress_struct codec{};
  JpegError error;
  jpeg_destination_mgr destination{};
  std::array<JOCTET, 4096> buffer;
  Writer writer;
  JpegWriter(std::vector<uint8_t>& output, size_t limit) : writer{output, limit} {
    codec.err = jpeg_std_error(&error.base);
    error.base.error_exit = jpeg_failure;
    error.base.emit_message = jpeg_message;
    codec.client_data = this;
  }
  ~JpegWriter() { jpeg_destroy_compress(&codec); }
};
void jpeg_output_init(j_compress_ptr codec) {
  auto* state = static_cast<JpegWriter*>(codec->client_data);
  codec->dest->next_output_byte = state->buffer.data();
  codec->dest->free_in_buffer = state->buffer.size();
}
boolean jpeg_output_full(j_compress_ptr codec) {
  auto* state = static_cast<JpegWriter*>(codec->client_data);
  if (!state->writer.append(state->buffer.data(), state->buffer.size())) ERREXIT(codec, JERR_FILE_WRITE);
  jpeg_output_init(codec);
  return TRUE;
}
void jpeg_output_end(j_compress_ptr codec) {
  auto* state = static_cast<JpegWriter*>(codec->client_data);
  if (!state->writer.append(state->buffer.data(), state->buffer.size() - codec->dest->free_in_buffer)) ERREXIT(codec, JERR_FILE_WRITE);
}

// Parse bounded APP payloads directly, avoiding libjpeg's unbounded marker list.
void jpeg_metadata(imcodec_result& result, const uint8_t* bytes, size_t size, const RasterLimits& limits) {
  std::array<const uint8_t*, 256> profiles{};
  std::array<size_t, 256> lengths{};
  unsigned total = 0;
  size_t profile_size = 0;
  size_t position = 2;
  while (position < size) {
    if (bytes[position++] != 0xff) throw std::runtime_error("Invalid JPEG marker");
    while (position < size && bytes[position] == 0xff) ++position;
    if (position == size) throw std::runtime_error("Truncated JPEG marker");
    const unsigned marker = bytes[position++];
    if (marker == 0xda || marker == 0xd9) break;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (size - position < 2) throw std::runtime_error("Truncated JPEG marker length");
    const size_t length = size_t(bytes[position]) * 256 + bytes[position + 1];
    if (length < 2 || length > size - position) throw std::runtime_error("Invalid JPEG marker length");
    const uint8_t* data = bytes + position + 2;
    const size_t count = length - 2;
    if (marker == 0xe2 && count >= 14 && std::memcmp(data, "ICC_PROFILE\0", 12) == 0) {
      const unsigned index = data[12];
      if (!index || !data[13] || index > data[13] || profiles[index] || (total && total != data[13])) throw std::runtime_error("Invalid JPEG ICC sequence");
      total = data[13];
      if (count - 14 > limits.icc - profile_size) throw std::runtime_error("JPEG ICC profile exceeds its byte limit");
      profiles[index] = data + 14;
      lengths[index] = count - 14;
      profile_size += count - 14;
    } else if (limits.metadata && marker == 0xe1 && count >= 6 && std::memcmp(data, "Exif\0\0", 6) == 0) {
      if (count - 6 > limits.metadata) throw std::runtime_error("JPEG EXIF metadata exceeds its byte limit");
      result.buffers[2].assign(data + 6, data + count);
    } else if (limits.metadata && marker == 0xe1 && count >= 29 && std::memcmp(data, "http://ns.adobe.com/xap/1.0/\0", 29) == 0) {
      if (count - 29 > limits.metadata) throw std::runtime_error("JPEG XMP metadata exceeds its byte limit");
      result.buffers[3].assign(data + 29, data + count);
    }
    position += length;
  }
  for (unsigned i = 1; i <= total; ++i) {
    if (!profiles[i]) throw std::runtime_error("Incomplete JPEG ICC sequence");
    result.buffers[1].insert(result.buffers[1].end(), profiles[i], profiles[i] + lengths[i]);
  }
}
}

void read_jpeg(imcodec_result& result, const uint8_t* bytes, size_t size,
               const RasterLimits& limits, bool inspect) {
  if (!bytes || size < 4 || bytes[0] != 0xff || bytes[1] != 0xd8 || size > std::numeric_limits<unsigned long>::max()) throw std::runtime_error("Invalid JPEG input");
  jpeg_metadata(result, bytes, size, limits);
  auto state = std::make_unique<JpegReader>();
  if (setjmp(state->error.jump)) throw std::runtime_error(state->error.message);
  jpeg_create_decompress(&state->codec);
  jpeg_mem_src(&state->codec, bytes, static_cast<unsigned long>(size));
  jpeg_read_header(&state->codec, TRUE);
  result.width = state->codec.image_width;
  result.height = state->codec.image_height;
  result.source_depth = state->codec.data_precision;
  result.depth = limits.preserve && result.source_depth > 8 ? 16 : 8;
  if (inspect) return;
  result.buffers[0].resize(pixel_bytes(result.width, result.height, result.depth / 2, limits.pixels, limits.bytes));
  const bool cmyk = state->codec.jpeg_color_space == JCS_CMYK || state->codec.jpeg_color_space == JCS_YCCK;
  state->codec.out_color_space = cmyk ? JCS_CMYK : JCS_EXT_RGBA;
  if (cmyk && result.source_depth != 8) throw std::runtime_error("High-depth CMYK JPEG is unsupported");
  // CMYK conversion produces RGB samples; its original four-channel profile
  // cannot describe those pixels. Inspection still retains the source profile.
  if (cmyk) result.buffers[1].clear();
  jpeg_start_decompress(&state->codec);
  const size_t samples = result.width * 4;
  if (result.source_depth <= 8) state->row.resize(samples);
  else if (result.source_depth <= 12) state->row12.resize(samples);
  else state->row16.resize(samples);
  while (state->codec.output_scanline < state->codec.output_height) {
    const size_t y = state->codec.output_scanline;
    if (result.source_depth <= 8) {
      JSAMPROW row = state->row.data();
      if (jpeg_read_scanlines(&state->codec, &row, 1) != 1) throw std::runtime_error("Incomplete JPEG scanline");
    } else if (result.source_depth <= 12) {
      J12SAMPROW row = state->row12.data();
      if (jpeg12_read_scanlines(&state->codec, &row, 1) != 1) throw std::runtime_error("Incomplete JPEG scanline");
    } else {
      J16SAMPROW row = state->row16.data();
      if (jpeg16_read_scanlines(&state->codec, &row, 1) != 1) throw std::runtime_error("Incomplete JPEG scanline");
    }
    uint8_t* target = result.buffers[0].data() + y * samples * (result.depth / 8);
    if (result.source_depth <= 8) {
      std::memcpy(target, state->row.data(), samples);
      if (result.source_depth < 8) {
        const unsigned maximum = (1u << result.source_depth) - 1;
        for (size_t i = 0; i < samples; ++i) target[i] = i % 4 == 3 ? 255 : (unsigned(target[i]) * 255 + maximum / 2) / maximum;
      }
      if (cmyk) {
        for (size_t i = 0; i < samples; i += 4) {
          const unsigned k = state->row[i + 3];
          for (size_t c = 0; c < 3; ++c) {
            target[i + c] = state->codec.saw_Adobe_marker ? (unsigned(state->row[i + c]) * k + 127) / 255 : ((255 - unsigned(state->row[i + c])) * (255 - k) + 127) / 255;
          }
          target[i + 3] = 255;
        }
      }
    } else {
      const uint32_t maximum = (1u << result.source_depth) - 1;
      for (size_t i = 0; i < samples; ++i) {
        const uint32_t value = i % 4 == 3 ? maximum : result.source_depth <= 12 ? state->row12[i] : state->row16[i];
        if (result.depth == 16) {
          const uint32_t scaled = (value * 65535u + maximum / 2) / maximum;
          target[i * 2] = scaled & 255;
          target[i * 2 + 1] = scaled >> 8;
        } else target[i] = (value * 255u + maximum / 2) / maximum;
      }
    }
  }
  jpeg_finish_decompress(&state->codec);
}

void encode_jpeg(imcodec_result& result, const uint8_t* rgba, int width, int height,
                 int quality, int chroma, size_t max_bytes) {
  if (chroma < 0 || chroma > 1) throw std::runtime_error("Invalid JPEG chroma sampling");
  auto state = std::make_unique<JpegWriter>(result.buffers[0], max_bytes);
  if (setjmp(state->error.jump)) throw std::runtime_error(state->error.message);
  jpeg_create_compress(&state->codec);
  state->codec.dest = &state->destination;
  state->destination.init_destination = jpeg_output_init;
  state->destination.empty_output_buffer = jpeg_output_full;
  state->destination.term_destination = jpeg_output_end;
  state->codec.image_width = width;
  state->codec.image_height = height;
  state->codec.input_components = 4;
  state->codec.in_color_space = JCS_EXT_RGBA;
  jpeg_set_defaults(&state->codec);
  jpeg_set_quality(&state->codec, quality, TRUE);
  state->codec.comp_info[0].h_samp_factor = chroma == 1 ? 2 : 1;
  state->codec.comp_info[0].v_samp_factor = chroma == 1 ? 2 : 1;
  jpeg_start_compress(&state->codec, TRUE);
  while (state->codec.next_scanline < state->codec.image_height) {
    JSAMPROW row = const_cast<JSAMPROW>(rgba + size_t(state->codec.next_scanline) * width * 4);
    jpeg_write_scanlines(&state->codec, &row, 1);
  }
  jpeg_finish_compress(&state->codec);
}
}
