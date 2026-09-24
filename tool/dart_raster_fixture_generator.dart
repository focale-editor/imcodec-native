import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';

/// Freezes Dart VM encoder output for independent browser interoperability.
///
/// Imcodec 0.4.2's Dart OpenEXR uint64 accessors cannot run in JavaScript.
void main() {
  final Image image = Image(width: 17, height: 9);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, (x * 13 + y * 7) % 256, (y * 27 + 33) % 256, (x * 7 + y * 19) % 256, [0, 1, 64, 128, 254, 255][(x + y) % 6]);
    }
  }
  final Image solid = Image(width: 16, height: 16);
  for (int y = 0; y < 16; y++) {
    for (int x = 0; x < 16; x++) {
      solid.setPixelRgba(x, y, 200, 60, 30, 255);
    }
  }
  final Map<String, Uint8List> fixtures = {
    for (final OpenExrCompression compression in OpenExrCompression.values)
      'exr${compression.name}': const OpenExrEncoder().encode(image, encodeOptions: OpenExrEncodeOptions(compression: compression)),
    'exrHdr': OpenExrEncoder.encodeFloat32Rgba(
      width: 2,
      height: 1,
      pixels: Float32List.fromList([1.5, -0.25, 0.5, 1, 0.125, 0.25, 0.75, 0.5]),
      options: const OpenExrEncodeOptions(),
    ),
    for (final JpegChroma chroma in JpegChroma.values) 'jpeg${chroma.name}': const JpegEncoder().encode(solid, encodeOptions: JpegEncodeOptions(quality: 95, chroma: chroma)),
  };
  final StringBuffer output = StringBuffer(
    "import 'dart:convert';\nimport 'dart:typed_data';\n\n/// Original fixtures from tool/dart_raster_fixture_generator.dart.\nUint8List dartRasterFixture(String name) => base64Decode(_fixtures[name]!);\n\nconst Map<String, String> _fixtures = {\n",
  );
  for (final MapEntry<String, Uint8List> entry in fixtures.entries) {
    final String encoded = base64Encode(entry.value);
    output.writeln("  '${entry.key}':");
    for (int position = 0; position < encoded.length; position += 100) {
      final int end = (position + 100).clamp(0, encoded.length);
      output.writeln("      '${encoded.substring(position, end)}'${end == encoded.length ? ',' : ''}");
    }
  }
  output.writeln('};');
  File('test/dart_raster_fixtures.dart').writeAsStringSync(output.toString());
}
