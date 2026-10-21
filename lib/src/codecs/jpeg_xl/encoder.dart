part of '../jpeg_xl.dart';

/// Encodes lossless JPEG XL using libjxl, including RGB hidden by zero alpha.
final class NativeJpegXlEncoder extends NativeRasterEncoder<JpegXlEncodeOptions> {
  /// Creates a native JPEG XL encoder with a bounded output allocation.
  const NativeJpegXlEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const JpegXlEncodeOptions());

  @override
  NativeRequest createRequest(Image image, JpegXlEncodeOptions options) => _request(image.bytes, image.width, image.height, options);

  @override
  NativeRequest createSampleRequest(DecodedImage image, JpegXlEncodeOptions options) => _request(Uint8List(0), image.width, image.height, options).withSamples(image);

  /// Describes one RGBA8 encode of [bytes] with [options].
  NativeRequest _request(Uint8List bytes, int width, int height, JpegXlEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 3,
    bytes: bytes,
    width: width,
    height: height,
    lossless: true,
    speed: switch (options.effort) {
      JpegXlEffort.fast => 1,
      JpegXlEffort.balanced => 5,
      JpegXlEffort.maximum => 9,
    },
    maxOutputBytes: maxOutputBytes,
  );
}
