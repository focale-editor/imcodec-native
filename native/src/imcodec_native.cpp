#include "imcodec_native.h"
#include "raster_codecs.h"

#include <libheif/heif.h>
#include <jxl/decode.h>
#include <jxl/encode.h>
#include <webp/decode.h>
#include <webp/demux.h>
#include <webp/encode.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <stdexcept>
#include <vector>

namespace {
using imcodec::Owned;
using imcodec::pixel_bytes;
using imcodec::Writer;

// Throw only inside the shim; exported entry points translate exceptions.
void check(heif_error error) {
  if (error.code != heif_error_Ok) {
    throw std::runtime_error(error.message ? error.message : "libheif failed");
  }
}

// Match the library's reference-counted initialization on every operation.
// The engine lock below protects its non-threaded global plugin state.
struct HeifSession {
  HeifSession() { check(heif_init(nullptr)); }
  ~HeifSession() { heif_deinit(); }
};

using Context = Owned<heif_context, heif_context_free>;
using Handle = Owned<heif_image_handle, heif_image_handle_release>;
using Raster = Owned<heif_image, heif_image_release>;
using Encoder = Owned<heif_encoder, heif_encoder_release>;
using JxlDecoderInstance = Owned<JxlDecoder, JxlDecoderDestroy>;
using WebPDemuxerInstance = Owned<WebPDemuxer, WebPDemuxDelete>;
using WebPAnimationDecoder = Owned<WebPAnimDecoder, WebPAnimDecoderDelete>;

// Apply libheif's own limits before parsing any attacker-controlled container.
Context read_context(const uint8_t* bytes, size_t size, size_t max_pixels,
                     size_t max_icc_bytes) {
  if (!bytes || size < 16 || !max_icc_bytes || !max_pixels) {
    throw std::runtime_error("Invalid HEIF input or allocation limit");
  }
  Context context(heif_context_alloc(), heif_context_free);
  if (!context) throw std::bad_alloc();
  heif_security_limits* limits = heif_context_get_security_limits(context.get());
  limits->max_image_size_pixels = std::min<uint64_t>(limits->max_image_size_pixels, max_pixels);
  limits->max_color_profile_size = static_cast<uint32_t>(
      std::min<size_t>(limits->max_color_profile_size, max_icc_bytes));
  heif_context_set_max_decoding_threads(context.get(), 0);
  check(heif_context_read_from_memory_without_copy(context.get(), bytes, size, nullptr));
  return context;
}

// Only the primary still image is returned; libheif applies crop/rotate/mirror.
Handle primary(heif_context* context) {
  heif_image_handle* raw_handle = nullptr;
  check(heif_context_get_primary_image_handle(context, &raw_handle));
  Handle handle(raw_handle, heif_image_handle_release);
  if (!handle) throw std::runtime_error("HEIF has no primary image");
  return handle;
}

void read_metadata(imcodec_result& result, const heif_image_handle* handle,
                   size_t max_icc_bytes, size_t max_metadata_bytes) {
  const int width = heif_image_handle_get_width(handle);
  const int height = heif_image_handle_get_height(handle);
  const int depth = std::max(heif_image_handle_get_luma_bits_per_pixel(handle),
                             heif_image_handle_get_chroma_bits_per_pixel(handle));
  if (width <= 0 || height <= 0 || depth < 1 || depth > 16) {
    throw std::runtime_error("Unsupported HEIF dimensions or sample depth");
  }
  result.width = static_cast<size_t>(width);
  result.height = static_cast<size_t>(height);
  result.source_depth = static_cast<size_t>(depth);
  const size_t icc_size = heif_image_handle_get_raw_color_profile_size(handle);
  if (icc_size > max_icc_bytes) throw std::runtime_error("ICC profile exceeds its byte limit");
  if (icc_size) {
    result.buffers[1].resize(icc_size);
    check(heif_image_handle_get_raw_color_profile(handle, result.buffers[1].data()));
  }
  if (!max_metadata_bytes) return;
  const int count = heif_image_handle_get_number_of_metadata_blocks(handle, nullptr);
  if (count < 0 || count > 4096) throw std::runtime_error("Too many HEIF metadata blocks");
  std::vector<heif_item_id> ids(static_cast<size_t>(count));
  const int actual = heif_image_handle_get_list_of_metadata_block_IDs(handle, nullptr, ids.data(), count);
  for (int i = 0; i < actual; ++i) {
    const char* type = heif_image_handle_get_metadata_type(handle, ids[i]);
    const char* content_type = heif_image_handle_get_metadata_content_type(handle, ids[i]);
    const int field = type && std::strcmp(type, "Exif") == 0 ? 2 :
        (type && std::strcmp(type, "mime") == 0 && content_type &&
         std::strcmp(content_type, "application/rdf+xml") == 0 ? 3 : 0);
    if (!field) continue;
    if (!result.buffers[field].empty()) throw std::runtime_error("Duplicate HEIF metadata packet");
    const size_t size = heif_image_handle_get_metadata_size(handle, ids[i]);
    if (size > max_metadata_bytes) throw std::runtime_error("Metadata packet exceeds its byte limit");
    result.buffers[field].resize(size);
    if (size) check(heif_image_handle_get_metadata(handle, ids[i], result.buffers[field].data()));
  }
}

// Native output may use padded rows and premultiplied alpha. Normalize both.
void copy_pixels(imcodec_result& result, heif_image* image,
                 size_t max_pixels, size_t max_bytes) {
  const int width = heif_image_get_width(image, heif_channel_interleaved);
  const int height = heif_image_get_height(image, heif_channel_interleaved);
  if (width <= 0 || height <= 0) throw std::runtime_error("Decoded HEIF has invalid dimensions");
  result.width = static_cast<size_t>(width);
  result.height = static_cast<size_t>(height);
  const size_t pixel_size = result.depth == 16 ? 8 : 4;
  const size_t byte_count = pixel_bytes(result.width, result.height, pixel_size, max_pixels, max_bytes);
  size_t stride = 0;
  const uint8_t* source = heif_image_get_plane_readonly2(image, heif_channel_interleaved, &stride);
  const size_t row_bytes = result.width * pixel_size;
  if (!source || stride < row_bytes) throw std::runtime_error("Decoded HEIF has an invalid row stride");
  std::vector<uint8_t>& pixels = result.buffers[0];
  pixels.resize(byte_count);
  for (size_t y = 0; y < result.height; ++y) {
    std::memcpy(pixels.data() + y * row_bytes, source + y * stride, row_bytes);
  }
  const bool premultiplied = heif_image_is_premultiplied_alpha(image) != 0;
  if (result.depth == 16) {
    const int significant_bits = heif_image_get_bits_per_pixel_range(image, heif_channel_interleaved);
    if (significant_bits < 1 || significant_bits > 16) throw std::runtime_error("Invalid decoded HEIF sample depth");
    const uint32_t maximum = (1u << significant_bits) - 1;
    for (size_t i = 0; i < pixels.size(); i += 2) {
      const uint32_t sample = pixels[i] | (uint32_t(pixels[i + 1]) << 8);
      const uint32_t scaled = (std::min(sample, maximum) * 65535u + maximum / 2) / maximum;
      pixels[i] = uint8_t(scaled);
      pixels[i + 1] = uint8_t(scaled >> 8);
    }
  }
  if (!premultiplied) return;
  const size_t channel_bytes = result.depth / 8;
  const uint32_t maximum = result.depth == 16 ? 65535 : 255;
  for (size_t pixel = 0; pixel < pixels.size(); pixel += pixel_size) {
    const size_t alpha_position = pixel + 3 * channel_bytes;
    const uint32_t alpha = pixels[alpha_position] |
        (channel_bytes == 2 ? uint32_t(pixels[alpha_position + 1]) << 8 : 0);
    for (size_t channel = 0; channel < 3; ++channel) {
      const size_t position = pixel + channel * channel_bytes;
      const uint32_t sample = pixels[position] |
          (channel_bytes == 2 ? uint32_t(pixels[position + 1]) << 8 : 0);
      const uint32_t straight = alpha ? std::min(maximum, (sample * maximum + alpha / 2) / alpha) : 0;
      pixels[position] = uint8_t(straight);
      if (channel_bytes == 2) pixels[position + 1] = uint8_t(straight >> 8);
    }
  }
}

// This writer never lets exceptions unwind into a codec callback.
heif_error write_heif(heif_context*, const void* data, size_t size, void* user) {
  if (!static_cast<Writer*>(user)->append(static_cast<const uint8_t*>(data), size)) {
    return {heif_error_Encoding_error, heif_suberror_Unspecified, "Encoded output exceeds its byte limit or available memory"};
  }
  return {heif_error_Ok, heif_suberror_Unspecified, "Success"};
}

void encode_heif(imcodec_result& result, const uint8_t* rgba, int width, int height,
                 int format, int quality, bool lossless, int speed, size_t max_bytes) {
  HeifSession session;
  Context context(heif_context_alloc(), heif_context_free);
  if (!context) throw std::bad_alloc();
  heif_encoder* raw_encoder = nullptr;
  check(heif_context_get_encoder_for_format(context.get(),
      format == 1 ? heif_compression_AV1 : heif_compression_HEVC, &raw_encoder));
  Encoder encoder(raw_encoder, heif_encoder_release);
  check(heif_encoder_set_lossy_quality(encoder.get(), quality));
  if (format == 1) {
    check(heif_encoder_set_parameter_integer(encoder.get(), "threads", 1));
    check(heif_encoder_set_parameter_integer(encoder.get(), "speed", speed));
    check(heif_encoder_set_parameter_boolean(encoder.get(), "lossless-alpha", 1));
    check(heif_encoder_set_lossless(encoder.get(), lossless ? 1 : 0));
    check(heif_encoder_set_parameter_string(encoder.get(), "chroma", lossless ? "444" : "420"));
  } else if (lossless) {
    throw std::runtime_error("The bundled HEIC encoder does not support lossless RGB encoding");
  }
  heif_image* raw_image = nullptr;
  check(heif_image_create(width, height, heif_colorspace_RGB, heif_chroma_interleaved_RGBA, &raw_image));
  Raster image(raw_image, heif_image_release);
  check(heif_image_add_plane(image.get(), heif_channel_interleaved, width, height, 8));
  size_t stride = 0;
  uint8_t* plane = heif_image_get_plane2(image.get(), heif_channel_interleaved, &stride);
  const size_t row_bytes = static_cast<size_t>(width) * 4;
  if (!plane || stride < row_bytes) throw std::runtime_error("Invalid HEIF encoder row stride");
  for (int y = 0; y < height; ++y) {
    std::memcpy(plane + size_t(y) * stride, rgba + size_t(y) * row_bytes, row_bytes);
  }
  Owned<heif_color_profile_nclx, heif_nclx_color_profile_free> profile(
      heif_nclx_color_profile_alloc(), heif_nclx_color_profile_free);
  if (!profile) throw std::bad_alloc();
  check(heif_nclx_color_profile_set_color_primaries(profile.get(), 1));
  check(heif_nclx_color_profile_set_transfer_characteristics(profile.get(), 13));
  check(heif_nclx_color_profile_set_matrix_coefficients(profile.get(), lossless ? 0 : 6));
  profile->full_range_flag = 1;
  check(heif_image_set_nclx_color_profile(image.get(), profile.get()));
  Owned<heif_encoding_options, heif_encoding_options_free> options(
      heif_encoding_options_alloc(), heif_encoding_options_free);
  if (!options) throw std::bad_alloc();
  options->output_nclx_profile = profile.get();
  options->save_alpha_channel = 1;
  check(heif_context_encode_image(context.get(), image.get(), encoder.get(), options.get(), nullptr));
  Writer writer{result.buffers[0], max_bytes};
  heif_writer callbacks{1, write_heif};
  check(heif_context_write(context.get(), &callbacks, &writer));
}

int write_webp(const uint8_t* data, size_t size, const WebPPicture* picture) {
  return static_cast<Writer*>(picture->custom_ptr)->append(data, size) ? 1 : 0;
}

void encode_webp(imcodec_result& result, const uint8_t* rgba, int width, int height,
                 int quality, bool lossless, int effort, size_t max_bytes) {
  WebPConfig config;
  WebPPicture picture;
  if (!WebPConfigInit(&config) || !WebPPictureInit(&picture)) throw std::runtime_error("Incompatible libwebp ABI");
  config.lossless = lossless ? 1 : 0;
  config.quality = static_cast<float>(quality);
  config.method = effort;
  config.exact = 1;
  config.alpha_quality = 100;
  config.thread_level = 0;
  if (!WebPValidateConfig(&config)) throw std::runtime_error("Invalid WebP encoder options");
  picture.use_argb = 1;
  picture.width = width;
  picture.height = height;
  Writer writer{result.buffers[0], max_bytes};
  picture.writer = write_webp;
  picture.custom_ptr = &writer;
  if (!WebPPictureImportRGBA(&picture, rgba, width * 4)) {
    WebPPictureFree(&picture);
    throw std::runtime_error("Could not allocate WebP input pixels");
  }
  const bool success = WebPEncode(&config, &picture) != 0;
  WebPPictureFree(&picture);
  if (!success) throw std::runtime_error("WebP encoding failed or exceeded its output-byte limit");
}

void check_jxl(JxlEncoderStatus status) {
  if (status != JXL_ENC_SUCCESS) throw std::runtime_error("JPEG XL encoding failed");
}

void encode_jxl(imcodec_result& result, const uint8_t* rgba, size_t size,
                int width, int height, int effort, size_t max_bytes) {
  Owned<JxlEncoder, JxlEncoderDestroy> encoder(JxlEncoderCreate(nullptr), JxlEncoderDestroy);
  if (!encoder) throw std::bad_alloc();
  JxlBasicInfo info;
  JxlEncoderInitBasicInfo(&info);
  info.xsize = static_cast<uint32_t>(width);
  info.ysize = static_cast<uint32_t>(height);
  info.bits_per_sample = 8;
  info.num_color_channels = 3;
  info.num_extra_channels = 1;
  info.alpha_bits = 8;
  info.alpha_premultiplied = JXL_FALSE;
  info.uses_original_profile = JXL_TRUE;
  check_jxl(JxlEncoderSetBasicInfo(encoder.get(), &info));
  JxlColorEncoding color;
  JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
  check_jxl(JxlEncoderSetColorEncoding(encoder.get(), &color));
  JxlEncoderFrameSettings* settings = JxlEncoderFrameSettingsCreate(encoder.get(), nullptr);
  if (!settings) throw std::bad_alloc();
  check_jxl(JxlEncoderSetFrameLossless(settings, JXL_TRUE));
  check_jxl(JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, effort));
  check_jxl(JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_KEEP_INVISIBLE, 1));
  const JxlPixelFormat pixels{4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
  check_jxl(JxlEncoderAddImageFrame(settings, &pixels, rgba, size));
  JxlEncoderCloseInput(encoder.get());
  std::vector<uint8_t>& output = result.buffers[0];
  output.resize(std::min<size_t>(65536, max_bytes));
  size_t used = 0;
  while (true) {
    uint8_t* next = output.data() + used;
    size_t available = output.size() - used;
    const JxlEncoderStatus status = JxlEncoderProcessOutput(encoder.get(), &next, &available);
    used = output.size() - available;
    if (status == JXL_ENC_SUCCESS) break;
    if (status != JXL_ENC_NEED_MORE_OUTPUT) check_jxl(status);
    if (output.size() == max_bytes) throw std::runtime_error("JPEG XL output exceeds its byte limit");
    output.resize(output.size() + std::min(output.size(), max_bytes - output.size()));
  }
  output.resize(used);
}

