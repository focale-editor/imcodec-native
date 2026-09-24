part of '../open_exr.dart';

/// Encodes OpenEXR through OpenEXR using Imcodec's options.
final class NativeOpenExrEncoder extends NativeRasterEncoder<OpenExrEncodeOptions> {
  /// Creates a native OpenEXR encoder with a bounded output allocation.
  const NativeOpenExrEncoder({super.maxOutputBytes});

  @override
  NativeRequest createRequest(Image image, OpenExrEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 9,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    speed: options.compression.value,
    maxOutputBytes: maxOutputBytes,
  );

  @override
  OpenExrEncodeOptions createDefaultEncodeOptions() => const OpenExrEncodeOptions();
}
