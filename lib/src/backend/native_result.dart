import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';

/// Dart-owned copies of all output from one native operation.
final class NativeResult {
  /// Width after applying container transformations.
  final int width;

  /// Height after applying container transformations.
  final int height;

  /// Storage depth of decoded samples: eight, sixteen, or float32.
  final int depth;

  /// Significant source depth reported by the container.
  final int sourceDepth;

  /// Encoded data or decoded pixels.
  final Uint8List bytes;

  /// Embedded ICC profile.
  final Uint8List? iccProfile;

  /// Opaque HEIF EXIF block, including its four-byte TIFF-offset prefix.
  final Uint8List? exifMetadata;

  /// Opaque XMP packet.
  final Uint8List? xmpMetadata;

  /// Takes ownership of bridge output copied into Dart memory.
  const NativeResult({
    required this.width,
    required this.height,
    required this.depth,
    required this.sourceDepth,
    required this.bytes,
    this.iccProfile,
    this.exifMetadata,
    this.xmpMetadata,
  });

  /// Transfers decoded RGBA8 pixels into Imcodec's image model.
  Image toImage() => Image.fromRgba(width: width, height: height, bytes: bytes, copy: false);

  /// Transfers decoded pixels without discarding high-precision samples.
  DecodedImage toImageData() => DecodedImage(
    width: width,
    height: height,
    colorModel: DecodedColorModel.rgb,
    sampleFormat: switch (depth) {
      8 => DecodedSampleFormat.uint8,
      16 => DecodedSampleFormat.uint16,
      32 => DecodedSampleFormat.float32,
      _ => throw ImageCodecException('Unsupported native sample depth: $depth'),
    },
    bytes: bytes,
    iccProfile: iccProfile,
    copy: false,
  );

  /// Retains the inspected container metadata in Imcodec's immutable model.
  DecodedImageMetadata toMetadata() => DecodedImageMetadata(
    width: width,
    height: height,
    bitsPerChannel: sourceDepth,
    colorModel: DecodedColorModel.rgb,
    iccProfile: iccProfile,
    exifMetadata: exifMetadata,
    xmpMetadata: xmpMetadata,
  );
}
