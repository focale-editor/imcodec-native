import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/backend/native_request.dart';
import 'package:imcodec_native/src/codecs/raster_metadata.dart';

/// Shared bounded decoding for the bundled raster engines.
abstract base class NativeRasterDecoder<Options extends RasterDecodeOptions> extends RasterDecoder<Options> {
  /// Maximum byte length of decoded samples.
  final int maxDecodedBytes;

  /// Maximum retained ICC payload size.
  final int maxIccProfileBytes;

  /// Creates a native decoder with independent pixel, byte, and ICC limits.
  const NativeRasterDecoder({
    required super.defaultDecodeOptions,
    this.maxDecodedBytes = defaultMaxDecodedBytes,
    this.maxIccProfileBytes = defaultMaxIccProfileBytes,
  });

  /// Bridge identifier for this codec.
  int get codecId;

  /// Encoded format accepted by this decoder.
  ImageFormat get format;

  /// Whether the input signature is accepted by this native decoder.
  bool matches(Uint8List bytes) => format.matches(bytes);

  /// Display orientation the engine leaves for Dart to apply, from one to
  /// eight.
  ///
  /// One by default, for engines that orient their own output or formats with
  /// no orientation. Decoded pixels are rearranged to match Imcodec's Dart
  /// decoders.
  int orientationOf(Uint8List input) => 1;

  @override
  Image decodeWithOptions(Uint8List input, Options options) => _orientImage(
    input,
    backend
        .execute(
          _request(
            input,
            options: options,
          ),
        )
        .toImage(),
  );

  /// Decodes native samples without reducing integer or floating precision.
  DecodedImage decodeData(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) {
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return _orientData(
      input,
      backend
          .execute(
            _request(
              input,
              options: options,
              requestedMaxDecodedBytes: maxDecodedBytes,
              requestedMaxIccProfileBytes: maxIccProfileBytes,
              preserveDepth: true,
            ),
          )
          .toImageData(),
    );
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
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return _orientImage(
      input,
      (await backend.executeAsync(
        _request(
          Uint8List.fromList(input),
          options: options,
        ),
      )).toImage(),
    );
  }

  /// Preserves native samples on a native isolate or browser Worker.
  Future<DecodedImage> decodeDataAsync(
    Uint8List input, {
    Options? decodeOptions,
    int? maxDecodedBytes,
    int? maxIccProfileBytes,
  }) async {
    final Options options = decodeOptions ?? defaultDecodeOptions;
    return _orientData(
      input,
      (await backend.executeAsync(
        _request(
          Uint8List.fromList(input),
          options: options,
          requestedMaxDecodedBytes: maxDecodedBytes,
          requestedMaxIccProfileBytes: maxIccProfileBytes,
          preserveDepth: true,
        ),
      )).toImageData(),
    );
  }

  /// Applies [orientationOf] to RGBA8 output.
  Image _orientImage(Uint8List input, Image image) {
    final int orientation = orientationOf(input);
    if (orientation == 1) {
      return image;
    }
    final ({Uint8List bytes, int width, int height}) oriented = orientPixels(image.bytes, image.width, image.height, orientation);
    return Image.fromRgba(width: oriented.width, height: oriented.height, bytes: oriented.bytes, copy: false);
  }

  /// Applies [orientationOf] to samples of any depth and colour model.
  DecodedImage _orientData(Uint8List input, DecodedImage image) {
    final int orientation = orientationOf(input);
    if (orientation == 1) {
      return image;
    }
    final ({Uint8List bytes, int width, int height}) oriented = orientPixels(image.bytes, image.width, image.height, orientation);
    return DecodedImage(
      width: oriented.width,
      height: oriented.height,
      colorModel: image.colorModel,
      sampleFormat: image.sampleFormat,
      bytes: oriented.bytes,
      iccProfile: image.iccProfile,
      copy: false,
    );
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
