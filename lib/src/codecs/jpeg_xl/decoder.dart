part of '../jpeg_xl.dart';

/// Decodes JPEG XL through libjxl to straight-alpha RGBA samples.
final class NativeJpegXlDecoder extends NativeRasterDecoder<JpegXlDecodeOptions> {
  /// Creates a native JPEG XL decoder with bounded output allocations.
  const NativeJpegXlDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });

  @override
  int get codecId => 3;

  @override
  ImageFormat get format => ImageFormat.jpegXl;

  @override
  JpegXlDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => JpegXlDecodeOptions(maxPixels: maxPixels);
}