void check_jxl_decoder(JxlDecoderStatus status, const char* message) {
  if (status != JXL_DEC_SUCCESS) throw std::runtime_error(message);
}

// Retain the profile that describes libjxl's actual output pixels. This can be
// the authored ICC payload or a compact profile synthesized from structured
// JPEG XL colour metadata.
void read_jxl_icc(imcodec_result& result, const JxlDecoder* decoder,
                  size_t max_icc_bytes) {
  size_t size = 0;
  const JxlDecoderStatus size_status = JxlDecoderGetICCProfileSize(
      decoder, JXL_COLOR_PROFILE_TARGET_DATA, &size);
  if (size_status == JXL_DEC_ERROR) return;
  check_jxl_decoder(size_status, "JPEG XL colour profile is incomplete");
  if (size > max_icc_bytes) {
    throw std::runtime_error("JPEG XL ICC profile exceeds its byte limit");
  }
  if (!size) return;
  result.buffers[1].resize(size);
  check_jxl_decoder(
      JxlDecoderGetColorAsICCProfile(decoder, JXL_COLOR_PROFILE_TARGET_DATA,
                                    result.buffers[1].data(), size),
      "Could not read the JPEG XL colour profile");
}

JxlDecoderInstance create_jxl_decoder(const uint8_t* bytes, size_t size,
                                      int events) {
  if (!bytes || size < 2 || JxlSignatureCheck(bytes, size) < JXL_SIG_CODESTREAM) {
    throw std::runtime_error("Invalid JPEG XL input");
  }
  JxlDecoderInstance decoder(JxlDecoderCreate(nullptr), JxlDecoderDestroy);
  if (!decoder) throw std::bad_alloc();
  check_jxl_decoder(JxlDecoderSubscribeEvents(decoder.get(), events),
                    "Could not configure the JPEG XL decoder");
  check_jxl_decoder(JxlDecoderSetUnpremultiplyAlpha(decoder.get(), JXL_TRUE),
                    "Could not request straight JPEG XL alpha");
  check_jxl_decoder(JxlDecoderSetInput(decoder.get(), bytes, size),
                    "Could not provide JPEG XL input");
  JxlDecoderCloseInput(decoder.get());
  return decoder;
}

