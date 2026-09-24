part of '../qoi.dart';

/// Decodes QOI through the reference QOI library.
final class NativeQoiDecoder extends NativeRasterDecoder<QoiDecodeOptions> {
  /// Creates a native QOI decoder with bounded output allocations.
  const NativeQoiDecoder({
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });

  @override
  int get codecId => 7;

  @override
  ImageFormat get format => ImageFormat.qoi;

  @override
  QoiDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => QoiDecodeOptions(maxPixels: maxPixels);
}
