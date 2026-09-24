part of '../tiff.dart';

/// Encodes TIFF through libtiff using Imcodec's options.
final class NativeTiffEncoder extends NativeRasterEncoder<TiffEncodeOptions> {
  /// Creates a native TIFF encoder with a bounded output allocation.
  const NativeTiffEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const TiffEncodeOptions());

  @override
  NativeRequest createRequest(Image image, TiffEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 8,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    speed: options.compression == TiffCompression.packBits ? 1 : 0,
    maxOutputBytes: maxOutputBytes,
  );
}
