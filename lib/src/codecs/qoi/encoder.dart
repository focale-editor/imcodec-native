part of '../qoi.dart';

/// Encodes QOI through the reference QOI library using Imcodec's options.
final class NativeQoiEncoder extends NativeRasterEncoder<QoiEncodeOptions> {
  /// Creates a native QOI encoder with a bounded output allocation.
  const NativeQoiEncoder({super.maxOutputBytes}) : super(defaultEncodeOptions: const QoiEncodeOptions());

  @override
  NativeRequest createRequest(Image image, QoiEncodeOptions options) => NativeRequest(
    operation: NativeOperation.encode,
    format: 7,
    bytes: image.bytes,
    width: image.width,
    height: image.height,
    speed: 0,
    maxOutputBytes: maxOutputBytes,
  );
}
