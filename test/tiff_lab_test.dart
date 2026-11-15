import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

/// L*, a* and b* of the three pixels of each fixture.
const List<(double, double, double)> _pixels = [(50, -20, 30), (100, 0, 0), (25, 60, -90)];

/// Uncompressed three-pixel Lab TIFFs: CIELab at eight and sixteen bits and
/// ICCLab at sixteen bits, written by a small independent generator.
const Map<String, String> _fixtures = {
  'CIELab 8-bit':
      'SUkqAAgAAAAJAAABAwABAAAAAwAAAAEBAwABAAAAAQAAAAIBAwADAAAAegAAAAMBAwABAAAAAQAAAAYBAwABAAAACAAAABEBBAABAAAAgAAAABUBAwABAAAAAwAAABYBAwABAAAAAQAAABcBBAABAAAACQAAAAAAAAAIAAgACACA7B7/AABAPKY=',
  'CIELab 16-bit': 'SUkqAAgAAAAJAAABAwABAAAAAwAAAAEBAwABAAAAAQAAAAIBAwADAAAAegAAAAMBAwABAAAAAQAAAAYBAwABAAAACAAAABEBBAABAAAAgAAAABUBAwABAAAAAwAAABYBAwABAAAAAQAAABcBBAABAAAAEgAAAAAAAAAQABAAEAAAgADsAB7//wAAAAAAQAA8AKY=',
  'ICCLab 16-bit': 'SUkqAAgAAAAJAAABAwABAAAAAwAAAAEBAwABAAAAAQAAAAIBAwADAAAAegAAAAMBAwABAAAAAQAAAAYBAwABAAAACQAAABEBBAABAAAAgAAAABUBAwABAAAAAwAAABYBAwABAAAAAQAAABcBBAABAAAAEgAAAAAAAAAQABAAEAAAgGxsnp7//4CAgIAAQLy8JiY=',
};

/// Exercises native CIELab and ICCLab TIFF import.
void main() {
  setUpAll(() => ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null));

  for (final MapEntry<String, String> fixture in _fixtures.entries) {
    test('decodes ${fixture.key} TIFF to ICC-encoded Lab samples', () {
      // Arrange
      final Uint8List bytes = base64Decode(fixture.value);
      final bool wide = !fixture.key.contains('8-bit');

      // Act
      final DecodedImageMetadata metadata = inspectImage(bytes)!;
      final DecodedImage decoded = decodeImageData(bytes);

      // Assert
      expect(metadata.colorModel, DecodedColorModel.lab);
      expect(decoded.colorModel, DecodedColorModel.lab);
      expect(decoded.sampleFormat, wide ? DecodedSampleFormat.uint16 : DecodedSampleFormat.uint8);
      final ByteData data = ByteData.sublistView(decoded.bytes);
      double sample(int pixel, int channel) => wide ? data.getUint16((pixel * 4 + channel) * 2, Endian.little) / 65535 : decoded.bytes[pixel * 4 + channel] / 255;
      final double tolerance = wide ? 1e-4 : 0.6 / 255;
      for (int pixel = 0; pixel < _pixels.length; pixel++) {
        final (double l, double a, double b) = _pixels[pixel];
        expect(sample(pixel, 0), closeTo(l / 100, tolerance));
        expect(sample(pixel, 1), closeTo((a + 128) / 255, tolerance));
        expect(sample(pixel, 2), closeTo((b + 128) / 255, tolerance));
        expect(sample(pixel, 3), 1);
      }
    });
  }

  test('decodes Lab TIFF to display sRGB, matching the Dart conversion', () {
    // Arrange
    final Uint8List bytes = base64Decode(_fixtures['CIELab 16-bit']!);

    // Act
    final Image native = decodeImage(bytes);
    final Image dart = decodeImageData(bytes).toImage();

    // Assert: white stays white; every byte agrees within rounding.
    expect(native.bytes.sublist(4, 8), [255, 255, 255, 255]);
    for (int index = 0; index < native.bytes.length; index++) {
      expect((native.bytes[index] - dart.bytes[index]).abs(), lessThanOrEqualTo(1));
    }
  });
}
