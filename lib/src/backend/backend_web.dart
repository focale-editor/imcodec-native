import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/native_request.dart';
import 'package:imcodec_native/src/backend/native_result.dart';
import 'package:web/web.dart' as web;

/// Default URL used by Flutter's package asset bundler.
String _assetBaseUrl = 'assets/packages/imcodec_native/assets/web/';

/// Shared initialization attempt, cleared after failures so callers can retry.
Future<void>? _initialization;

/// Loaded synchronous codec module for ordinary `dart:convert` interfaces.
_CodecModule? _module;

/// Lazily created Worker that owns one reusable WebAssembly instance.
_WorkerRuntime? _workerRuntime;

/// Creates the Emscripten module using the external package loader script.
@JS('imcodecNativeCreateModule')
external JSPromise<JSObject> _createModule();

/// Constructs module Workers outside dart2js/dart2wasm option-dictionary code.
@JS('imcodecNativeCreateWorker')
external web.Worker _createWorker(JSString url);

/// Formats an ErrorEvent without relying on dart2wasm extension-type casts.
@JS('imcodecNativeWorkerError')
external JSString _workerError(web.Event event);

/// Loads the package's WebAssembly module before synchronous codecs are used.
Future<void> initializeBackend({String? assetBaseUrl}) {
  if (assetBaseUrl != null) {
    final String trimmed = assetBaseUrl.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(assetBaseUrl, 'assetBaseUrl', 'An asset URL is required');
    }
    final String normalized = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    if (_initialization != null && normalized != _assetBaseUrl) {
      throw StateError('The Web asset URL cannot change after initialization starts');
    }
    _assetBaseUrl = normalized;
  }
  return _initialization ??= _loadModule();
}

/// Injects the external loader and reports loading, CSP, or Wasm errors.
Future<void> _loadModule() async {
  final web.HTMLScriptElement script = web.HTMLScriptElement()
    ..type = 'module'
    ..src = '${_assetBaseUrl}imcodec_native_loader.js';
  final Completer<void> loaded = Completer<void>();
  script.onload = ((web.Event event) {
    if (!loaded.isCompleted) {
      loaded.complete();
    }
  }).toJS;
  script.onerror = ((web.Event event) {
    if (!loaded.isCompleted) {
      loaded.completeError(ImageCodecException('Could not load the ImcodecNative Web assets from $_assetBaseUrl'));
    }
  }).toJS;
  try {
    web.document.head!.appendChild(script);
    await loaded.future.timeout(const Duration(seconds: 30));
    _module = _CodecModule._(await _createModule().toDart.timeout(const Duration(seconds: 60)));
  } on Object catch (error) {
    _initialization = null;
    throw ImageCodecException('Could not initialize ImcodecNative WebAssembly', cause: error);
  } finally {
    script.remove();
  }
}

/// Requires explicit asynchronous browser initialization before synchronous use.
_CodecModule get _readyModule => _module ?? (throw StateError('Await ImcodecNative.initialize() before using synchronous Web codecs'));

/// Reports the engine versions read from the loaded WebAssembly module.
String get backendVersion {
  final _CodecModule module = _readyModule;
  return module.readString(module.version());
}

/// Executes expensive work in a module Worker without blocking the browser UI.
Future<NativeResult> executeAsync(NativeRequest request) {
  request.validate();
  if (_module == null) {
    return Future<NativeResult>.error(
      StateError(
        'Await ImcodecNative.initialize() before using Web codecs',
      ),
    );
  }
  return (_workerRuntime ??= _WorkerRuntime()).execute(request);
}

/// Correlates requests sent to one long-lived module Worker.
final class _WorkerRuntime {
  /// Operations awaiting a response, keyed by their transferable identifier.
  final Map<int, Completer<NativeResult>> _pending = {};

  /// Browser Worker that owns the reusable codec module.
  late final web.Worker _worker;

  /// Monotonic identifier used to correlate out-of-order responses.
  int _nextRequestId = 1;

  /// Whether a transport failure permanently closed this runtime.
  bool _failed = false;

