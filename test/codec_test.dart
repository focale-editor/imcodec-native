import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

import 'fixtures.dart';

/// Exercises real bundled engines rather than substituting codec mocks.
void main() {
  setUpAll(() async {
    await ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null);
  });

  test('all engines are bundled in the loaded runtime', () {
    expect(ImcodecNative.backendVersion, contains('libheif 1.21.2'));
    expect(ImcodecNative.backendVersion, contains('libjxl 0.12.0'));
    expect(ImcodecNative.backendVersion, contains('libwebp 1.6.0'));
  });

  test('lossless AVIF preserves every RGBA byte including hidden RGB', () {
    final Image source = testImage();
    const AvifCodec codec = AvifCodec();
    final Uint8List encoded = codec.encode(
      source,
      encodeOptions: const AvifEncodeOptions(lossless: true, speed: 9),
    );
    expect(ImageFormat.sniff(encoded), NativeImageFormat.avif);
    expect(codec.decode(encoded).bytes, source.bytes);
    expect(codec.decoder.convert(encoded).bytes, source.bytes);
    expect(decodeImage(encoded).bytes, source.bytes);
    expect(decodeImageData(encoded).bytes, source.bytes);
    expect(inspectImage(encoded)?.width, source.width);
  });

  test('repeated AVIF colour and alpha encodes preserve earlier outputs', () {
    final Image source = testImage();
    const AvifEncoder encoder = AvifEncoder();
    const AvifEncodeOptions options = AvifEncodeOptions(lossless: true, speed: 9);
    final Uint8List original = Uint8List.fromList(source.bytes);
    final Uint8List first = encoder.encode(source, encodeOptions: options);
    for (int iteration = 0; iteration < 8; iteration++) {
      source.setPixelRgba(0, 0, iteration * 19, 255 - iteration, 37, iteration.isEven ? 0 : 127);
      final Uint8List encoded = encoder.encode(source, encodeOptions: options);
      expect(decodeAvif(encoded).bytes, source.bytes);
    }
    expect(decodeAvif(first).bytes, original);
  });

  test('repeated HEIC colour and alpha encodes preserve earlier outputs', () {
    final Image source = testImage();
    const HeifEncoder encoder = HeifEncoder();
    final Uint8List first = encoder.encode(source);
    final Uint8List original = Uint8List.fromList(decodeHeif(first).bytes);
    for (int iteration = 0; iteration < 8; iteration++) {
      source.setPixelRgba(0, 0, iteration * 19, 255 - iteration, 37, iteration.isEven ? 0 : 127);
      final Image decoded = decodeHeif(encoder.encode(source));
      for (int offset = 3; offset < source.bytes.length; offset += 4) {
        expect(decoded.bytes[offset], source.bytes[offset]);
      }
    }
    expect(decodeHeif(first).bytes, original);
  });

  test('HEIC preserves dimensions and exact alpha with lossy colour', () {
    final Image source = testImage();
    final Uint8List encoded = encodeHeif(
      source,
      options: const HeifEncodeOptions(quality: 90),
    );
    final Image decoded = decodeImage(encoded);
    expect(ImageFormat.sniff(encoded), NativeImageFormat.heif);
    expect(decoded.width, source.width);
    expect(decoded.height, source.height);
    expect([for (int i = 3; i < decoded.bytes.length; i += 4) decoded.bytes[i]], [for (int i = 3; i < source.bytes.length; i += 4) source.bytes[i]]);
    expect(inspectImage(encoded)?.bitsPerChannel, 8);
  });

  for (final (String, Codec<Image, Uint8List>) entry in [
    ('JPEG XL', const NativeJpegXlCodec()),
    ('WebP', const NativeWebPCodec()),
  ]) {
    test('${entry.$1} direct and registered codecs decode natively', () {
      final Image source = testImage();
      final Uint8List encoded = entry.$2.encoder.convert(source);
      expect(entry.$2.decoder.convert(encoded).bytes, source.bytes);
      expect(decodeImage(encoded).bytes, source.bytes);
      expect(decodeImageData(encoded).bytes, source.bytes);
    });
  }

  for (final (String, Uint8List Function(), int, DecodedSampleFormat) entry in [
    (
      'sixteen-bit',
      jpegXl16Fixture,
      16,
      DecodedSampleFormat.uint16,
    ),
    (
      'floating-point',
      jpegXlFloat32Fixture,
      32,
      DecodedSampleFormat.float32,
    ),
  ]) {
    test('native JPEG XL preserves ${entry.$1} samples', () {
      final Uint8List encoded = entry.$2();
      final DecodedImageMetadata metadata = const NativeJpegXlDecoder().inspect(
        encoded,
      );
      final DecodedImage decoded = const NativeJpegXlDecoder().decodeData(
        encoded,
      );

      expect((metadata.width, metadata.height), (2, 2));
      expect(metadata.bitsPerChannel, entry.$3);
      expect(decoded.sampleFormat, entry.$4);
      expect(decoded.bytes, hasLength(2 * 2 * 4 * entry.$4.bytesPerChannel));
      expect(decodeImageData(encoded).sampleFormat, entry.$4);
    });
  }

  test('generic and format-specific JPEG XL and WebP helpers use native encoders', () {
    final Image image = testImage();
    const JpegXlEncodeOptions jxlOptions = JpegXlEncodeOptions(
      effort: JpegXlEffort.fast,
    );
    const WebPEncodeOptions webPOptions = WebPEncodeOptions(
      effort: WebPEffort.fast,
    );
    final Uint8List jxl = const NativeJpegXlEncoder().encode(
      image,
      encodeOptions: jxlOptions,
    );
    final Uint8List webp = const NativeWebPEncoder().encode(
      image,
      encodeOptions: webPOptions,
    );
    expect(encodeJpegXl(image, options: jxlOptions), jxl);
    expect(
      encodeImage(
        image,
        format: ImageFormat.jpegXl,
        options: jxlOptions,
      ),
      jxl,
    );
    expect(encodeWebP(image, options: webPOptions), webp);
    expect(
      encodeImage(
        image,
        format: ImageFormat.webp,
        options: webPOptions,
      ),
      webp,
    );
    expect(
      encodeWebP(
        image,
        options: const WebPEncodeOptions(quality: 70),
      ),
      const NativeWebPEncoder().encode(
        image,
        encodeOptions: const WebPEncodeOptions(quality: 70),
      ),
    );
  });

  test('converters enforce allocation limits and reject a mismatched format', () {
    final Image source = testImage();
    final Uint8List avif = encodeAvif(
      source,
      options: const AvifEncodeOptions(speed: 9),
    );
    expect(
      () => const AvifCodec().decode(
        avif,
        decodeOptions: const AvifDecodeOptions(maxPixels: 2),
      ),
      throwsA(isA<ImageCodecException>()),
    );
    expect(
      () => decodeImage(
        avif,
        options: const AvifDecodeOptions(maxPixels: 2),
      ),
      throwsA(isA<ImageCodecException>()),
    );
    expect(
      () => decodeImageData(avif, maxPixels: 2),
      throwsA(isA<ImageCodecException>()),
    );
    expect(() => decodeAvifData(avif, maxDecodedBytes: 4), throwsA(isA<ImageCodecException>()));
    expect(() => const HeifDecoder().convert(avif), throwsA(isA<ImageCodecException>()));
    expect(
      () => const AvifEncoder().encode(
        source,
        encodeOptions: const AvifEncodeOptions(quality: 101),
      ),
      throwsRangeError,
    );
    expect(
      () => const AvifEncoder().encode(
        source,
        encodeOptions: const AvifEncodeOptions(speed: -1),
      ),
      throwsRangeError,
    );
    expect(() => const AvifEncoder(maxOutputBytes: 1).encode(source), throwsA(isA<ImageCodecException>()));
    expect(() => const NativeJpegXlEncoder(maxOutputBytes: 1).encode(source), throwsA(isA<ImageCodecException>()));
    expect(() => const NativeWebPEncoder(maxOutputBytes: 1).encode(source), throwsA(isA<ImageCodecException>()));
    final Uint8List jxl = const NativeJpegXlEncoder().encode(source);
    final Uint8List webp = const NativeWebPEncoder().encode(source);
    expect(
      () => const NativeJpegXlDecoder().decode(
        jxl,
        decodeOptions: const JpegXlDecodeOptions(maxPixels: 2),
      ),
      throwsA(isA<ImageCodecException>()),
    );
    expect(
      () => const NativeWebPDecoder(maxDecodedBytes: 4).decode(webp),
      throwsA(isA<ImageCodecException>()),
    );
  });

  test('malformed containers fail repeatedly without poisoning subsequent calls', () async {
    final Uint8List truncated = fileType('avif');
    for (int attempt = 0; attempt < 20; attempt++) {
      expect(() => decodeAvif(truncated), throwsA(isA<ImageCodecException>()));
    }
    final Image source = testImage();
    final Uint8List encoded = encodeAvif(
      source,
      options: const AvifEncodeOptions(lossless: true, speed: 9),
    );
    expect(decodeAvif(encoded).bytes, source.bytes);
    await expectLater(
      decodeAvifAsync(truncated),
      throwsA(isA<ImageCodecException>()),
    );
    expect((await decodeAvifAsync(encoded)).bytes, source.bytes);
  });

  test('native decoder isolates and Web Workers preserve output', () async {
    final Image source = testImage();
    final Uint8List original = Uint8List.fromList(source.bytes);
    final Uint8List encoded = encodeAvif(
      source,
      options: const AvifEncodeOptions(lossless: true, speed: 9),
    );
    expect(source.bytes, original);
    expect((await decodeAvifAsync(encoded)).bytes, original);
    final Uint8List webp = const NativeWebPEncoder().encode(
      source,
      encodeOptions: const WebPEncodeOptions(effort: WebPEffort.fast),
    );
    expect(
      (await decodeWebPAsync(webp)).bytes,
      original,
    );
    final Uint8List jxl = const NativeJpegXlEncoder().encode(
      source,
      encodeOptions: const JpegXlEncodeOptions(effort: JpegXlEffort.fast),
    );
    expect(
      (await decodeJpegXlAsync(jxl)).bytes,
      original,
    );
    expect((await decodeJpegXlDataAsync(jxl)).sampleFormat, DecodedSampleFormat.uint8);
    expect((await decodeWebPDataAsync(webp)).sampleFormat, DecodedSampleFormat.uint8);
  });

  test('registered runner helpers submit native work to the supplied runner', () async {
    int tasks = 0;
    Future<List<O>> runner<I, O>(List<I> inputs, O Function(I) execute) async {
      tasks += inputs.length;
      return inputs.map(execute).toList();
    }

    final Image source = testImage();
    expect(
      await encodeJpegXlWith(
        runner,
        source,
        options: const JpegXlEncodeOptions(effort: JpegXlEffort.fast),
      ),
      encodeJpegXl(
        source,
        options: const JpegXlEncodeOptions(effort: JpegXlEffort.fast),
      ),
    );
    expect(await encodeWebPWith(runner, source), encodeWebP(source));
    expect(await encodeAvifWith(runner, source), encodeAvif(source));
    expect(await encodeHeifWith(runner, source), encodeHeif(source));
    expect(await encodeImageWith(runner, source, format: NativeImageFormat.heif), encodeImage(source, format: NativeImageFormat.heif));
    expect(tasks, 5);
  });

  test('concurrent background decodes safely share native engine state', () async {
    final Image source = testImage();
    final Uint8List avif = encodeAvif(
      source,
      options: const AvifEncodeOptions(lossless: true, speed: 9),
    );
    final Uint8List webp = const NativeWebPEncoder().encode(
      source,
      encodeOptions: const WebPEncodeOptions(effort: WebPEffort.fast),
    );
    final List<Image> results = await Future.wait([
      for (int i = 0; i < 4; i++) decodeAvifAsync(avif),
      for (int i = 0; i < 4; i++) decodeWebPAsync(webp),
    ]);
    for (final Image decoded in results) {
      expect(decoded.bytes, source.bytes);
    }
  });

  for (final int depth in [10, 12]) {
    test('$depth-bit AVIF preserves normalized samples, orientation and metadata', () {
      final Uint8List encoded = depth == 10 ? rgba10Fixture() : rgba12Fixture();
      final DecodedImage decoded = decodeImageData(encoded);
      expect((decoded.width, decoded.height), (5, 3));
      expect(decoded.sampleFormat, DecodedSampleFormat.uint16);
      final ByteData data = ByteData.sublistView(decoded.bytes);
      final int maximum = (1 << depth) - 1;
      for (int y = 0; y < 5; y++) {
        for (int x = 0; x < 3; x++) {
          final int pixel = (x * 5 + 4 - y) * 8;
          for (int channel = 0; channel < 4; channel++) {
            final int sample = channel == 3 ? maximum : (x * 37 + y * 101 + channel * 223) % (maximum + 1);
            expect(data.getUint16(pixel + channel * 2, Endian.little), (sample * 65535 + maximum ~/ 2) ~/ maximum);
          }
        }
      }
      final DecodedImageMetadata metadata = inspectImage(encoded)!;
      final DecodedImageMetadata formatMetadata = NativeImageFormat.avif.inspect(
        encoded,
        defaultMaxIccProfileBytes,
        defaultMaxDescriptiveMetadataBytes,
      );
      expect((metadata.width, metadata.height), (3, 5));
      expect((formatMetadata.width, formatMetadata.height), (3, 5));
      expect(metadata.bitsPerChannel, depth);
      expect(metadata.requiresExactDecoding, isTrue);
      expect(ascii.decode(metadata.iccProfile!), 'ImcodecNative synthetic ICC payload');
      expect(decoded.iccProfile, metadata.iccProfile);
      expect(metadata.exifMetadata, [0, 0, 0, 0, 73, 73, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(ascii.decode(metadata.xmpMetadata!), '<x:xmpmeta xmlns:x="adobe:ns:meta/"/>');
      expect(() => inspectImage(encoded, maxIccProfileBytes: 4), throwsA(isA<ImageCodecException>()));
      expect(() => inspectImage(encoded, maxDescriptiveMetadataBytes: 4), throwsA(isA<ImageCodecException>()));
      expect(() => decodeImageData(encoded, maxDecodedBytes: 119), throwsA(isA<ImageCodecException>()));
    });
  }
}

/// Generates odd-sized colourful input with opaque, translucent and hidden RGB.
Image testImage() {
  final Image image = Image(width: 17, height: 9);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, (x * 13 + y * 7) % 256, (y * 27 + 33) % 256, (x * 7 + y * 19) % 256, [0, 1, 64, 128, 254, 255][(x + y) % 6]);
    }
  }
  return image;
}

/// Creates a complete file-type box without an image payload.
Uint8List fileType(String brand, {List<String> compatible = const []}) {
  final Uint8List bytes = Uint8List(16 + compatible.length * 4);
  final ByteData data = ByteData.sublistView(bytes)..setUint32(0, bytes.length);
  bytes.setRange(4, 8, ascii.encode('ftyp'));
  bytes.setRange(8, 12, ascii.encode(brand));
  for (int i = 0; i < compatible.length; i++) {
    data.setUint32(16 + i * 4, ascii.encode(compatible[i]).fold(0, (value, byte) => (value << 8) | byte));
  }
  return bytes;
}
