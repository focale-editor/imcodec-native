part of '../tiff.dart';

/// Encodes and decodes TIFF through libtiff.
final class NativeTiffCodec extends RasterCodec<TiffEncodeOptions, NativeTiffEncoder, TiffDecodeOptions, NativeTiffDecoder>
    with ParallelRasterCodec<TiffEncodeOptions, NativeTiffEncoder, TiffDecodeOptions, NativeTiffDecoder> {
  /// Creates a complete native TIFF codec.
  const NativeTiffCodec({
    super.rasterEncoder = const NativeTiffEncoder(),
    super.rasterDecoder = const NativeTiffDecoder(),
  }) : super(
         format: ImageFormat.tiff,
       );
}