void read_jxl_basic_info(imcodec_result& result, const JxlDecoder* decoder,
                         JxlBasicInfo& info) {
  check_jxl_decoder(JxlDecoderGetBasicInfo(decoder, &info),
                    "Could not read JPEG XL image information");
  if (!info.xsize || !info.ysize ||
      (info.num_color_channels != 1 && info.num_color_channels != 3) ||
      !info.bits_per_sample || info.bits_per_sample > 32 ||
      info.exponent_bits_per_sample > info.bits_per_sample ||
      info.alpha_bits > 32 || info.alpha_exponent_bits > info.alpha_bits) {
    throw std::runtime_error("Unsupported JPEG XL dimensions or sample layout");
  }
  result.width = info.xsize;
  result.height = info.ysize;
  const bool floating = info.exponent_bits_per_sample ||
                        info.alpha_exponent_bits;
  result.source_depth = floating
      ? 32
      : std::max(info.bits_per_sample, info.alpha_bits);
}

void decode_jxl(imcodec_result& result, const uint8_t* bytes, size_t size,
                size_t max_pixels, size_t max_decoded_bytes,
                bool preserve_depth, size_t max_icc_bytes) {
  JxlDecoderInstance decoder = create_jxl_decoder(
      bytes, size, JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING |
                       JXL_DEC_FULL_IMAGE);
  JxlBasicInfo info{};
  JxlPixelFormat pixel_format{4, JXL_TYPE_UINT8, JXL_LITTLE_ENDIAN, 0};
  bool have_info = false;
  bool have_output = false;
  while (true) {
    const JxlDecoderStatus status = JxlDecoderProcessInput(decoder.get());
    if (status == JXL_DEC_BASIC_INFO) {
      read_jxl_basic_info(result, decoder.get(), info);
      const bool floating = info.exponent_bits_per_sample ||
                            info.alpha_exponent_bits;
      const uint32_t widest_bits = std::max(info.bits_per_sample,
                                            info.alpha_bits);
      if (preserve_depth && floating) {
        result.depth = 32;
        pixel_format.data_type = JXL_TYPE_FLOAT;
      } else if (preserve_depth && widest_bits > 8) {
        result.depth = 16;
        pixel_format.data_type = JXL_TYPE_UINT16;
      } else {
        result.depth = 8;
        pixel_format.data_type = JXL_TYPE_UINT8;
      }
      const size_t bytes_per_pixel = result.depth == 32 ? 16 :
                                     result.depth == 16 ? 8 : 4;
      pixel_bytes(result.width, result.height, bytes_per_pixel, max_pixels,
                  max_decoded_bytes);
      have_info = true;
    } else if (status == JXL_DEC_COLOR_ENCODING) {
      read_jxl_icc(result, decoder.get(), max_icc_bytes);
    } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
      if (!have_info || have_output) {
        throw std::runtime_error("Invalid JPEG XL frame sequence");
      }
      size_t required = 0;
      check_jxl_decoder(
          JxlDecoderImageOutBufferSize(decoder.get(), &pixel_format, &required),
          "Could not size the JPEG XL output buffer");
      const size_t bytes_per_pixel = result.depth == 32 ? 16 :
                                     result.depth == 16 ? 8 : 4;
      const size_t bounded = pixel_bytes(result.width, result.height,
                                         bytes_per_pixel, max_pixels,
                                         max_decoded_bytes);
      if (required != bounded) {
        throw std::runtime_error("Unexpected JPEG XL output buffer size");
      }
      result.buffers[0].resize(required);
      check_jxl_decoder(
          JxlDecoderSetImageOutBuffer(decoder.get(), &pixel_format,
                                      result.buffers[0].data(), required),
          "Could not configure the JPEG XL output buffer");
      have_output = true;
    } else if (status == JXL_DEC_FULL_IMAGE) {
      if (!have_output) throw std::runtime_error("JPEG XL returned no pixels");
      return;
    } else if (status == JXL_DEC_NEED_MORE_INPUT) {
      throw std::runtime_error("The JPEG XL input is truncated");
    } else if (status == JXL_DEC_ERROR) {
      throw std::runtime_error("JPEG XL decoding failed");
    } else if (status == JXL_DEC_SUCCESS) {
      throw std::runtime_error("JPEG XL contains no visible image");
    } else {
      throw std::runtime_error("Unsupported JPEG XL decoder event");
    }
  }
}