  /// Starts the external module Worker and installs transport handlers.
  _WorkerRuntime() {
    _worker = _createWorker(
      '${_assetBaseUrl}imcodec_native_worker.js'.toJS,
    );
    _worker.onmessage = _handleMessage.toJS;
    _worker.onerror = ((web.Event event) {
      final String detail = _workerError(event).toDart;
      _fail(
        ImageCodecException(
          'The ImcodecNative Web Worker could not load or execute: $detail',
        ),
      );
    }).toJS;
    _worker.onmessageerror = ((web.Event event) {
      _fail(
        const ImageCodecException(
          'The ImcodecNative Web Worker returned an invalid message',
        ),
      );
    }).toJS;
  }

  /// Transfers one validated request and awaits its corresponding response.
  Future<NativeResult> execute(NativeRequest request) {
    if (_failed) {
      return Future<NativeResult>.error(
        const ImageCodecException('The ImcodecNative Web Worker is unavailable'),
      );
    }
    final int id = _nextRequestId++;
    final Completer<NativeResult> completed = Completer<NativeResult>();
    _pending[id] = completed;
    try {
      final JSArrayBuffer buffer = Uint8List.fromList(request.bytes).buffer.toJS;
      _worker.postMessage(
        _WorkerRequest(
          id: id,
          operation: request.operation.index,
          format: request.format,
          bytes: buffer,
          width: request.width,
          height: request.height,
          quality: request.quality,
          lossless: request.lossless,
          speed: request.speed,
          maxPixels: request.maxPixels,
          maxDecodedBytes: request.maxDecodedBytes,
          preserveDepth: request.preserveDepth,
          maxIccProfileBytes: request.maxIccProfileBytes,
          maxMetadataBytes: request.maxMetadataBytes,
          maxOutputBytes: request.maxOutputBytes,
        ),
        [buffer].toJS,
      );
    } on Object catch (error, stack) {
      _pending.remove(id);
      completed.completeError(error, stack);
    }
    return completed.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _pending.remove(id);
        _fail(
          const ImageCodecException(
            'The ImcodecNative Web Worker did not respond',
          ),
        );
        throw const ImageCodecException(
          'The ImcodecNative Web Worker did not respond',
        );
      },
    );
  }

  /// Converts one Worker message into an owned Dart result or codec error.
  void _handleMessage(web.MessageEvent event) {
    try {
      final _WorkerResponse response = _WorkerResponse._(event.data as JSObject);
      final Completer<NativeResult>? completed = _pending.remove(response.id);
      if (completed == null || completed.isCompleted) {
        return;
      }
      final String? error = response.error;
      if (error != null) {
        completed.completeError(ImageCodecException(error));
        return;
      }
      completed.complete(
        NativeResult(
          width: response.width,
          height: response.height,
          depth: response.depth,
          sourceDepth: response.sourceDepth,
          colorModel: response.colorModel,
          bytes: response.bytes?.toDart.asUint8List() ?? Uint8List(0),
          iccProfile: response.iccProfile?.toDart.asUint8List(),
          exifMetadata: response.exifMetadata?.toDart.asUint8List(),
          xmpMetadata: response.xmpMetadata?.toDart.asUint8List(),
        ),
      );
    } on Object catch (error, stack) {
      _fail(error, stack);
    }
  }

  /// Terminates a broken Worker and fails every outstanding operation.
  void _fail(Object error, [StackTrace? stack]) {
    if (_failed) {
      return;
    }
    _failed = true;
    _worker.terminate();
    if (identical(_workerRuntime, this)) {
      _workerRuntime = null;
    }
    final List<Completer<NativeResult>> pending = _pending.values.toList();
    _pending.clear();
    for (final Completer<NativeResult> completed in pending) {
      if (!completed.isCompleted) {
        completed.completeError(error, stack ?? StackTrace.current);
      }
    }
  }
}

