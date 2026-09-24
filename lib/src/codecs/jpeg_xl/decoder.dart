part of '../jpeg_xl.dart';

/// Decodes JPEG XL through libjxl to straight-alpha RGBA samples.
final class NativeJpegXlDecoder extends NativeRasterDecoder<JpegXlDecodeOptions> {
  /// Creates a native JPEG XL decoder with bounded output allocations.
  const NativeJpegXlDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  }) : super(defaultDecodeOptions: const JpegXlDecodeOptions());

  @override
  int get codecId => 3;

  @override
  ImageFormat get format => ImageFormat.jpegXl;
}
