part of '../avif.dart';

/// Encodes straight RGBA8 as lossy or mathematically lossless AVIF.
final class AvifEncoder extends NativeRasterEncoder<AvifEncodeOptions> {
  /// Creates an AVIF encoder with a bounded output allocation.
  const AvifEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const AvifEncodeOptions());

  @override
  NativeRequest createRequest(Image image, AvifEncodeOptions options) => _request(image.bytes, image.width, image.height, options);

  @override
  NativeRequest createSampleRequest(DecodedImage image, AvifEncodeOptions options) => _request(Uint8List(0), image.width, image.height, options).withSamples(image);

  /// Describes one RGBA8 encode of [bytes] with [options].
  NativeRequest _request(Uint8List bytes, int width, int height, AvifEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 1,
    bytes: bytes,
    width: width,
    height: height,
    quality: options.quality,
    lossless: options.lossless,
    speed: options.speed,
    maxOutputBytes: maxOutputBytes,
  );
}

/// Options for AVIF encoding.
final class AvifEncodeOptions extends RasterEncodeOptions {
  /// Colour quality from zero through one hundred; alpha is always lossless.
  final int quality;

  /// Uses lossless RGB coding with identity colour conversion and 4:4:4 chroma.
  final bool lossless;

  /// AV1 speed from zero (slowest) through nine (fastest).
  final int speed;

  /// Creates AVIF encoding options.
  const AvifEncodeOptions({
    this.quality = 80,
    this.lossless = false,
    this.speed = 6,
  });
}
