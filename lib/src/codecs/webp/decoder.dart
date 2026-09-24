part of '../webp.dart';

/// Decodes still or first-frame WebP through libwebp.
final class NativeWebPDecoder extends NativeRasterDecoder<WebPDecodeOptions> {
  /// Creates a native WebP decoder with bounded output allocations.
  const NativeWebPDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  }) : super(defaultDecodeOptions: const WebPDecodeOptions());

  @override
  int get codecId => 4;

  @override
  ImageFormat get format => ImageFormat.webp;
}
