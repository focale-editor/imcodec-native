import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/backend/native_request.dart';

/// Shared bounded decoding for the bundled raster engines.
abstract base class NativeRasterDecoder<Options extends RasterDecodeOptions> extends RasterDecoder<Options> {
  /// Maximum byte length of decoded samples.
  final int maxDecodedBytes;

  /// Maximum retained ICC payload size.
  final int maxIccProfileBytes;

  /// Creates a native decoder with independent pixel, byte, and ICC limits.
  const NativeRasterDecoder({
    this.maxDecodedBytes = defaultMaxDecodedBytes,
    this.maxIccProfileBytes = defaultMaxIccProfileBytes,
  });

  /// Bridge identifier for this codec.
  int get codecId;

  /// Encoded format accepted by this decoder.
  ImageFormat get format;

  /// Whether the input signature is accepted by this native decoder.
  bool matches(Uint8List bytes) => format.matches(bytes);

  @override
  Image decodeImage(Uint8List input, Options options) => backend
      .execute(
        _request(
          input,
          options: options,
        ),
      )
      .toImage();

  /// Decodes native samples without reducing integer or floating precision.
  DecodedImage decodeData(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) {
    final Options options = decodeOptions ?? createDefaultDecodeOptions();
    return backend
        .execute(
          _request(
            input,
            options: options,
            requestedMaxDecodedBytes: maxDecodedBytes,
            requestedMaxIccProfileBytes: maxIccProfileBytes,
            preserveDepth: true,
          ),
        )
        .toImageData();
  }

  /// Reads dimensions, source depth, and bounded colour metadata.
  DecodedImageMetadata inspect(
    Uint8List input, {
    int? maxIccProfileBytes,
    int maxMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) {
    _checkSignature(input);
    return backend
        .execute(
          NativeRequest(
            operation: NativeOperation.inspect,
            format: codecId,
            bytes: input,
            maxIccProfileBytes: _minimum(
              this.maxIccProfileBytes,
              maxIccProfileBytes,
            ),
            maxMetadataBytes: maxMetadataBytes,
          ),
        )
        .toMetadata();
  }

  /// Decodes on a native isolate or browser Worker.
  Future<Image> decodeAsync(
    Uint8List input, {
    Options? decodeOptions,
  }) async {
    final Options options = decodeOptions ?? createDefaultDecodeOptions();
    return (await backend.executeAsync(
      _request(
        Uint8List.fromList(input),
        options: options,
      ),
    )).toImage();
  }

  /// Preserves native samples on a native isolate or browser Worker.
  Future<DecodedImage> decodeDataAsync(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) async {
    final Options options = decodeOptions ?? createDefaultDecodeOptions();
    return (await backend.executeAsync(
      _request(
        Uint8List.fromList(input),
        options: options,
        requestedMaxDecodedBytes: maxDecodedBytes,
        requestedMaxIccProfileBytes: maxIccProfileBytes,
        preserveDepth: true,
      ),
    )).toImageData();
  }

  /// Constructs one validated pointer-free bridge request.
  NativeRequest _request(
    Uint8List bytes, {
    required Options options,
    int? requestedMaxDecodedBytes,
    int? requestedMaxIccProfileBytes,
    bool preserveDepth = false,
  }) {
    _checkSignature(bytes);
    return NativeRequest(
      operation: NativeOperation.decode,
      format: codecId,
      bytes: bytes,
      maxPixels: options.maxPixels,
      maxDecodedBytes: _minimum(
        maxDecodedBytes,
        requestedMaxDecodedBytes,
      ),
      maxIccProfileBytes: _minimum(
        maxIccProfileBytes,
        requestedMaxIccProfileBytes,
      ),
      preserveDepth: preserveDepth,
    );
  }

  /// Rejects another format before entering a bundled decoder.
  void _checkSignature(Uint8List bytes) {
    if (!matches(bytes)) {
      throw ImageCodecException('Expected ${format.name} image data');
    }
  }

  /// Returns the stricter configured and call-site allocation limit.
  int _minimum(int configured, int? requested) => requested == null || configured < requested ? configured : requested;
}
