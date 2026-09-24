part of '../tiff.dart';

/// Decodes TIFF through libtiff.
final class NativeTiffDecoder extends NativeRasterDecoder<TiffDecodeOptions> {
  /// Creates a native TIFF decoder with bounded output allocations.
  const NativeTiffDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  }) : super(defaultDecodeOptions: const TiffDecodeOptions());

  @override
  int get codecId => 8;

  @override
  ImageFormat get format => ImageFormat.tiff;

  @override
  bool matches(Uint8List bytes) =>
      super.matches(bytes) ||
      bytes.length >= 8 &&
          ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 43 && bytes[3] == 0 && bytes[4] == 8 && bytes[5] == 0) ||
              (bytes[0] == 0x4d && bytes[1] == 0x4d && bytes[2] == 0 && bytes[3] == 43 && bytes[4] == 0 && bytes[5] == 8)) &&
          bytes[6] == 0 &&
          bytes[7] == 0;
}