void inspect_jxl(imcodec_result& result, const uint8_t* bytes, size_t size,
                 size_t max_icc_bytes) {
  JxlDecoderInstance decoder = create_jxl_decoder(
      bytes, size, JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING);
  JxlBasicInfo info{};
  bool have_info = false;
  while (true) {
    const JxlDecoderStatus status = JxlDecoderProcessInput(decoder.get());
    if (status == JXL_DEC_BASIC_INFO) {
      read_jxl_basic_info(result, decoder.get(), info);
      result.depth = result.source_depth;
      have_info = true;
    } else if (status == JXL_DEC_COLOR_ENCODING) {
      if (!have_info) throw std::runtime_error("Invalid JPEG XL header sequence");
      read_jxl_icc(result, decoder.get(), max_icc_bytes);
      return;
    } else if (status == JXL_DEC_NEED_MORE_INPUT) {
      throw std::runtime_error("The JPEG XL header is truncated");
    } else if (status == JXL_DEC_ERROR) {
      throw std::runtime_error("JPEG XL inspection failed");
    } else if (status == JXL_DEC_SUCCESS) {
      if (have_info) return;
      throw std::runtime_error("JPEG XL contains no image information");
    } else {
      throw std::runtime_error("Unexpected JPEG XL inspection event");
    }
  }
}

