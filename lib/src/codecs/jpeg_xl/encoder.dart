part of '../jpeg_xl.dart';

/// Encodes lossless JPEG XL using libjxl, including RGB hidden by zero alpha.
final class NativeJpegXlEncoder extends NativeRasterEncoder<JpegXlEncodeOptions> {
  /// Creates a native JPEG XL encoder with a bounded output allocation.
  const NativeJpegXlEncoder({super.maxOutputBytes});

  @override
  NativeRequest createRequest(Image image, JpegXlEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 3,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    lossless: true,
    speed: switch (options.effort) {
      JpegXlEffort.fast => 1,
      JpegXlEffort.balanced => 5,
      JpegXlEffort.maximum => 9,
    },
    maxOutputBytes: maxOutputBytes,
  );

  @override
  JpegXlEncodeOptions createDefaultEncodeOptions() => const JpegXlEncodeOptions();
}
