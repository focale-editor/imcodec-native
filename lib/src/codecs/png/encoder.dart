part of '../png.dart';

/// Encodes PNG through libpng using Imcodec's options.
final class NativePngEncoder extends NativeRasterEncoder<PngEncodeOptions> {
  /// Creates a native PNG encoder with a bounded output allocation.
  const NativePngEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const PngEncodeOptions());

  @override
  NativeRequest createRequest(Image image, PngEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 5,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    speed: options.level,
    maxOutputBytes: maxOutputBytes,
  );
}
