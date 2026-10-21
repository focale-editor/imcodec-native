part of '../heif.dart';

/// Encodes straight RGBA8 as HEIC with HEVC 4:2:0 colour and lossless alpha.
///
/// The bundled Kvazaar encoder does not provide lossless RGB coding. Even at
/// quality 100, colour subsampling can change RGB values.
final class HeifEncoder extends NativeRasterEncoder<HeifEncodeOptions> {
  /// Creates a HEIC encoder with a bounded output allocation.
  const HeifEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const HeifEncodeOptions());

  @override
  NativeRequest createRequest(Image image, HeifEncodeOptions options) => _request(image.bytes, image.width, image.height, options);

  @override
  NativeRequest createSampleRequest(DecodedImage image, HeifEncodeOptions options) => _request(Uint8List(0), image.width, image.height, options).withSamples(image);

  /// Describes one RGBA8 encode of [bytes] with [options].
  NativeRequest _request(Uint8List bytes, int width, int height, HeifEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 2,
    bytes: bytes,
    width: width,
    height: height,
    quality: options.quality,
    maxOutputBytes: maxOutputBytes,
  );
}

/// Options for HEIF/HEIC encoding.
final class HeifEncodeOptions extends RasterEncodeOptions {
  /// Colour quality from zero through one hundred.
  final int quality;

  /// Creates HEIF/HEIC encoding options.
  const HeifEncodeOptions({
    this.quality = 80,
  });
}