void copy_webp_chunk(std::vector<uint8_t>& output,
                     const WebPDemuxer* demuxer, const char fourcc[4],
                     size_t limit, bool reject_duplicates) {
  WebPChunkIterator iterator{};
  if (!WebPDemuxGetChunk(demuxer, fourcc, reject_duplicates ? 1 : 0,
                         &iterator)) {
    return;
  }
  try {
    if (reject_duplicates && iterator.num_chunks != 1) {
      throw std::runtime_error("WebP has duplicate ICC profiles");
    }
    if (iterator.chunk.size > limit) {
      throw std::runtime_error("WebP metadata exceeds its byte limit");
    }
    if (iterator.chunk.size) {
      if (!iterator.chunk.bytes) {
        throw std::runtime_error("WebP metadata points to a null buffer");
      }
      output.assign(iterator.chunk.bytes,
                    iterator.chunk.bytes + iterator.chunk.size);
    }
  } catch (...) {
    WebPDemuxReleaseChunkIterator(&iterator);
    throw;
  }
  WebPDemuxReleaseChunkIterator(&iterator);
}

WebPDemuxerInstance read_webp_metadata(imcodec_result& result,
                                      const uint8_t* bytes, size_t size,
                                      size_t max_icc_bytes,
                                      size_t max_metadata_bytes) {
  const WebPData data{bytes, size};
  WebPDemuxerInstance demuxer(WebPDemux(&data), WebPDemuxDelete);
  if (!demuxer) throw std::runtime_error("Invalid WebP container");
  copy_webp_chunk(result.buffers[1], demuxer.get(), "ICCP", max_icc_bytes,
                  true);
  if (max_metadata_bytes) {
    copy_webp_chunk(result.buffers[2], demuxer.get(), "EXIF",
                    max_metadata_bytes, false);
    copy_webp_chunk(result.buffers[3], demuxer.get(), "XMP ",
                    max_metadata_bytes, false);
  }
  return demuxer;
}

