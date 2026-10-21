import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';

/// Maximum size of one encoded output allocation.
const int defaultMaxEncodedBytes = 400000000;

/// Operations supported by the shared native/WebAssembly bridge.
enum NativeOperation {
  /// Decode the primary image.
  decode,

  /// Inspect the primary image without decoding pixels.
  inspect,

  /// Encode tightly packed straight RGBA8.
  encode,

  /// Encode straight RGBA samples of [NativeRequest.bitDepth] with an optional
  /// ICC profile.
  encodeSamples,
}

/// Transferable, pointer-free parameters for one codec operation.
final class NativeRequest {
  /// Requested bridge operation.
  final NativeOperation operation;

  /// Stable format identifier documented by the shared C ABI.
  final int format;

  /// Encoded input or straight RGBA8 pixels.
  final Uint8List bytes;

  /// Input width for encoding.
  final int width;

  /// Input height for encoding.
  final int height;

  /// Compression quality from zero through one hundred.
  final int quality;

  /// Whether lossless encoding was requested.
  final bool lossless;

  /// Format-specific compression effort or speed.
  final int speed;

  /// Decode allocation limit expressed in pixels.
  final int maxPixels;

  /// Decode allocation limit expressed in bytes.
  final int maxDecodedBytes;

  /// Whether to retain high-bit-depth source samples.
  final bool preserveDepth;

  /// Maximum retained ICC payload size.
  final int maxIccProfileBytes;

  /// Maximum retained size of each EXIF or XMP packet.
  final int maxMetadataBytes;

  /// Maximum encoded output size.
  final int maxOutputBytes;

  /// Bits per encoded input sample: eight, or sixteen in little-endian words.
  final int bitDepth;

  /// ICC profile describing the encoded input samples.
  final Uint8List? iccProfile;

  /// Creates one immutable codec request.
  const NativeRequest({
    required this.operation,
    required this.format,
    required this.bytes,
    this.width = 0,
    this.height = 0,
    this.quality = 80,
    this.lossless = false,
    this.speed = 6,
    this.maxPixels = RasterDecodeOptions.defaultMaxPixels,
    this.maxDecodedBytes = defaultMaxDecodedBytes,
    this.preserveDepth = false,
    this.maxIccProfileBytes = defaultMaxIccProfileBytes,
    this.maxMetadataBytes = defaultMaxDescriptiveMetadataBytes,
    this.maxOutputBytes = defaultMaxEncodedBytes,
    this.bitDepth = 8,
    this.iccProfile,
  });

  /// This RGBA8 encode request carrying [image]'s samples and profile instead.
  ///
  /// [image] must hold straight RGB with alpha in eight- or sixteen-bit samples.
  NativeRequest withSamples(DecodedImage image) {
    if (image.colorModel != DecodedColorModel.rgb || image.sampleFormat == DecodedSampleFormat.float32) {
      throw const ImageCodecException('Only eight- and sixteen-bit RGB samples can be encoded');
    }
    return NativeRequest(
      operation: NativeOperation.encodeSamples,
      format: format,
      bytes: image.bytes,
      width: image.width,
      height: image.height,
      quality: quality,
      lossless: lossless,
      speed: speed,
      maxIccProfileBytes: maxIccProfileBytes,
      maxOutputBytes: maxOutputBytes,
      bitDepth: image.sampleFormat.bitsPerChannel,
      iccProfile: image.iccProfile,
    );
  }

  /// Rejects invalid options before allocating native memory.
  void validate() {
    for (final (String, int) limit in [
      ('maxPixels', maxPixels),
      ('maxDecodedBytes', maxDecodedBytes),
      ('maxIccProfileBytes', maxIccProfileBytes),
      ('maxMetadataBytes', maxMetadataBytes),
      ('maxOutputBytes', maxOutputBytes),
    ]) {
      if (limit.$2 < 1 || limit.$2 > 0x7fffffff) {
        throw RangeError.range(limit.$2, 1, 0x7fffffff, limit.$1);
      }
    }
    if (quality < 0 || quality > 100) {
      throw RangeError.range(quality, 0, 100, 'quality');
    }
    if (operation == NativeOperation.encodeSamples) {
      if (bitDepth != 8 && bitDepth != 16) {
        throw RangeError.value(bitDepth, 'bitDepth', 'Samples must have eight or sixteen bits');
      }
      if (format < 1 || format > 4) {
        throw ImageCodecException('Format $format encodes RGBA8 only');
      }
      if ((iccProfile?.length ?? 0) > maxIccProfileBytes) {
        throw const ImageCodecException('The ICC profile exceeds its byte limit');
      }
    }
    if (operation == NativeOperation.encode || operation == NativeOperation.encodeSamples) {
      final int maximumSpeed = switch (format) {
        1 => 9,
        3 => 9,
        4 => 6,
        6 || 8 => 1,
        7 => 0,
        9 => 3,
        _ => 9,
      };
      final int minimumSpeed = format == 3 ? 1 : 0;
      if (speed < minimumSpeed || speed > maximumSpeed) {
        throw RangeError.range(speed, minimumSpeed, maximumSpeed, 'speed');
      }
      if (width < 1 || height < 1 || width > 0x1fffffff || height > 0x1fffffff || bytes.length != width * height * 4 * (operation == NativeOperation.encodeSamples ? bitDepth ~/ 8 : 1)) {
        throw const ImageCodecException('Invalid straight RGBA encoder dimensions');
      }
    }
  }
}
