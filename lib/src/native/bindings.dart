@DefaultAsset('package:imcodec_native/src/native/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Opaque bridge result; no third-party structure crosses the Dart ABI.
final class NativeCodecResult extends Opaque;

/// Decodes one primary or first visible image into an owned result.
@Native<Pointer<NativeCodecResult> Function(Pointer<Uint8>, Size, Int, Size, Size, Int, Size)>(symbol: 'imcodec_decode')
external Pointer<NativeCodecResult> nativeDecode(Pointer<Uint8> bytes, int size, int format, int maxPixels, int maxDecodedBytes, int preserveDepth, int maxIccBytes);

/// Inspects one image without decoding pixels.
@Native<Pointer<NativeCodecResult> Function(Pointer<Uint8>, Size, Int, Size, Size)>(symbol: 'imcodec_inspect')
external Pointer<NativeCodecResult> nativeInspect(Pointer<Uint8> bytes, int size, int format, int maxIccBytes, int maxMetadataBytes);

/// Encodes straight RGBA8 pixels with the selected bundled codec.
@Native<Pointer<NativeCodecResult> Function(Pointer<Uint8>, Size, Int, Int, Int, Int, Int, Int, Size)>(symbol: 'imcodec_encode')
external Pointer<NativeCodecResult> nativeEncode(Pointer<Uint8> bytes, int size, int width, int height, int format, int quality, int lossless, int speed, int maxOutputBytes);

/// Releases every allocation owned by one bridge result.
@Native<Void Function(Pointer<NativeCodecResult>)>(symbol: 'imcodec_result_free')
external void nativeResultFree(Pointer<NativeCodecResult> result);

/// Reads a dimension, sample depth, or buffer length from a bridge result.
@Native<Size Function(Pointer<NativeCodecResult>, Int)>(symbol: 'imcodec_result_number')
external int nativeResultNumber(Pointer<NativeCodecResult> result, int field);

/// Borrows one buffer until the result is released.
@Native<Pointer<Uint8> Function(Pointer<NativeCodecResult>, Int)>(symbol: 'imcodec_result_data')
external Pointer<Uint8> nativeResultData(Pointer<NativeCodecResult> result, int field);

/// Borrows the result's error message, empty on success.
@Native<Pointer<Utf8> Function(Pointer<NativeCodecResult>)>(symbol: 'imcodec_result_error')
external Pointer<Utf8> nativeResultError(Pointer<NativeCodecResult> result);

/// Reports the bundled runtime versions.
@Native<Pointer<Utf8> Function()>(symbol: 'imcodec_version')
external Pointer<Utf8> nativeVersion();