WebPBitstreamFeatures read_webp_features(const uint8_t* bytes, size_t size) {
  if (!bytes || size < 20) throw std::runtime_error("Invalid WebP input");
  WebPBitstreamFeatures features{};
  if (WebPGetFeatures(bytes, size, &features) != VP8_STATUS_OK ||
      features.width <= 0 || features.height <= 0) {
    throw std::runtime_error("Invalid or truncated WebP input");
  }
  return features;
}

void decode_webp(imcodec_result& result, const uint8_t* bytes, size_t size,
                  size_t max_pixels, size_t max_decoded_bytes,
                  size_t max_icc_bytes) {
  const WebPBitstreamFeatures features = read_webp_features(bytes, size);
  result.width = static_cast<size_t>(features.width);
  result.height = static_cast<size_t>(features.height);
  result.depth = 8;
  result.source_depth = 8;
  const size_t output_size = pixel_bytes(result.width, result.height, 4,
                                         max_pixels, max_decoded_bytes);
  WebPDemuxerInstance demuxer = read_webp_metadata(
      result, bytes, size, max_icc_bytes, 0);
  result.buffers[0].resize(output_size);
  if (!features.has_animation) {
    if (!WebPDecodeRGBAInto(bytes, size, result.buffers[0].data(), output_size,
                            features.width * 4)) {
      throw std::runtime_error("WebP decoding failed");
    }
    return;
  }

  const WebPData data{bytes, size};
  WebPAnimDecoderOptions options;
  if (!WebPAnimDecoderOptionsInit(&options)) {
    throw std::runtime_error("Incompatible libwebp animation ABI");
  }
  options.color_mode = MODE_RGBA;
  options.use_threads = 0;
  WebPAnimationDecoder decoder(WebPAnimDecoderNew(&data, &options),
                               WebPAnimDecoderDelete);
  if (!decoder) throw std::runtime_error("Could not create a WebP animation decoder");
  WebPAnimInfo info{};
  if (!WebPAnimDecoderGetInfo(decoder.get(), &info) ||
      info.canvas_width != result.width || info.canvas_height != result.height) {
    throw std::runtime_error("Invalid WebP animation canvas");
  }
  uint8_t* canvas = nullptr;
  int timestamp = 0;
  if (!WebPAnimDecoderGetNext(decoder.get(), &canvas, &timestamp) || !canvas) {
    throw std::runtime_error("WebP animation contains no visible frame");
  }
  std::memcpy(result.buffers[0].data(), canvas, output_size);
}

