part of '../webp.dart';

/// Decodes still or first-frame WebP through libwebp.
final class NativeWebPDecoder extends NativeRasterDecoder<WebPDecodeOptions> {
  /// Creates a native WebP decoder with bounded output allocations.
  const NativeWebPDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });

  @override
  int get codecId => 4;

  @override
  ImageFormat get format => ImageFormat.webp;

  @override
  WebPDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => WebPDecodeOptions(maxPixels: maxPixels);
}
