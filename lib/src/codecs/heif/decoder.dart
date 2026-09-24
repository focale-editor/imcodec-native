part of '../heif.dart';

/// Shared allocation options for HEIF-family decoders.
abstract class HeifRasterDecodeOptions extends RasterDecodeOptions {
  /// Maximum byte length of decoded samples.
  final int maxDecodedBytes;

  /// Maximum retained ICC payload size.
  final int maxIccProfileBytes;

  /// Creates bounded HEIF-family decoding options.
  const HeifRasterDecodeOptions({
    super.maxPixels,
    this.maxDecodedBytes = defaultMaxDecodedBytes,
    this.maxIccProfileBytes = defaultMaxIccProfileBytes,
  });
}

/// Shared primary-image decoding for HEIF and AVIF containers.
abstract base class HeifRasterDecoder<Options extends HeifRasterDecodeOptions> extends RasterDecoder<Options> {
  /// Creates a HEIF-family decoder.
  const HeifRasterDecoder({required super.defaultDecodeOptions});

  /// Container format accepted by this decoder.
  NativeImageFormat get format;

  @override
  Image decodeWithOptions(Uint8List input, Options options) => backend
      .execute(
        _request(
          input,
          options: options,
        ),
      )
      .toImage();

  /// Decodes normalized uint16 RGBA for high-bit-depth input, otherwise RGBA8.
  ///
  /// Ten- and twelve-bit values expand to the full uint16 range. Samples remain
  /// in their source colour space; no display tone mapping is performed.
  DecodedImage decodeData(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) {
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return backend
        .execute(
          _request(
            input,
            options: options,
            maxDecodedBytes: maxDecodedBytes,
            maxIccProfileBytes: maxIccProfileBytes,
            preserveDepth: true,
          ),
        )
        .toImageData();
  }

  /// Reads dimensions, depth and bounded ICC, EXIF and XMP payloads.
  DecodedImageMetadata inspect(
    Uint8List input, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => format.inspect(
    input,
    maxIccProfileBytes,
    maxMetadataBytes,
  );

  /// Decodes on a native isolate or browser Worker.
  Future<Image> decodeAsync(
    Uint8List input, {
    Options? decodeOptions,
  }) async {
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return (await backend.executeAsync(
      _request(
        Uint8List.fromList(input),
        options: options,
      ),
    )).toImage();
  }

  /// Preserves high-precision samples on a native isolate or browser Worker.
  Future<DecodedImage> decodeDataAsync(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) async {
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return (await backend.executeAsync(
      _request(
        Uint8List.fromList(input),
        options: options,
        maxDecodedBytes: maxDecodedBytes,
        maxIccProfileBytes: maxIccProfileBytes,
        preserveDepth: true,
      ),
    )).toImageData();
  }

  /// Validates the format and constructs one bounded decoding operation.
  NativeRequest _request(
    Uint8List bytes, {
    required Options options,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
    bool preserveDepth = false,
  }) {
    _checkSignature(bytes);
    return NativeRequest(
      operation: NativeOperation.decode,
      format: format.codecId,
      bytes: bytes,
      maxPixels: options.maxPixels,
      maxDecodedBytes: _minimum(
        options.maxDecodedBytes,
        maxDecodedBytes,
      ),
      maxIccProfileBytes: _minimum(
        options.maxIccProfileBytes,
        maxIccProfileBytes,
      ),
      preserveDepth: preserveDepth,
    );
  }

  /// Rejects another format without initializing an engine or allocating pixels.
  void _checkSignature(Uint8List bytes) {
    if (!identical(NativeImageFormat.sniff(bytes), format)) {
      throw ImageCodecException('Expected ${format.name} image data');
    }
  }

  /// Returns the stricter of [configured] and an optional call-site limit.
  int _minimum(int configured, int? requested) => requested == null || configured < requested ? configured : requested;
}

/// Decodes primary HEIF/HEIC images, including grids, alpha and orientation.
final class HeifDecoder extends HeifRasterDecoder<HeifDecodeOptions> {
  /// Creates a bounded HEIF decoder.
  const HeifDecoder() : super(defaultDecodeOptions: const HeifDecodeOptions());

  @override
  NativeImageFormat get format => NativeImageFormat.heif;
}

/// Options for HEIF/HEIC decoding.
final class HeifDecodeOptions extends HeifRasterDecodeOptions {
  /// Creates bounded HEIF/HEIC decoding options.
  const HeifDecodeOptions({
    super.maxPixels,
    super.maxDecodedBytes,
    super.maxIccProfileBytes,
  });
}