void inspect_webp(imcodec_result& result, const uint8_t* bytes, size_t size,
                   size_t max_icc_bytes, size_t max_metadata_bytes) {
  const WebPBitstreamFeatures features = read_webp_features(bytes, size);
  result.width = static_cast<size_t>(features.width);
  result.height = static_cast<size_t>(features.height);
  result.depth = 8;
  result.source_depth = 8;
  read_webp_metadata(result, bytes, size, max_icc_bytes, max_metadata_bytes);
}

// Scalar codec builds contain process-global initialization and strategy tables.
// Isolates can call FFI concurrently: serialize each engine, not all engines.
std::mutex& codec_mutex(int format) {
  static std::mutex heif_mutex;
  static std::mutex jxl_mutex;
  static std::mutex raster_mutexes[6];
  return format >= 4 && format <= 9 ? raster_mutexes[format - 4] : format == 3 ? jxl_mutex : heif_mutex;
}

// Result allocation failure is the only error represented by a null pointer.
template <typename Function>
imcodec_result* operation(int format, Function body) noexcept {
  imcodec_result* result = new (std::nothrow) imcodec_result;
  if (!result) return nullptr;
  try {
    std::lock_guard<std::mutex> lock(codec_mutex(format));
    body(*result);
  } catch (const std::exception& error) {
    std::snprintf(result->error, sizeof(result->error), "%s", error.what());
  } catch (...) {
    std::snprintf(result->error, sizeof(result->error), "Unknown native codec failure");
  }
  return result;
}
}

imcodec_result* imcodec_decode(const uint8_t* bytes, size_t size, int format,
    size_t max_pixels, size_t max_decoded_bytes, int preserve_depth, size_t max_icc_bytes) {
  return operation(format, [&](imcodec_result& result) {
    if (format == 1 || format == 2) {
      HeifSession session;
      Context context = read_context(bytes, size, max_pixels, max_icc_bytes);
      Handle handle = primary(context.get());
      read_metadata(result, handle.get(), max_icc_bytes, 0);
      result.depth = preserve_depth && result.source_depth > 8 ? 16 : 8;
      pixel_bytes(result.width, result.height, result.depth == 16 ? 8 : 4, max_pixels, max_decoded_bytes);
      heif_image* raw_image = nullptr;
      check(heif_decode_image(handle.get(), &raw_image, heif_colorspace_RGB,
          result.depth == 16 ? heif_chroma_interleaved_RRGGBBAA_LE : heif_chroma_interleaved_RGBA, nullptr));
      Raster image(raw_image, heif_image_release);
      if (!image) throw std::runtime_error("HEIF decoder returned no image");
      copy_pixels(result, image.get(), max_pixels, max_decoded_bytes);
    } else if (format == 3) {
      decode_jxl(result, bytes, size, max_pixels, max_decoded_bytes,
                 preserve_depth != 0, max_icc_bytes);
    } else if (format == 4) {
      decode_webp(result, bytes, size, max_pixels, max_decoded_bytes,
                  max_icc_bytes);
    } else if (format == 5) {
      imcodec::read_png(result, bytes, size, imcodec::RasterLimits{max_pixels, max_decoded_bytes, max_icc_bytes, 0, preserve_depth != 0}, false);
    } else if (format == 6) {
      imcodec::read_jpeg(result, bytes, size, imcodec::RasterLimits{max_pixels, max_decoded_bytes, max_icc_bytes, 0, preserve_depth != 0}, false);
    } else if (format == 7) {
      imcodec::read_qoi(result, bytes, size, imcodec::RasterLimits{max_pixels, max_decoded_bytes, max_icc_bytes, 0, preserve_depth != 0}, false);
    } else if (format == 8) {
      imcodec::read_tiff(result, bytes, size, imcodec::RasterLimits{max_pixels, max_decoded_bytes, max_icc_bytes, 0, preserve_depth != 0}, false);
    } else if (format == 9) {
      imcodec::read_exr(result, bytes, size, imcodec::RasterLimits{max_pixels, max_decoded_bytes, max_icc_bytes, 0, preserve_depth != 0}, false);
    } else {
      throw std::runtime_error("Unsupported decode format");
    }
  });
}

