import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';

import 'codec_test.dart' show fileType;

/// Verifies registration and container sniffing without opening native engines.
void main() {
  tearDown(ImcodecNative.unregister);

  test('Imcodec stays agnostic until the add-on registers formats', () {
    final Uint8List bytes = fileType('avif');
    final List<ImageFormat> coreFormats = ImageFormatRegistry.formats;
    expect(ImageFormat.sniff(bytes), isNull);
    expect(ImageFormatRegistry.contains(NativeImageFormat.avif), isFalse);
    ImcodecNative.register();
    expect(ImageFormat.sniff(bytes), NativeImageFormat.avif);
    expect(ImageFormatRegistry.contains(NativeImageFormat.avif), isTrue);
    expect(ImageFormatRegistry.lookup('avif'), same(NativeImageFormat.avif));
    expect(NativeImageFormat.avif, isA<InspectableFormat>());
    expect(NativeImageFormat.heif, isA<InspectableFormat>());
    expect(ImageFormatRegistry.formats, hasLength(coreFormats.length + 2));
    ImcodecNative.unregister();
    expect(ImageFormat.sniff(bytes), isNull);
    expect(ImageFormatRegistry.contains(NativeImageFormat.avif), isFalse);
    expect(ImageFormatRegistry.formats, coreFormats);
  });

  test('compatible brands are inspected and AVIF takes precedence over HEIF', () {
    expect(NativeImageFormat.sniff(fileType('mif1', compatible: ['heic', 'avif'])), NativeImageFormat.avif);
    expect(NativeImageFormat.sniff(fileType('heic', compatible: ['mif1'])), NativeImageFormat.heif);
    expect(NativeImageFormat.sniff(fileType('isom', compatible: ['mp42'])), isNull);
    expect(NativeImageFormat.sniff(fileType('avis')), isNull);
    expect(NativeImageFormat.sniff(fileType('msf1')), isNull);
    expect(NativeImageFormat.sniff(fileType('avis', compatible: ['mif1', 'msf1'])), isNull);
    expect(NativeImageFormat.sniff(fileType('hevc', compatible: ['mif1', 'msf1'])), isNull);
  });

  test('truncated, malformed and oversized file-type boxes do not sniff', () {
    final Uint8List bytes = fileType('avif');
    for (int length = 0; length < bytes.length; length++) {
      expect(NativeImageFormat.sniff(Uint8List.sublistView(bytes, 0, length)), isNull);
    }
    ByteData.sublistView(bytes).setUint32(0, 0xffffffff);
    expect(NativeImageFormat.sniff(bytes), isNull);
    ByteData.sublistView(bytes).setUint32(0, 15);
    expect(NativeImageFormat.sniff(bytes), isNull);
  });

  test('extended file-type sizes and byte-buffer offsets are handled', () {
    final Uint8List storage = Uint8List(28);
    final Uint8List bytes = Uint8List.sublistView(storage, 4);
    final ByteData data = ByteData.sublistView(bytes);
    data.setUint32(0, 1);
    data.setUint32(4, 0x66747970);
    data.setUint32(12, 24);
    data.setUint32(16, 0x61766966);
    expect(NativeImageFormat.sniff(bytes), NativeImageFormat.avif);
    data.setUint32(8, 1);
    expect(NativeImageFormat.sniff(bytes), isNull);
  });

  test('HEIC API aliases retain one canonical HEIF format', () {
    expect(NativeImageFormat.heic, same(NativeImageFormat.heif));
    expect(HeicCodec, HeifCodec);
    expect(HeicDecoder, HeifDecoder);
    expect(HeicEncoder, HeifEncoder);
    const HeicCodec codec = HeicCodec();
    expect(codec.format, same(NativeImageFormat.heif));
    expect(codec.rasterEncoder, isA<HeifEncoder>());
    expect(codec.rasterDecoder, isA<HeifDecoder>());
  });
}
