import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/codecs/avif.dart';
import 'package:imcodec_native/src/codecs/heif.dart';
import 'package:imcodec_native/src/codecs/jpeg.dart';
import 'package:imcodec_native/src/codecs/jpeg_xl.dart';
import 'package:imcodec_native/src/codecs/open_exr.dart';
import 'package:imcodec_native/src/codecs/png.dart';
import 'package:imcodec_native/src/codecs/qoi.dart';
import 'package:imcodec_native/src/codecs/tiff.dart';
import 'package:imcodec_native/src/codecs/webp.dart';

/// Decodes the primary AVIF image to straight RGBA8.
Image decodeAvif(
  Uint8List bytes, {
  AvifDecodeOptions? options,
}) => const AvifCodec().decode(
  bytes,
  decodeOptions: options,
);

/// Decodes the primary HEIF/HEIC image to straight RGBA8.
Image decodeHeif(
  Uint8List bytes, {
  HeifDecodeOptions? options,
}) => const HeifCodec().decode(
  bytes,
  decodeOptions: options,
);

/// Decodes the primary HEIC image to straight RGBA8.
Image decodeHeic(
  Uint8List bytes, {
  HeifDecodeOptions? options,
}) => decodeHeif(
  bytes,
  options: options,
);

/// Decodes AVIF samples while preserving high-bit-depth input and ICC profiles.
DecodedImage decodeAvifData(
  Uint8List bytes, {
  AvifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const AvifDecoder().decodeData(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes HEIF/HEIC samples while preserving high-bit-depth input and ICC profiles.
DecodedImage decodeHeifData(
  Uint8List bytes, {
  HeifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const HeifDecoder().decodeData(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes HEIC samples while preserving high-bit-depth input and ICC profiles.
DecodedImage decodeHeicData(
  Uint8List bytes, {
  HeifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => decodeHeifData(
  bytes,
  options: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes AVIF on a native isolate or browser Worker.
Future<Image> decodeAvifAsync(
  Uint8List bytes, {
  AvifDecodeOptions? options,
}) => const AvifDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Decodes HEIF/HEIC on a native isolate or browser Worker.
Future<Image> decodeHeifAsync(
  Uint8List bytes, {
  HeifDecodeOptions? options,
}) => const HeifDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Decodes HEIC on a native isolate or browser Worker.
Future<Image> decodeHeicAsync(
  Uint8List bytes, {
  HeifDecodeOptions? options,
}) => decodeHeifAsync(
  bytes,
  options: options,
);

/// Preserves high-precision AVIF samples on a native isolate or browser Worker.
Future<DecodedImage> decodeAvifDataAsync(
  Uint8List bytes, {
  AvifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const AvifDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Preserves high-precision HEIF/HEIC samples on a native isolate or browser Worker.
Future<DecodedImage> decodeHeifDataAsync(
  Uint8List bytes, {
  HeifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const HeifDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Preserves high-precision HEIC samples on a native isolate or browser Worker.
Future<DecodedImage> decodeHeicDataAsync(
  Uint8List bytes, {
  HeifDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => decodeHeifDataAsync(
  bytes,
  options: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the first visible JPEG XL frame on an isolate or browser Worker.
Future<Image> decodeJpegXlAsync(
  Uint8List bytes, {
  JpegXlDecodeOptions? options,
}) => const NativeJpegXlDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Decodes the first visible JPEG XL frame on an isolate or browser Worker.
Future<Image> decodeJxlAsync(
  Uint8List bytes, {
  JpegXlDecodeOptions? options,
}) => decodeJpegXlAsync(
  bytes,
  options: options,
);

/// Preserves native JPEG XL samples on an isolate or browser Worker.
Future<DecodedImage> decodeJpegXlDataAsync(
  Uint8List bytes, {
  JpegXlDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeJpegXlDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the first composited WebP frame on an isolate or browser Worker.
Future<Image> decodeWebPAsync(
  Uint8List bytes, {
  WebPDecodeOptions? options,
}) => const NativeWebPDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native WebP samples on an isolate or browser Worker.
Future<DecodedImage> decodeWebPDataAsync(
  Uint8List bytes, {
  WebPDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeWebPDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the primary PNG image on an isolate or browser Worker.
Future<Image> decodePngAsync(
  Uint8List bytes, {
  PngDecodeOptions? options,
}) => const NativePngDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native PNG samples on an isolate or browser Worker.
Future<DecodedImage> decodePngDataAsync(
  Uint8List bytes, {
  PngDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativePngDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the primary JPEG image on an isolate or browser Worker.
Future<Image> decodeJpegAsync(
  Uint8List bytes, {
  JpegDecodeOptions? options,
}) => const NativeJpegDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native JPEG samples on an isolate or browser Worker.
Future<DecodedImage> decodeJpegDataAsync(
  Uint8List bytes, {
  JpegDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeJpegDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the primary QOI image on an isolate or browser Worker.
Future<Image> decodeQoiAsync(
  Uint8List bytes, {
  QoiDecodeOptions? options,
}) => const NativeQoiDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native QOI samples on an isolate or browser Worker.
Future<DecodedImage> decodeQoiDataAsync(
  Uint8List bytes, {
  QoiDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeQoiDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the primary TIFF image on an isolate or browser Worker.
Future<Image> decodeTiffAsync(
  Uint8List bytes, {
  TiffDecodeOptions? options,
}) => const NativeTiffDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native TIFF samples on an isolate or browser Worker.
Future<DecodedImage> decodeTiffDataAsync(
  Uint8List bytes, {
  TiffDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeTiffDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);

/// Decodes the primary OpenEXR image on an isolate or browser Worker.
Future<Image> decodeOpenExrAsync(
  Uint8List bytes, {
  OpenExrDecodeOptions? options,
}) => const NativeOpenExrDecoder().decodeAsync(
  bytes,
  decodeOptions: options,
);

/// Preserves native OpenEXR samples on an isolate or browser Worker.
Future<DecodedImage> decodeOpenExrDataAsync(
  Uint8List bytes, {
  OpenExrDecodeOptions? options,
  int maxDecodedBytes = defaultMaxDecodedBytes,
  int maxIccProfileBytes = defaultMaxIccProfileBytes,
}) => const NativeOpenExrDecoder().decodeDataAsync(
  bytes,
  decodeOptions: options,
  maxDecodedBytes: maxDecodedBytes,
  maxIccProfileBytes: maxIccProfileBytes,
);
