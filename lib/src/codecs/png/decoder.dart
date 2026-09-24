part of '../png.dart';

/// Decodes PNG through libpng.
final class NativePngDecoder extends NativeRasterDecoder<PngDecodeOptions> {
  /// Creates a native PNG decoder with bounded output allocations.
  const NativePngDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });

  @override
  int get codecId => 5;

  @override
  ImageFormat get format => ImageFormat.png;

  @override
  PngDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => PngDecodeOptions(maxPixels: maxPixels);
}
