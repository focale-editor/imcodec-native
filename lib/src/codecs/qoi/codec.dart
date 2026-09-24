part of '../qoi.dart';

/// Encodes and decodes QOI through the reference QOI library.
final class NativeQoiCodec extends RasterCodec<QoiEncodeOptions, NativeQoiEncoder, QoiDecodeOptions, NativeQoiDecoder>
    with ParallelRasterCodec<QoiEncodeOptions, NativeQoiEncoder, QoiDecodeOptions, NativeQoiDecoder> {
  /// Creates a complete native QOI codec.
  const NativeQoiCodec({
    super.rasterEncoder = const NativeQoiEncoder(),
    super.rasterDecoder = const NativeQoiDecoder(),
  }) : super(
         format: ImageFormat.qoi,
       );
}
