part of '../webp.dart';

/// Encodes WebP using libwebp while retaining Imcodec's straight-alpha contract.
final class NativeWebPEncoder extends NativeRasterEncoder<WebPEncodeOptions> {
  /// Creates a native WebP encoder with a bounded output allocation.
  const NativeWebPEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const WebPEncodeOptions());

  @override
  NativeRequest createRequest(Image image, WebPEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 4,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
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