/// Copies all output before releasing WebAssembly allocations.
NativeResult execute(NativeRequest request) {
  request.validate();
  final _CodecModule module = _readyModule;
  final int input = module.allocate(request.bytes.isEmpty ? 1 : request.bytes.length);
  if (input == 0) {
    throw const ImageCodecException('Could not allocate WebAssembly input memory');
  }
  int result = 0;
  try {
    module.heap.toDart.setRange(input, input + request.bytes.length, request.bytes);
    result = switch (request.operation) {
      NativeOperation.decode => module.decode(input, request.bytes.length, request.format, request.maxPixels, request.maxDecodedBytes, request.preserveDepth ? 1 : 0, request.maxIccProfileBytes),
      NativeOperation.inspect => module.inspect(input, request.bytes.length, request.format, request.maxIccProfileBytes, request.maxMetadataBytes),
      NativeOperation.encode => module.encode(
        input,
        request.bytes.length,
        request.width,
        request.height,
        request.format,
        request.quality,
        request.lossless ? 1 : 0,
        request.speed,
        request.maxOutputBytes,
      ),
    };
    final String error = module.readString(module.error(result));
    if (error.isNotEmpty) {
      throw ImageCodecException(error);
    }
    return NativeResult(
      width: module.number(result, 0),
      height: module.number(result, 1),
      depth: module.number(result, 2),
      sourceDepth: module.number(result, 3),
      colorModel: module.number(result, 8),
      bytes: _copyBuffer(module, result, 0) ?? Uint8List(0),
      iccProfile: _copyBuffer(module, result, 1),
      exifMetadata: _copyBuffer(module, result, 2),
      xmpMetadata: _copyBuffer(module, result, 3),
    );
  } finally {
    module.releaseResult(result);
    module.release(input);
  }
}

/// Copies a bounded byte vector from the current, possibly grown Wasm heap.
Uint8List? _copyBuffer(_CodecModule module, int result, int field) {
  final int length = module.number(result, field + 4);
  if (length == 0) {
    return null;
  }
  final int pointer = module.data(result, field);
  return Uint8List.fromList(module.heap.toDart.sublist(pointer, pointer + length));
}

/// Typed view over Emscripten's exported C functions and memory.
extension type _CodecModule._(JSObject _) implements JSObject {
  /// Current linear memory, refreshed after operations that may grow it.
  @JS('HEAPU8')
  external JSUint8Array get heap;

  /// Allocates bridge input memory.
  @JS('_malloc')
  external int allocate(int size);

  /// Releases bridge input memory.
  @JS('_free')
  external void release(int pointer);

  /// Decodes one image.
  @JS('_imcodec_decode')
  external int decode(int bytes, int size, int format, int maxPixels, int maxBytes, int preserveDepth, int maxIccBytes);

  /// Inspects one image.
  @JS('_imcodec_inspect')
  external int inspect(int bytes, int size, int format, int maxIccBytes, int maxMetadataBytes);

  /// Encodes straight RGBA8.
  @JS('_imcodec_encode')
  external int encode(int bytes, int size, int width, int height, int format, int quality, int lossless, int speed, int maxBytes);

  /// Releases all allocations owned by one result.
  @JS('_imcodec_result_free')
  external void releaseResult(int result);

  /// Reads a result dimension, depth, or buffer size.
  @JS('_imcodec_result_number')
  external int number(int result, int field);

  /// Borrows one output buffer.
  @JS('_imcodec_result_data')
  external int data(int result, int field);

  /// Borrows the error message.
  @JS('_imcodec_result_error')
  external int error(int result);

  /// Borrows the engine version string.
  @JS('_imcodec_version')
  external int version();

  /// Copies a null-terminated native UTF-8 string.
  @JS('UTF8ToString')
  external String readString(int pointer);
}

/// Structured clone message accepted by the browser Worker.
extension type _WorkerRequest._(JSObject _) implements JSObject {
  /// Creates a transferable codec request.
  external _WorkerRequest({
    required int id,
    required int operation,
    required int format,
    required JSArrayBuffer bytes,
    required int width,
    required int height,
    required int quality,
    required bool lossless,
    required int speed,
    required int maxPixels,
    required int maxDecodedBytes,
    required bool preserveDepth,
    required int maxIccProfileBytes,
    required int maxMetadataBytes,
    required int maxOutputBytes,
  });
}

/// Ownership-transferred buffers returned by the browser Worker.
extension type _WorkerResponse._(JSObject _) implements JSObject {
  /// Correlates this response with its request.
  external int get id;

  /// Error text, present only on failure.
  external String? get error;

  /// Decoded width.
  external int get width;

  /// Decoded height.
  external int get height;

  /// Storage sample depth.
  external int get depth;

  /// Original sample depth.
  external int get sourceDepth;

  /// Native process colour model.
  external int get colorModel;

  /// Encoded bytes or decoded pixels.
  external JSArrayBuffer? get bytes;

  /// Embedded ICC profile.
  external JSArrayBuffer? get iccProfile;

  /// Original EXIF block.
  external JSArrayBuffer? get exifMetadata;

  /// Original XMP packet.
  external JSArrayBuffer? get xmpMetadata;
}
