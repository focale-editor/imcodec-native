part of '../png.dart';

/// Encodes and decodes PNG through libpng.
final class NativePngCodec extends RasterCodec<PngEncodeOptions, NativePngEncoder, PngDecodeOptions, NativePngDecoder>
    with ParallelRasterCodec<PngEncodeOptions, NativePngEncoder, PngDecodeOptions, NativePngDecoder> {
  /// Creates a complete native PNG codec.
  const NativePngCodec({
    super.rasterEncoder = const NativePngEncoder(),
    super.rasterDecoder = const NativePngDecoder(),
  }) : super(
         format: ImageFormat.png,
       );
}
