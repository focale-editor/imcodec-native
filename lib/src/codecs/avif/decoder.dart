part of '../avif.dart';

/// Decodes the primary AVIF image, including alpha and container orientation.
final class AvifDecoder extends HeifRasterDecoder<AvifDecodeOptions> {
  /// Creates a bounded AVIF decoder.
  const AvifDecoder();

  @override
  NativeImageFormat get format => NativeImageFormat.avif;

  @override
  AvifDecodeOptions createDecodeOptions({
    int maxPixels = RasterDecodeOptions.defaultMaxPixels,
  }) => AvifDecodeOptions(maxPixels: maxPixels);
}

/// Options for AVIF decoding.
final class AvifDecodeOptions extends HeifRasterDecodeOptions {
  /// Creates bounded AVIF decoding options.
  const AvifDecodeOptions({
    super.maxPixels,
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });
}
