import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

/// Density and orientation that the bundled engines do not handle themselves.
void main() {
  setUpAll(() async {
    await ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null);
  });

  /// A 4 × 2 image whose every pixel is distinct.
  Image source() {
    final Image image = Image(width: 4, height: 2);
    for (int y = 0; y < 2; y++) {
      for (int x = 0; x < 4; x++) {
        image.setPixelRgba(x, y, x * 60, y * 200, 30, 255);
      }
    }
    return image;
  }

  test('PNG, JPEG and TIFF encoders record the requested pixel density', () {
    final Image image = source();
    final Map<String, Uint8List> encoded = {
      'png': const NativePngEncoder().encode(image, encodeOptions: const PngEncodeOptions(pixelsPerInch: 300)),
      'jpeg': const NativeJpegEncoder().encode(image, encodeOptions: const JpegEncodeOptions(pixelsPerInch: 300)),
      'tiff': const NativeTiffEncoder().encode(image, encodeOptions: const TiffEncodeOptions(pixelsPerInch: 300)),
    };

    for (final MapEntry<String, Uint8List> entry in encoded.entries) {
      final DecodedImageMetadata? metadata = inspectImage(entry.value);
      expect(metadata?.pixelsPerInch, closeTo(300, 0.01), reason: entry.key);
      expect(decodeImage(entry.value).width, 4, reason: '${entry.key} still decodes');
    }
  });

  test('an encoder without a requested density writes none', () {
    final Uint8List png = const NativePngEncoder().encode(source());

    expect(inspectImage(png)?.pixelsPerInch, isNull);
  });

  test('native JPEG decoding applies the EXIF orientation like the Dart decoder', () {
    final Uint8List jpeg = const NativeJpegEncoder().encode(source(), encodeOptions: const JpegEncodeOptions(quality: 100));
    for (int orientation = 1; orientation <= 8; orientation++) {
      final Uint8List oriented = _withExifOrientation(jpeg, orientation);

      final Image native = const NativeJpegDecoder().decode(oriented);
      final DecodedImage data = const NativeJpegDecoder().decodeData(oriented);
      final Image dart = const JpegDecoder().decode(oriented);

      expect((native.width, native.height), (dart.width, dart.height), reason: 'orientation $orientation');
      expect((data.width, data.height), (dart.width, dart.height), reason: 'orientation $orientation');
      // Lossy decoders differ slightly, but each pixel must land in the same place.
      for (int offset = 0; offset < native.bytes.length; offset++) {
        expect(native.bytes[offset], closeTo(dart.bytes[offset], 12), reason: 'orientation $orientation byte $offset');
      }
    }
  });
}

/// Inserts a minimal EXIF segment carrying [orientation] after the SOI marker.
Uint8List _withExifOrientation(Uint8List jpeg, int orientation) {
  final List<int> exif = [
    0x45, 0x78, 0x69, 0x66, 0, 0, // Exif header.
    0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, // Little-endian TIFF, directory at 8.
    1, 0, // One entry.
    0x12, 0x01, 3, 0, 1, 0, 0, 0, orientation, 0, 0, 0, // Orientation.
    0, 0, 0, 0, // No further directory.
  ];
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    0xFF, 0xE1, (exif.length + 2) >> 8, (exif.length + 2) & 0xFF, ...exif, //
    ...jpeg.sublist(2),
  ]);
}
