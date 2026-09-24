import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

import 'advanced_raster_fixtures.dart';
import 'codec_test.dart' show testImage;
import 'dart_raster_fixtures.dart';
import 'raster_fixtures.dart';

/// Cross-checks native output with independent Dart and external encoders.
void main() {
  setUpAll(() => ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null));

  for (final (String, Codec<Image, Uint8List>, Codec<Image, Uint8List>) entry in [
    ('PNG', const NativePngCodec(), const PngCodec()),
    ('QOI', const NativeQoiCodec(), const QoiCodec()),
    ('TIFF', const NativeTiffCodec(), const TiffCodec()),
  ]) {
    test('${entry.$1} interoperates losslessly in both directions', () {
      final Image source = testImage();
      final Uint8List encoded = entry.$2.encode(source);
      expect(entry.$3.decode(encoded).bytes, source.bytes);
      expect(entry.$2.decode(entry.$3.encode(source)).bytes, source.bytes);
      expect(decodeImage(encoded).bytes, source.bytes);
      expect(decodeImageData(encoded).bytes, source.bytes);
      expect(inspectImage(encoded)?.width, source.width);
    });
  }

  test('JPEG interoperates with Dart and honours both chroma settings', () {
    final Image source = Image(width: 16, height: 16);
    for (int y = 0; y < 16; y++) {
      for (int x = 0; x < 16; x++) {
        source.setPixelRgba(x, y, 200, 60, 30, 255);
      }
    }
    for (final JpegChroma chroma in JpegChroma.values) {
      final JpegEncodeOptions options = JpegEncodeOptions(quality: 95, chroma: chroma);
      final Uint8List native = const NativeJpegEncoder().encode(source, encodeOptions: options);
      // Use VM-authored reference bytes where the old Dart codec differs on JS.
      final Uint8List dart = kIsWeb ? dartRasterFixture('jpeg${chroma.name}') : const JpegEncoder().encode(source, encodeOptions: options);
      for (final Image decoded in [if (!kIsWeb) const JpegDecoder().decode(native), const NativeJpegDecoder().decode(dart), decodeImage(native)]) {
        expect((decoded.width, decoded.height), (16, 16));
        _expectClose(decoded.bytes, source.bytes, 3);
      }
      expect(encodeJpeg(source, options: options), native);
    }
  });

  test('JPEG decodes external progressive and CMYK images', () {
    final Uint8List progressive = rasterFixture('progressiveJpeg');
    final DecodedImage decoded = const NativeJpegDecoder().decodeData(progressive);
    expect((decoded.width, decoded.height), (2, 2));
    expect(decoded.iccProfile, isNotEmpty);
    expect(const NativeJpegDecoder().inspect(progressive).iccProfile, decoded.iccProfile);
    final Image cmyk = const NativeJpegDecoder().decode(rasterFixture('cmykJpeg'));
    expect(cmyk.bytes, [
      for (int i = 0; i < 4; i++) ...[255, 0, 0, 255],
    ]);
    expect(() => const NativeJpegDecoder(maxIccProfileBytes: 8).decode(progressive), throwsA(isA<ImageCodecException>()));
  });

  test('PNG inspection retains EXIF after IDAT without decoding pixels', () {
    expect(const NativePngDecoder().inspect(rasterFixture('png16')).exifMetadata, hasLength(14));
    expect(() => const NativePngDecoder().inspect(rasterFixture('png16'), maxMetadataBytes: 4), throwsA(isA<ImageCodecException>()));
  });

  test('PNG expands palette transparency and retains hidden colours', () {
    expect(const NativePngDecoder().decode(rasterFixture('palettePng')).bytes, [255, 0, 0, 0, 0, 255, 0, 128, 0, 0, 255, 255, 0, 255, 0, 128]);
  });

  for (final String name in ['png16', 'interlacedPng16', 'tiff16', 'tiff16BigEndian', 'tiff16Tiled', 'tiff16Planar']) {
    test('$name retains every uint16 sample and ICC bytes', () {
      final Uint8List input = rasterFixture(name);
      final DecodedImage decoded = decodeImageData(input);
      expect(decoded.sampleFormat, DecodedSampleFormat.uint16);
      expect((decoded.width, decoded.height), (2, 2));
      final ByteData data = ByteData.sublistView(decoded.bytes);
      expect([for (int i = 0; i < 16; i++) data.getUint16(i * 2, Endian.little)], [0, 257, 32639, 0, 12345, 23456, 34567, 45678, 65535, 64250, 61680, 65535, 25443, 16962, 8481, 16448]);
      expect(decoded.iccProfile, isNotEmpty);
      expect(inspectImage(input)?.bitsPerChannel, 16);
      expect(() => decodeImageData(input, maxDecodedBytes: 31), throwsA(isA<ImageCodecException>()));
      expect(() => decodeImageData(input, maxIccProfileBytes: 8), throwsA(isA<ImageCodecException>()));
    });
  }

  test('TIFF retains floating-point HDR and reads BigTIFF', () {
    final DecodedImage decoded = const NativeTiffDecoder().decodeData(rasterFixture('tiffFloat'));
    expect(decoded.sampleFormat, DecodedSampleFormat.float32);
    final ByteData data = ByteData.sublistView(decoded.bytes);
    expect([for (int i = 0; i < 8; i++) data.getFloat32(i * 4, Endian.little)], [1.5, -0.25, 0.5, 1, 0.125, 0.25, 0.75, 0.5]);
    expect(const NativeTiffDecoder().decode(rasterFixture('bigTiff')).bytes, [0, 1, 127, 0, 30, 60, 90, 128, 255, 250, 240, 255, 99, 66, 33, 64]);
  });

  test('TIFF applies all eight orientations without altering straight alpha', () {
    for (int orientation = 1; orientation <= 8; orientation++) {
      final Image image = const NativeTiffDecoder().decode(rasterFixture('tiffOrientation$orientation'));
      expect((image.width, image.height), orientation >= 5 ? (1, 2) : (2, 1));
      final bool reversed = [2, 3, 7, 8].contains(orientation);
      expect(image.bytes, reversed ? [30, 60, 90, 128, 0, 1, 127, 0] : [0, 1, 127, 0, 30, 60, 90, 128]);
    }
  });

  test('OpenEXR interoperates with Dart for every encoder compression', () {
    final Image source = testImage();
    for (final OpenExrCompression compression in OpenExrCompression.values) {
      final OpenExrEncodeOptions options = OpenExrEncodeOptions(compression: compression);
      final Uint8List native = const NativeOpenExrEncoder().encode(source, encodeOptions: options);
      // Imcodec 0.4.2's Dart OpenEXR path uses unsupported JS uint64 accessors.
      final Uint8List dart = kIsWeb ? dartRasterFixture('exr${compression.name}') : const OpenExrEncoder().encode(source, encodeOptions: options);
      if (!kIsWeb) {
        _expectClose(const OpenExrDecoder().decode(native).bytes, source.bytes, 1);
      }
      _expectClose(const NativeOpenExrDecoder().decode(dart).bytes, source.bytes, 1);
      _expectClose(decodeImage(native).bytes, source.bytes, 1);
      expect(decodeImageData(native).sampleFormat, DecodedSampleFormat.float32);
      expect(inspectImage(native)?.bitsPerChannel, 16);
      expect(encodeOpenExr(source, options: options), native);
    }
  });

  test('OpenEXR preserves extended sRGB HDR values in float32', () {
    final Float32List source = Float32List.fromList([1.5, -0.25, 0.5, 1, 0.125, 0.25, 0.75, 0.5]);
    final Uint8List encoded = kIsWeb ? dartRasterFixture('exrHdr') : OpenExrEncoder.encodeFloat32Rgba(width: 2, height: 1, pixels: source, options: const OpenExrEncodeOptions());
    final DecodedImage decoded = const NativeOpenExrDecoder().decodeData(encoded);
    final ByteData data = ByteData.sublistView(decoded.bytes);
    for (int i = 0; i < source.length; i++) {
      expect(data.getFloat32(i * 4, Endian.little), closeTo(source[i], 0.002));
    }
  });

  test('lossless JPEG retains four-, twelve- and sixteen-bit samples', () {
    for (final int depth in [4, 12, 16]) {
      final Uint8List bytes = advancedRasterFixture('jpeg$depth');
      final DecodedImage decoded = const NativeJpegDecoder().decodeData(bytes);
      expect(const NativeJpegDecoder().inspect(bytes).bitsPerChannel, depth);
      expect(decoded.sampleFormat, depth == 4 ? DecodedSampleFormat.uint8 : DecodedSampleFormat.uint16);
      final List<int> samples = switch (depth) {
        4 => [0, 1, 7, 15, 15, 8, 3, 15],
        12 => [0, 1, 1234, 4095, 4095, 2048, 3012, 4095],
        _ => [0, 1, 12345, 65535, 65535, 32768, 45678, 65535],
      };
      final int maximum = (1 << depth) - 1;
      final ByteData data = ByteData.sublistView(decoded.bytes);
      for (int i = 0; i < samples.length; i++) {
        final int value = depth == 4 ? decoded.bytes[i] : data.getUint16(i * 2, Endian.little);
        expect(value, (samples[i] * (depth == 4 ? 255 : 65535) + maximum ~/ 2) ~/ maximum);
      }
    }
  });

  test('OpenEXR reads layered float channels with offset windows and PIZ tiles', () {
    for (final String name in ['exrFloatOffset', 'exrTiled']) {
      final Uint8List bytes = advancedRasterFixture(name);
      final DecodedImage decoded = const NativeOpenExrDecoder().decodeData(bytes);
      expect((decoded.width, decoded.height), (2, 1));
      expect(const NativeOpenExrDecoder().inspect(bytes).bitsPerChannel, 32);
      final ByteData data = ByteData.sublistView(decoded.bytes);
      expect(data.getFloat32(0, Endian.little), closeTo(1.19418, 0.0001));
      expect(data.getFloat32(4, Endian.little), closeTo(-0.53710, 0.0001));
      expect(data.getFloat32(8, Endian.little), closeTo(0.73536, 0.0001));
      expect(data.getFloat32(28, Endian.little), 0.5);
    }
    final DecodedImage gray = const NativeOpenExrDecoder().decodeData(advancedRasterFixture('exrLuminance'));
    final ByteData data = ByteData.sublistView(gray.bytes);
    expect(data.getFloat32(0, Endian.little), closeTo(0.53710, 0.0001));
    expect(data.getFloat32(4, Endian.little), data.getFloat32(0, Endian.little));
    expect(data.getFloat32(8, Endian.little), data.getFloat32(0, Endian.little));
    expect(data.getFloat32(12, Endian.little), 1);
  });

  test('failed OpenEXR limits do not alter a later encode', () {
    final Image source = testImage();
    final Uint8List encoded = const NativeOpenExrEncoder().encode(source);
    expect(() => const NativeOpenExrDecoder().decode(encoded, decodeOptions: const OpenExrDecodeOptions(maxPixels: 1)), throwsA(isA<ImageCodecException>()));
    expect(const NativeOpenExrEncoder().encode(source), encoded);
  });

  test('typed encoder options and runners reach native implementations', () async {
    final Image source = testImage();
    for (final int level in [0, 6, 9]) {
      final PngEncodeOptions options = PngEncodeOptions(level: level);
      final Uint8List encoded = const NativePngEncoder().encode(source, encodeOptions: options);
      expect(encodePng(source, options: options), encoded);
      expect(await const NativePngEncoder().encodeWith(runSequentially, source, encodeOptions: options), encoded);
    }
    for (final TiffCompression compression in TiffCompression.values) {
      final TiffEncodeOptions options = TiffEncodeOptions(compression: compression);
      final Uint8List encoded = const NativeTiffEncoder().encode(source, encodeOptions: options);
      expect(encodeTiff(source, options: options), encoded);
      expect(const TiffDecoder().decode(encoded).bytes, source.bytes);
    }
    expect(encodeQoi(source), const NativeQoiEncoder().encode(source));
    expect(() => const NativePngEncoder().encode(source, encodeOptions: const PngEncodeOptions(level: -1)), throwsRangeError);
    expect(() => const NativePngEncoder().encode(source, encodeOptions: const PngEncodeOptions(level: 10)), throwsRangeError);
  });

  test('new decoders run concurrently in native isolates and browser Workers', () async {
    final Image source = testImage();
    final List<Image> images = await Future.wait([
      decodePngAsync(const NativePngEncoder().encode(source)),
      decodeJpegAsync(const NativeJpegEncoder().encode(source)),
      decodeQoiAsync(const NativeQoiEncoder().encode(source)),
      decodeTiffAsync(const NativeTiffEncoder().encode(source)),
      decodeOpenExrAsync(const NativeOpenExrEncoder().encode(source)),
    ]);
    for (final Image image in images) {
      expect((image.width, image.height), (source.width, source.height));
    }
    expect(images[0].bytes, source.bytes);
    expect(images[2].bytes, source.bytes);
    expect(images[3].bytes, source.bytes);
    final List<DecodedImage> data = await Future.wait([
      decodePngDataAsync(rasterFixture('png16')),
      decodeJpegDataAsync(rasterFixture('progressiveJpeg')),
      decodeQoiDataAsync(const QoiEncoder().encode(source)),
      decodeTiffDataAsync(rasterFixture('tiff16')),
      decodeOpenExrDataAsync(dartRasterFixture('exrzip')),
    ]);
    expect(data.map((image) => image.sampleFormat), [DecodedSampleFormat.uint16, DecodedSampleFormat.uint8, DecodedSampleFormat.uint8, DecodedSampleFormat.uint16, DecodedSampleFormat.float32]);
  });

  test('allocation limits and truncated inputs fail without poisoning codecs', () {
    final Image source = testImage();
    for (final Codec<Image, Uint8List> codec in [const NativePngCodec(), const NativeJpegCodec(), const NativeQoiCodec(), const NativeTiffCodec(), const NativeOpenExrCodec()]) {
      final Uint8List encoded = codec.encode(source);
      expect(() => decodeImageData(encoded, maxPixels: 2), throwsA(isA<ImageCodecException>()));
      expect(() => decodeImageData(encoded, maxDecodedBytes: 3), throwsA(isA<ImageCodecException>()));
      for (int attempt = 0; attempt < 3; attempt++) {
        expect(() => codec.decode(Uint8List.sublistView(encoded, 0, encoded.length ~/ 2)), throwsA(isA<ImageCodecException>()));
      }
      expect(codec.decode(encoded).width, source.width);
    }
    for (final Codec<Image, Uint8List> codec in [
      const NativePngCodec(rasterEncoder: NativePngEncoder(maxOutputBytes: 1)),
      const NativeJpegCodec(rasterEncoder: NativeJpegEncoder(maxOutputBytes: 1)),
      const NativeQoiCodec(rasterEncoder: NativeQoiEncoder(maxOutputBytes: 1)),
      const NativeTiffCodec(rasterEncoder: NativeTiffEncoder(maxOutputBytes: 1)),
      const NativeOpenExrCodec(rasterEncoder: NativeOpenExrEncoder(maxOutputBytes: 1)),
    ]) {
      expect(() => codec.encode(source), throwsA(isA<ImageCodecException>()));
    }
  });

  test('QOI rejects invalid opcode lengths and pixel runs', () {
    final Uint8List encoded = const NativeQoiEncoder().encode(testImage());
    encoded[14] = 0xfd;
    final Uint8List malformed = Uint8List.fromList([...encoded.sublist(0, 15), 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(() => const NativeQoiDecoder().decode(malformed), throwsA(isA<ImageCodecException>()));
  });

  test('new registrations are selectable, additive and reversible', () {
    ImcodecNative.unregister();
    addTearDown(ImcodecNative.register);
    const List<ImageFormat> formats = [ImageFormat.png, ImageFormat.jpeg, ImageFormat.qoi, ImageFormat.tiff, ImageFormat.openExr];
    final Map<ImageFormat, ImageCodecExtension?> original = {for (final ImageFormat format in formats) format: ImageCodecRegistry.lookup(format)};
    ImcodecNative.register(avif: false, heif: false, jpegXl: false, webP: false, png: true, jpeg: false, qoi: false, tiff: false, openExr: false);
    expect(ImageCodecRegistry.lookup(ImageFormat.png), isNot(same(original[ImageFormat.png])));
    expect(ImageCodecRegistry.lookup(ImageFormat.jpeg), same(original[ImageFormat.jpeg]));
    ImcodecNative.register();
    for (final ImageFormat format in formats) {
      expect(ImageCodecRegistry.lookup(format), isNot(same(original[format])));
    }
    ImcodecNative.unregister();
    for (final ImageFormat format in formats) {
      expect(ImageCodecRegistry.lookup(format), same(original[format]));
    }
  });
}

void _expectClose(Uint8List actual, Uint8List expected, int tolerance) {
  expect(actual.length, expected.length);
  for (int i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], tolerance), reason: 'sample $i');
  }
}