imcodec_result* imcodec_inspect(const uint8_t* bytes, size_t size, int format,
    size_t max_icc_bytes, size_t max_metadata_bytes) {
  return operation(format, [&](imcodec_result& result) {
    if (format == 1 || format == 2) {
      HeifSession session;
      Context context = read_context(bytes, size, 100000000, max_icc_bytes);
      Handle handle = primary(context.get());
      read_metadata(result, handle.get(), max_icc_bytes, max_metadata_bytes);
      // Imcodec metadata describes dimensions before container orientation.
      const int width = heif_image_handle_get_ispe_width(handle.get());
      const int height = heif_image_handle_get_ispe_height(handle.get());
      if (width <= 0 || height <= 0) throw std::runtime_error("Invalid HEIF spatial extent");
      result.width = static_cast<size_t>(width);
      result.height = static_cast<size_t>(height);
    } else if (format == 3) {
      inspect_jxl(result, bytes, size, max_icc_bytes);
    } else if (format == 4) {
      inspect_webp(result, bytes, size, max_icc_bytes, max_metadata_bytes);
    } else if (format == 5) {
      imcodec::read_png(result, bytes, size, imcodec::RasterLimits{100000000, 400000000, max_icc_bytes, max_metadata_bytes, false}, true);
    } else if (format == 6) {
      imcodec::read_jpeg(result, bytes, size, imcodec::RasterLimits{100000000, 400000000, max_icc_bytes, max_metadata_bytes, false}, true);
    } else if (format == 7) {
      imcodec::read_qoi(result, bytes, size, imcodec::RasterLimits{100000000, 400000000, max_icc_bytes, max_metadata_bytes, false}, true);
    } else if (format == 8) {
      imcodec::read_tiff(result, bytes, size, imcodec::RasterLimits{100000000, 400000000, max_icc_bytes, max_metadata_bytes, false}, true);
    } else if (format == 9) {
      imcodec::read_exr(result, bytes, size, imcodec::RasterLimits{100000000, 400000000, max_icc_bytes, max_metadata_bytes, false}, true);
    } else {
      throw std::runtime_error("Unsupported inspection format");
    }
  });
}

imcodec_result* imcodec_encode(const uint8_t* rgba, size_t size, int width, int height,
    int format, int quality, int lossless, int speed, size_t max_output_bytes) {
  return operation(format, [&](imcodec_result& result) {
    if (!rgba || width <= 0 || height <= 0 || !max_output_bytes || quality < 0 || quality > 100 ||
        size != pixel_bytes(size_t(width), size_t(height), 4, std::numeric_limits<size_t>::max(), size)) {
      throw std::runtime_error("Invalid encoder input or allocation limit");
    }
    if (format == 1 || format == 2) {
      encode_heif(result, rgba, width, height, format, quality, lossless != 0, speed, max_output_bytes);
    } else if (format == 3) {
      encode_jxl(result, rgba, size, width, height, speed, max_output_bytes);
    } else if (format == 4) {
      if (width > WEBP_MAX_DIMENSION || height > WEBP_MAX_DIMENSION) throw std::runtime_error("WebP dimensions exceed 16383 pixels");
      encode_webp(result, rgba, width, height, quality, lossless != 0, speed, max_output_bytes);
    } else if (format == 5) {
      imcodec::encode_png(result, rgba, width, height, speed, max_output_bytes);
    } else if (format == 6) {
      imcodec::encode_jpeg(result, rgba, width, height, quality, speed, max_output_bytes);
    } else if (format == 7) {
      imcodec::encode_qoi(result, rgba, width, height, max_output_bytes);
    } else if (format == 8) {
      imcodec::encode_tiff(result, rgba, width, height, speed, max_output_bytes);
    } else if (format == 9) {
      imcodec::encode_exr(result, rgba, width, height, speed, max_output_bytes);
    } else {
      throw std::runtime_error("Unsupported encode format");
    }
  });
}

void imcodec_result_free(imcodec_result* result) { delete result; }

size_t imcodec_result_number(const imcodec_result* result, int field) {
  if (!result) return 0;
  switch (field) {
    case 0: return result->width;
    case 1: return result->height;
    case 2: return result->depth;
    case 3: return result->source_depth;
    case 4: case 5: case 6: case 7: return result->buffers[field - 4].size();
    default: return 0;
  }
}

const uint8_t* imcodec_result_data(const imcodec_result* result, int field) {
  return result && field >= 0 && field < 4 ? result->buffers[field].data() : nullptr;
}

const char* imcodec_result_error(const imcodec_result* result) {
  return result ? result->error : "Could not allocate a native codec result";
}

const char* imcodec_version(void) { return "libheif 1.21.2; libaom 3.14.1; libde265 1.1.2; Kvazaar 2.3.2; libjxl 0.12.0; libwebp 1.6.0; libpng 1.6.58; libjpeg-turbo 3.2.0; QOI 97bacc8; libtiff 4.7.2; OpenEXR 3.4.14"; }
