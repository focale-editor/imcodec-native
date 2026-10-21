import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

/// A matrix/TRC Adobe RGB (1998) compatible profile; any valid ICC would do.
final Uint8List _adobeRgbProfile = base64.decode(
  'AAABwEZDTCAEMAAAbW50clJHQiBYWVogB+oAAQABAAAAAAAAYWNzcEFQUEwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPbWAAEAAAAA0y1GQ0wgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJclhZWgAAAPAAAAAUZ1hZWgAAAQQAAAAUYlhZWgAAARgAAAAUclRSQwAAASwAAAAOZ1RSQwAAASwAAAAOYlRSQwAAASwAAAAOd3RwdAAAATwAAAAUZGVzYwAAAVAAAAAgY3BydAAAAXAAAABQWFlaIAAAAAAAAJwYAABPpQAABPxYWVogAAAAAAAANI0AAKAsAAAPlVhZWiAAAAAAAAAmMQAAEC8AAL6bY3VydgAAAAAAAAABAjMAAFhZWiAAAAAAAAD21gABAAAAANMtZGVzYwAAAAAAAAARQWRvYmUgUkdCICgxOTk4KQAAAAB0ZXh0AAAAAFB1YmxpYyBkb21haW4gQWRvYmUgUkdCICgxOTk4KSBjb21wYXRpYmxlIHByb2ZpbGUgZ2VuZXJhdGVkIGJ5IEZvY2FsZQAAAA==',
);

/// Sixteen-bit straight RGBA whose values fall between eight-bit steps.
DecodedImage _samples({Uint8List? iccProfile}) {
  const int width = 8;
  const int height = 6;
  final ByteData data = ByteData(width * height * 8);
  for (int pixel = 0; pixel < width * height; pixel++) {
    for (int channel = 0; channel < 4; channel++) {
      final int value = channel == 3 ? 65535 : (pixel * 1021 + channel * 7919 + 128) % 65536;
      data.setUint16((pixel * 4 + channel) * 2, value, Endian.little);
    }
  }
  return DecodedImage(
    width: width,
    height: height,
    colorModel: DecodedColorModel.rgb,
    sampleFormat: DecodedSampleFormat.uint16,
    iccProfile: iccProfile,
    bytes: data.buffer.asUint8List(),
  );
}

/// Largest difference between two sixteen-bit sample buffers, scaled to 16 bits.
int _difference(DecodedImage expected, DecodedImage actual) {
  final ByteData left = ByteData.sublistView(expected.bytes);
  final ByteData right = ByteData.sublistView(actual.bytes);
  final int scale = actual.sampleFormat == DecodedSampleFormat.uint16 ? 1 : 257;
  int largest = 0;
  for (int index = 0; index < expected.bytes.length ~/ 2; index++) {
    final int value = actual.sampleFormat == DecodedSampleFormat.uint16 ? right.getUint16(index * 2, Endian.little) : actual.bytes[index];
    final int difference = (left.getUint16(index * 2, Endian.little) - value * scale).abs();
    largest = difference > largest ? difference : largest;
  }
  return largest;
}

/// Encodes deeper samples with their ICC profile through the bundled engines.
void main() {
  setUpAll(() async {
    await ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null);
  });

  test('lossless JPEG XL keeps sixteen-bit samples and their profile exactly', () {
    final DecodedImage source = _samples(iccProfile: _adobeRgbProfile);

    final DecodedImage decoded = decodeImageData(const NativeJpegXlEncoder().encodeSamples(source));

    expect(decoded.sampleFormat, DecodedSampleFormat.uint16);
    expect(_difference(source, decoded), 0);
    expect(decoded.iccProfile, isNotNull);
  });

  test('lossless AVIF keeps ten bits of sixteen-bit samples and their profile', () {
    final DecodedImage source = _samples(iccProfile: _adobeRgbProfile);

    final DecodedImage decoded = decodeImageData(const AvifEncoder().encodeSamples(source, encodeOptions: const AvifEncodeOptions(lossless: true, speed: 9)));

    expect(decoded.sampleFormat, DecodedSampleFormat.uint16);
    // Ten bits round each sample to within half of a 1/1023 step.
    expect(_difference(source, decoded), lessThanOrEqualTo(33));
    expect(decoded.iccProfile, _adobeRgbProfile);
  });

  test('HEIC and lossless WebP embed the profile of eight-bit reductions', () {
    final DecodedImage source = _samples(iccProfile: _adobeRgbProfile);

    final DecodedImage webp = decodeImageData(const NativeWebPEncoder().encodeSamples(source));
    final DecodedImage heic = decodeImageData(const HeifEncoder().encodeSamples(source, encodeOptions: const HeifEncodeOptions(quality: 100)));

    expect(webp.iccProfile, _adobeRgbProfile);
    expect(_difference(source, webp), lessThanOrEqualTo(128));
    expect(heic.iccProfile, _adobeRgbProfile);
  });

  test('eight-bit samples without a profile match the RGBA8 encoder', () {
    final Image image = Image(width: 4, height: 3);
    final DecodedImage samples = DecodedImage.fromImage(image);

    expect(const NativeWebPEncoder().encodeSamples(samples), const NativeWebPEncoder().encode(image));
  });

  test('RGBA8-only codecs reject sample encoding', () {
    expect(() => const NativePngEncoder().encodeSamples(_samples()), throwsUnsupportedError);
  });
}
