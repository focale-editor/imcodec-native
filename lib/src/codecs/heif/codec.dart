part of '../heif.dart';

/// Encodes HEIC and decodes primary images from HEIF/HEIC containers.
final class HeifCodec extends RasterCodec<HeifEncodeOptions, HeifEncoder, HeifDecodeOptions, HeifDecoder> with ParallelRasterCodec<HeifEncodeOptions, HeifEncoder, HeifDecodeOptions, HeifDecoder> {
  /// Creates a HEIF codec from independently configurable converters.
  const HeifCodec({
    super.rasterEncoder = const HeifEncoder(),
    super.rasterDecoder = const HeifDecoder(),
  }) : super(
         format: NativeImageFormat.heif,
       );
}
