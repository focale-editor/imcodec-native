import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/native_request.dart';
import 'package:imcodec_native/src/backend/native_result.dart';
import 'package:imcodec_native/src/native/bindings.dart';

/// Loads the bundled code asset; browser URL configuration is irrelevant here.
Future<void> initializeBackend({String? assetBaseUrl}) async {
  nativeVersion();
}

/// Reports the actually loaded native engines.
String get backendVersion => nativeVersion().toDartString();

/// Executes a pointer-free request on a worker isolate.
Future<NativeResult> executeAsync(NativeRequest request) => Isolate.run(() => execute(request));

/// Executes a request and copies all results before freeing native resources.
NativeResult execute(NativeRequest request) {
  request.validate();
  final Pointer<Uint8> input = calloc<Uint8>(request.bytes.isEmpty ? 1 : request.bytes.length);
  Pointer<NativeCodecResult> result = nullptr;
  try {
    input.asTypedList(request.bytes.length).setAll(0, request.bytes);
    result = switch (request.operation) {
      NativeOperation.decode => nativeDecode(input, request.bytes.length, request.format, request.maxPixels, request.maxDecodedBytes, request.preserveDepth ? 1 : 0, request.maxIccProfileBytes),
      NativeOperation.inspect => nativeInspect(input, request.bytes.length, request.format, request.maxIccProfileBytes, request.maxMetadataBytes),
      NativeOperation.encode => nativeEncode(
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
    final String error = nativeResultError(result).toDartString();
    if (error.isNotEmpty) {
      throw ImageCodecException(error);
    }
    return NativeResult(
      width: nativeResultNumber(result, 0),
      height: nativeResultNumber(result, 1),
      depth: nativeResultNumber(result, 2),
      sourceDepth: nativeResultNumber(result, 3),
      colorModel: nativeResultNumber(result, 8),
      bytes: _copyBuffer(result, 0) ?? Uint8List(0),
      iccProfile: _copyBuffer(result, 1),
      exifMetadata: _copyBuffer(result, 2),
      xmpMetadata: _copyBuffer(result, 3),
    );
  } finally {
    nativeResultFree(result);
    calloc.free(input);
  }
}

/// Copies one borrowed native buffer into Dart-owned storage.
Uint8List? _copyBuffer(Pointer<NativeCodecResult> result, int field) {
  final int size = nativeResultNumber(result, field + 4);
  if (size == 0) {
    return null;
  }
  final Pointer<Uint8> pointer = nativeResultData(result, field);
  if (pointer == nullptr) {
    throw const ImageCodecException('Native codec returned a null buffer');
  }
  return Uint8List.fromList(pointer.asTypedList(size));
}
