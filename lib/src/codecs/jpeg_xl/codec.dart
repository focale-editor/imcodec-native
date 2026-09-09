part of '../jpeg_xl.dart';

/// Encodes and decodes JPEG XL through libjxl.
final class NativeJpegXlCodec extends RasterCodec<JpegXlEncodeOptions, NativeJpegXlEncoder, JpegXlDecodeOptions, NativeJpegXlDecoder>
    with ParallelRasterCodec<JpegXlEncodeOptions, NativeJpegXlEncoder, JpegXlDecodeOptions, NativeJpegXlDecoder> {
  /// Creates a complete native JPEG XL codec.
  const NativeJpegXlCodec({
    super.rasterEncoder = const NativeJpegXlEncoder(),
    super.rasterDecoder = const NativeJpegXlDecoder(),
  }) : super(
         format: ImageFormat.jpegXl,
       );
}
