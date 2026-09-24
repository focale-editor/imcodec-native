#ifndef IMCODEC_NATIVE_H
#define IMCODEC_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define IMCODEC_EXPORT __declspec(dllexport)
#else
#define IMCODEC_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* All results, including errors, must be released with imcodec_result_free.
 * No borrowed input or result pointer survives a call to that function.
 * Formats: 1 = AVIF, 2 = HEIF/HEIC, 3 = JPEG XL, 4 = WebP,
 * 5 = PNG, 6 = JPEG, 7 = QOI, 8 = TIFF, 9 = OpenEXR.
 * Every format supports decoding and encoding. No C++ exception crosses this
 * API. */
typedef struct imcodec_result imcodec_result;
IMCODEC_EXPORT imcodec_result* imcodec_decode(const uint8_t* bytes, size_t size,
    int format, size_t max_pixels, size_t max_decoded_bytes, int preserve_depth,
    size_t max_icc_bytes);
IMCODEC_EXPORT imcodec_result* imcodec_inspect(const uint8_t* bytes, size_t size,
    int format, size_t max_icc_bytes, size_t max_metadata_bytes);
IMCODEC_EXPORT imcodec_result* imcodec_encode(const uint8_t* rgba, size_t size,
    int width, int height, int format, int quality, int lossless, int speed,
    size_t max_output_bytes);
IMCODEC_EXPORT void imcodec_result_free(imcodec_result* result);
/* Numbers: width, height, sample depth, source depth, data size, ICC size,
 * EXIF size, XMP size (field identifiers 0 through 7). */
IMCODEC_EXPORT size_t imcodec_result_number(const imcodec_result* result, int field);
/* Byte vectors: raster/encoded data, ICC, EXIF, XMP. */
IMCODEC_EXPORT const uint8_t* imcodec_result_data(const imcodec_result* result, int field);
IMCODEC_EXPORT const char* imcodec_result_error(const imcodec_result* result);
IMCODEC_EXPORT const char* imcodec_version(void);

#ifdef __cplusplus
}
#endif
#endif
