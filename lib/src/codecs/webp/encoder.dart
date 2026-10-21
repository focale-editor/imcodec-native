part of '../webp.dart';

/// Encodes WebP using libwebp while retaining Imcodec's straight-alpha contract.
final class NativeWebPEncoder extends NativeRasterEncoder<WebPEncodeOptions> {
  /// Creates a native WebP encoder with a bounded output allocation.
  const NativeWebPEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const WebPEncodeOptions());

  @override
  NativeRequest createRequest(Image image, WebPEncodeOptions options) => _request(image.bytes, image.width, image.height, options);

  @override
  NativeRequest createSampleRequest(DecodedImage image, WebPEncodeOptions options) => _request(Uint8List(0), image.width, image.height, options).withSamples(image);

  /// Describes one RGBA8 encode of [bytes] with [options].
  NativeRequest _request(Uint8List bytes, int width, int height, WebPEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 4,
    bytes: bytes,
    width: width,
    height: height,
    quality: options.quality ?? 100,
    lossless: options.quality == null,
    speed: switch (options.effort) {
      WebPEffort.fast => 0,
      WebPEffort.balanced => 4,
      WebPEffort.maximum => 6,
    },
    maxOutputBytes: maxOutputBytes,
  );
}
