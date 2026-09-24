part of '../open_exr.dart';

/// Decodes OpenEXR through OpenEXR.
final class NativeOpenExrDecoder extends NativeRasterDecoder<OpenExrDecodeOptions> {
  /// Creates a native OpenEXR decoder with bounded output allocations.
  const NativeOpenExrDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  }) : super(defaultDecodeOptions: const OpenExrDecodeOptions());

  @override
  int get codecId => 9;

  @override
  ImageFormat get format => ImageFormat.openExr;
}
