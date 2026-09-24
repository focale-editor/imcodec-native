part of '../jpeg.dart';

/// Decodes JPEG through libjpeg-turbo.
final class NativeJpegDecoder extends NativeRasterDecoder<JpegDecodeOptions> {
  /// Creates a native JPEG decoder with bounded output allocations.
  const NativeJpegDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });

  @override
  int get codecId => 6;

  @override
  ImageFormat get format => ImageFormat.jpeg;

  @override
  JpegDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => JpegDecodeOptions(maxPixels: maxPixels);
}
