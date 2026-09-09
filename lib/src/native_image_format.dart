import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/backend/native_request.dart';

/// Additional formats supplied by ImcodecNative's bundled engines.
final class NativeImageFormat extends ImageFormat with InspectableFormat {
  /// Stable identifier understood by the native and WebAssembly bridge.
  final int codecId;

  /// Creates one canonical optional format.
  const NativeImageFormat._({required super.name, required this.codecId});

  /// AV1 Image File Format.
  static const NativeImageFormat avif = NativeImageFormat._(name: 'avif', codecId: 1);

  /// HEVC images in HEIF containers, conventionally named `.heif` or `.heic`.
  static const NativeImageFormat heif = NativeImageFormat._(name: 'heif', codecId: 2);

  /// Alias for [heif] using the conventional Apple file extension.
  static const NativeImageFormat heic = heif;

  @override
  bool matches(Uint8List bytes) => identical(sniff(bytes), this);

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes,
    int maxIccProfileBytes,
    int maxDescriptiveMetadataBytes,
  ) {
    if (!matches(bytes)) {
      throw ImageCodecException('Expected $name image data');
    }
    return backend
        .execute(
          NativeRequest(
            operation: NativeOperation.inspect,
            format: codecId,
            bytes: bytes,
            maxIccProfileBytes: maxIccProfileBytes,
            maxMetadataBytes: maxDescriptiveMetadataBytes,
          ),
        )
        .toMetadata();
  }

  /// Detects still-image brands from a bounded ISO base media file-type box.
  ///
  /// Sequence-only brands and MP4 video are deliberately excluded. An AVIF
  /// compatible brand wins over generic HEIF brands regardless of brand order.
  static NativeImageFormat? sniff(Uint8List bytes) {
    if (bytes.length < 16) {
      return null;
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (data.getUint32(4) != 0x66747970) {
      return null;
    }
    final int shortSize = data.getUint32(0);
    int headerSize = 8;
    int boxSize = shortSize;
    if (shortSize == 1) {
      if (bytes.length < 24 || data.getUint32(8) != 0) {
        return null;
      }
      boxSize = data.getUint32(12);
      headerSize = 16;
    } else if (shortSize == 0) {
      boxSize = bytes.length;
    }
    if (boxSize < headerSize + 8 || boxSize > bytes.length || boxSize > 4096 || (boxSize - headerSize) % 4 != 0) {
      return null;
    }
    bool heifBrand = false;
    bool genericBrand = false;
    bool sequenceBrand = false;
    for (int position = headerSize; position < boxSize; position += 4) {
      if (position == headerSize + 4) {
        continue;
      }
      final int brand = data.getUint32(position);
      if (brand == 0x61766966) {
        return avif;
      }
      if (brand == 0x68656963 || brand == 0x68656978) {
        heifBrand = true;
      }
      genericBrand = genericBrand || brand == 0x6d696631;
      sequenceBrand = sequenceBrand || brand == 0x61766973 || brand == 0x6d736631 || brand == 0x68657663 || brand == 0x68657678;
    }
    return heifBrand || (genericBrand && !sequenceBrand) ? heif : null;
  }
}
