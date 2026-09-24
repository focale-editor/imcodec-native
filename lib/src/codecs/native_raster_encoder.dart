import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/backend/native_request.dart';

/// Shared synchronous and runner-based native encoder contract.
abstract base class NativeRasterEncoder<Options extends RasterEncodeOptions> extends RasterEncoder<Options> with ParallelRasterEncoder<Options> {
  /// Maximum size of one encoded output buffer.
  final int maxOutputBytes;

  /// Creates an immutable native encoder resource configuration.
  const NativeRasterEncoder({
    required super.defaultEncodeOptions,
    this.maxOutputBytes = defaultMaxEncodedBytes,
  });

  /// Describes one encoding operation without retaining native pointers.
  NativeRequest createRequest(Image image, Options options);

  /// Adds what the engine cannot write to its [encoded] output.
  ///
  /// Returns [encoded] by default. Runs on the calling isolate after the engine,
  /// so the bridge stays unchanged when an option has no native counterpart.
  Uint8List finishEncoding(Uint8List encoded, Options options) => encoded;

  @override
  Uint8List encodeWithOptions(Image input, Options options) => finishEncoding(
    _encodeRequest(createRequest(input, options)),
    options,
  );

  @override
  Future<Uint8List> encodeImageWith(
    ParallelRunner runner,
    Image input,
    Options options,
  ) async {
    final List<Uint8List> results = await runner<NativeRequest, Uint8List>(
      [createRequest(input, options)],
      _encodeRequest,
    );
    return finishEncoding(results.single, options);
  }
}

/// Runs one transferable encoder request, including inside worker isolates.
Uint8List _encodeRequest(NativeRequest request) => backend.execute(request).bytes;
