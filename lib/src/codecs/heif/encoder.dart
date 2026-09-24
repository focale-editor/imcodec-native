part of '../heif.dart';

/// Encodes straight RGBA8 as HEIC with HEVC 4:2:0 colour and lossless alpha.
///
/// The bundled Kvazaar encoder does not provide lossless RGB coding. Even at
/// quality 100, colour subsampling can change RGB values.
final class HeifEncoder extends NativeRasterEncoder<HeifEncodeOptions> {
  /// Creates a HEIC encoder with a bounded output allocation.
  const HeifEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const HeifEncodeOptions());

  @override
  NativeRequest createRequest(Image image, HeifEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 2,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
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
