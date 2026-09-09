part of '../webp.dart';

/// Encodes and decodes WebP through libwebp.
final class NativeWebPCodec extends RasterCodec<WebPEncodeOptions, NativeWebPEncoder, WebPDecodeOptions, NativeWebPDecoder>
    with ParallelRasterCodec<WebPEncodeOptions, NativeWebPEncoder, WebPDecodeOptions, NativeWebPDecoder> {
  /// Creates a complete native WebP codec.
  const NativeWebPCodec({
    super.rasterEncoder = const NativeWebPEncoder(),
    super.rasterDecoder = const NativeWebPDecoder(),
  }) : super(
         format: ImageFormat.webp,
       );
}
