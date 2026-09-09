part of '../avif.dart';

/// Encodes and decodes AVIF with the bundled AV1 engine.
final class AvifCodec extends RasterCodec<AvifEncodeOptions, AvifEncoder, AvifDecodeOptions, AvifDecoder> with ParallelRasterCodec<AvifEncodeOptions, AvifEncoder, AvifDecodeOptions, AvifDecoder> {
  /// Creates an AVIF codec from independently configurable converters.
  const AvifCodec({
    super.rasterEncoder = const AvifEncoder(),
    super.rasterDecoder = const AvifDecoder(),
  }) : super(
         format: NativeImageFormat.avif,
       );
}
