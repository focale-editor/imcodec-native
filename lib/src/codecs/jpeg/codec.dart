part of '../jpeg.dart';

/// Encodes and decodes JPEG through libjpeg-turbo.
final class NativeJpegCodec extends RasterCodec<JpegEncodeOptions, NativeJpegEncoder, JpegDecodeOptions, NativeJpegDecoder>
    with ParallelRasterCodec<JpegEncodeOptions, NativeJpegEncoder, JpegDecodeOptions, NativeJpegDecoder> {
  /// Creates a complete native JPEG codec.
  const NativeJpegCodec({
    super.rasterEncoder = const NativeJpegEncoder(),
    super.rasterDecoder = const NativeJpegDecoder(),
  }) : super(
         format: ImageFormat.jpeg,
       );
}
