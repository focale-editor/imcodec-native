// Generates original synthetic test images; no third-party image data is used.
#include <libheif/heif.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static void check(heif_error error) {
  if (error.code != heif_error_Ok) {
    std::fprintf(stderr, "%s\n", error.message);
    std::exit(1);
  }
}

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  check(heif_init(nullptr));
  for (int depth : {10, 12}) {
    heif_context* context = heif_context_alloc();
    heif_encoder* encoder = nullptr;
    check(heif_context_get_encoder_for_format(context, heif_compression_AV1, &encoder));
    check(heif_encoder_set_lossless(encoder, 1));
    check(heif_encoder_set_parameter_integer(encoder, "speed", 9));
    check(heif_encoder_set_parameter_string(encoder, "chroma", "444"));
    check(heif_encoder_set_parameter_boolean(encoder, "lossless-alpha", 1));
    heif_image* image = nullptr;
    check(heif_image_create(3, 5, heif_colorspace_RGB, heif_chroma_interleaved_RRGGBBAA_LE, &image));
    check(heif_image_add_plane(image, heif_channel_interleaved, 3, 5, depth));
    size_t stride = 0;
    uint8_t* pixels = heif_image_get_plane2(image, heif_channel_interleaved, &stride);
    const unsigned maximum = (1u << depth) - 1;
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 3; ++x) {
        for (int c = 0; c < 4; ++c) {
          const unsigned sample = c == 3 ? maximum : (unsigned(x * 37 + y * 101 + c * 223) % (maximum + 1));
          uint8_t* p = pixels + y * stride + x * 8 + c * 2;
          p[0] = uint8_t(sample);
          p[1] = uint8_t(sample >> 8);
        }
      }
    }
    heif_color_profile_nclx* profile = heif_nclx_color_profile_alloc();
    check(heif_nclx_color_profile_set_color_primaries(profile, 1));
    check(heif_nclx_color_profile_set_transfer_characteristics(profile, 13));
    check(heif_nclx_color_profile_set_matrix_coefficients(profile, 0));
    profile->full_range_flag = 1;
    check(heif_image_set_nclx_color_profile(image, profile));
    // An opaque marker tests byte preservation, not ICC profile interpretation.
    const char icc[] = "ImcodecNative synthetic ICC payload";
    check(heif_image_set_raw_color_profile(image, "prof", icc, sizeof(icc) - 1));
    heif_encoding_options* options = heif_encoding_options_alloc();
    options->output_nclx_profile = profile;
    options->save_two_colr_boxes_when_ICC_and_nclx_available = 1;
    options->image_orientation = heif_orientation_rotate_90_cw;
    heif_image_handle* handle = nullptr;
    check(heif_context_encode_image(context, image, encoder, options, &handle));
    const uint8_t exif[] = {'I', 'I', 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    const char xmp[] = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>";
    check(heif_context_add_exif_metadata(context, handle, exif, sizeof(exif)));
    check(heif_context_add_XMP_metadata(context, handle, xmp, sizeof(xmp) - 1));
    const std::string path = std::string(argv[1]) + "/rgba" + std::to_string(depth) + ".avif";
    check(heif_context_write_to_file(context, path.c_str()));
    heif_image_handle_release(handle);
    heif_encoding_options_free(options);
    heif_nclx_color_profile_free(profile);
    heif_image_release(image);
    heif_encoder_release(encoder);
    heif_context_free(context);
  }
  heif_deinit();
}
