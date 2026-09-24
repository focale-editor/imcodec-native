part of '../jpeg.dart';

/// Encodes JPEG through libjpeg-turbo using Imcodec's options.
final class NativeJpegEncoder extends NativeRasterEncoder<JpegEncodeOptions> {
  /// Creates a native JPEG encoder with a bounded output allocation.
  const NativeJpegEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const JpegEncodeOptions());

  @override
  NativeRequest createRequest(Image image, JpegEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 6,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    quality: options.quality,
    speed: options.chroma == JpegChroma.yuv420 ? 1 : 0,
    maxOutputBytes: maxOutputBytes,
  );

  /// The engine writes no density, so [JpegEncodeOptions.pixelsPerInch] is added here.
  @override
  Uint8List finishEncoding(Uint8List encoded, JpegEncodeOptions options) {
    final double? pixelsPerInch = options.pixelsPerInch;
    return pixelsPerInch == null ? encoded : jpegWithPixelDensity(encoded, pixelsPerInch);
  }
}
