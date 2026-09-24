part of '../open_exr.dart';

/// Encodes and decodes OpenEXR through OpenEXR.
final class NativeOpenExrCodec extends RasterCodec<OpenExrEncodeOptions, NativeOpenExrEncoder, OpenExrDecodeOptions, NativeOpenExrDecoder>
    with ParallelRasterCodec<OpenExrEncodeOptions, NativeOpenExrEncoder, OpenExrDecodeOptions, NativeOpenExrDecoder> {
  /// Creates a complete native OpenEXR codec.
  const NativeOpenExrCodec({
    super.rasterEncoder = const NativeOpenExrEncoder(),
    super.rasterDecoder = const NativeOpenExrDecoder(),
  }) : super(
         format: ImageFormat.openExr,
       );
}
