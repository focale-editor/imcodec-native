import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';

/// Pixels per inch in one pixel per metre.
const double _inchesPerMetre = 39.37007874015748;

/// Reads the EXIF display orientation of a JPEG, from one to eight.
///
/// The bundled libjpeg-turbo decoder returns stored rows, whereas Imcodec's
/// Dart decoder applies this orientation. Anything malformed reads as one, the
/// untransformed orientation, so a damaged packet never prevents decoding.
int jpegExifOrientation(Uint8List bytes) {
  try {
    int offset = 2;
    while (offset + 4 <= bytes.length && bytes[offset] == 0xFF) {
      final int marker = bytes[offset + 1];
      // Start of scan or end of image: no metadata follows.
      if (marker == 0xDA || marker == 0xD9) {
        return 1;
      }
      final int length = bytes[offset + 2] << 8 | bytes[offset + 3];
      final int start = offset + 4;
      final int end = offset + 2 + length;
      if (length < 2 || end > bytes.length) {
        return 1;
      }
      if (marker == 0xE1 && end - start >= 14 && _matches(bytes, start, const [0x45, 0x78, 0x69, 0x66, 0, 0])) {
        return _tiffOrientation(Uint8List.sublistView(bytes, start + 6, end));
      }
      offset = end;
    }
  } on RangeError {
    return 1;
  }
  return 1;
}

/// Reads tag 274 from the first directory of a TIFF-structured EXIF packet.
int _tiffOrientation(Uint8List tiff) {
  final Endian? endian = switch ((tiff[0], tiff[1])) {
    (0x49, 0x49) => Endian.little,
    (0x4D, 0x4D) => Endian.big,
    _ => null,
  };
  if (endian == null) {
    return 1;
  }
  final ByteData data = ByteData.sublistView(tiff);
  if (data.getUint16(2, endian) != 42) {
    return 1;
  }
  final int directory = data.getUint32(4, endian);
  if (directory + 2 > tiff.length) {
    return 1;
  }
  final int count = data.getUint16(directory, endian);
  for (int index = 0; index < count; index++) {
    final int entry = directory + 2 + index * 12;
    if (entry + 12 > tiff.length) {
      return 1;
    }
    if (data.getUint16(entry, endian) == 274 && data.getUint16(entry + 2, endian) == 3 && data.getUint32(entry + 4, endian) == 1) {
      final int orientation = data.getUint16(entry + 8, endian);
      return orientation >= 1 && orientation <= 8 ? orientation : 1;
    }
  }
  return 1;
}

/// Whether [bytes] holds [expected] at [offset].
bool _matches(Uint8List bytes, int offset, List<int> expected) {
  for (int index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) {
      return false;
    }
  }
  return true;
}

/// Rearranges row-major pixels of any size into display [orientation].
///
/// Follows the EXIF convention Imcodec's Dart JPEG decoder uses: orientations
/// five to eight swap the axes.
({Uint8List bytes, int width, int height}) orientPixels(Uint8List bytes, int width, int height, int orientation) {
  if (orientation == 1 || width == 0 || height == 0) {
    return (bytes: bytes, width: width, height: height);
  }
  final int bytesPerPixel = bytes.length ~/ (width * height);
  final bool swapped = orientation >= 5;
  final int outputWidth = swapped ? height : width;
  final int outputHeight = swapped ? width : height;
  final Uint8List output = Uint8List(bytes.length);
  // Whole words per pixel move one element at a time instead of byte by byte.
  final List<int> source;
  final List<int> destination;
  final int unitsPerPixel;
  if (bytesPerPixel % 4 == 0 && bytes.offsetInBytes % 4 == 0) {
    source = Uint32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4);
    destination = Uint32List.view(output.buffer);
    unitsPerPixel = bytesPerPixel ~/ 4;
  } else if (bytesPerPixel.isEven && bytes.offsetInBytes.isEven) {
    source = Uint16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2);
    destination = Uint16List.view(output.buffer);
    unitsPerPixel = bytesPerPixel ~/ 2;
  } else {
    source = bytes;
    destination = output;
    unitsPerPixel = bytesPerPixel;
  }
  int sourceIndex = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final (int targetX, int targetY) = switch (orientation) {
        2 => (width - 1 - x, y),
        3 => (width - 1 - x, height - 1 - y),
        4 => (x, height - 1 - y),
        5 => (y, x),
        6 => (height - 1 - y, x),
        7 => (height - 1 - y, width - 1 - x),
        _ => (y, width - 1 - x),
      };
      final int targetIndex = (targetY * outputWidth + targetX) * unitsPerPixel;
      for (int unit = 0; unit < unitsPerPixel; unit++) {
        destination[targetIndex + unit] = source[sourceIndex + unit];
      }
      sourceIndex += unitsPerPixel;
    }
  }
  return (bytes: output, width: outputWidth, height: outputHeight);
}

/// Rejects a density that no container can record.
void _checkDensity(double pixelsPerInch) {
  if (!pixelsPerInch.isFinite || pixelsPerInch <= 0) {
    throw ArgumentError.value(pixelsPerInch, 'pixelsPerInch', 'Pixel density must be finite and positive');
  }
}

/// Returns [png] with a `pHYs` chunk recording [pixelsPerInch].
///
/// The chunk follows `IHDR`, as the specification requires it to precede the
/// image data, and replaces any existing one.
Uint8List pngWithPixelDensity(Uint8List png, double pixelsPerInch) {
  _checkDensity(pixelsPerInch);
  final int pixelsPerMetre = (pixelsPerInch * _inchesPerMetre).round();
  if (pixelsPerMetre < 1 || pixelsPerMetre > 0x7FFFFFFF) {
    throw ArgumentError.value(pixelsPerInch, 'pixelsPerInch', 'PNG density must fit in 31 bits per metre');
  }
  const int headerEnd = 8 + 12 + 13;
  if (png.length < headerEnd || !_matches(png, 12, const [0x49, 0x48, 0x44, 0x52])) {
    throw const ImageCodecException('Expected a PNG image header');
  }
  final Uint8List chunk = Uint8List(21);
  final ByteData data = ByteData.sublistView(chunk)
    ..setUint32(0, 9)
    ..setUint32(4, 0x70485973)
    ..setUint32(8, pixelsPerMetre)
    ..setUint32(12, pixelsPerMetre);
  chunk[16] = 1;
  data.setUint32(17, _crc32(Uint8List.sublistView(chunk, 4, 17)));
  final BytesBuilder output = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(png, 0, headerEnd))
    ..add(chunk);
  int offset = headerEnd;
  while (offset + 12 <= png.length) {
    final int length = ByteData.sublistView(png).getUint32(offset);
    final int end = offset + 12 + length;
    if (end > png.length) {
      throw const ImageCodecException('Truncated PNG chunk');
    }
    if (!_matches(png, offset + 4, const [0x70, 0x48, 0x59, 0x73])) {
      output.add(Uint8List.sublistView(png, offset, end));
    }
    offset = end;
  }
  return output.takeBytes();
}

/// Returns [jpeg] with its JFIF header recording [pixelsPerInch].
///
/// libjpeg-turbo writes a JFIF header with an aspect ratio only. Its density
/// fields are rewritten in place; a stream without one gains a header.
Uint8List jpegWithPixelDensity(Uint8List jpeg, double pixelsPerInch) {
  _checkDensity(pixelsPerInch);
  final int density = pixelsPerInch.round();
  if (density < 1 || density > 0xFFFF) {
    throw ArgumentError.value(pixelsPerInch, 'pixelsPerInch', 'JPEG density must round to 1 through 65535');
  }
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw const ImageCodecException('Expected a JPEG start of image');
  }
  final bool jfif = jpeg.length >= 20 && jpeg[2] == 0xFF && jpeg[3] == 0xE0 && _matches(jpeg, 6, const [0x4A, 0x46, 0x49, 0x46, 0]);
  final Uint8List output = jfif
      ? Uint8List.fromList(jpeg)
      : Uint8List.fromList([
          ...Uint8List.sublistView(jpeg, 0, 2),
          0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, //
          ...Uint8List.sublistView(jpeg, 2),
        ]);
  ByteData.sublistView(output)
    ..setUint8(13, 1)
    ..setUint16(14, density)
    ..setUint16(16, density);
  return output;
}

/// Returns [tiff] with resolution tags recording [pixelsPerInch].
///
/// The first directory is copied to the end of the file with XResolution,
/// YResolution and ResolutionUnit set, and the header is pointed at the copy.
/// Every other offset stays valid because no existing byte moves.
Uint8List tiffWithPixelDensity(Uint8List tiff, double pixelsPerInch) {
  _checkDensity(pixelsPerInch);
  const int denominator = 1000;
  final int numerator = (pixelsPerInch * denominator).round();
  if (numerator > 0xFFFFFFFF) {
    throw ArgumentError.value(pixelsPerInch, 'pixelsPerInch', 'TIFF density exceeds a rational');
  }
  if (tiff.length < 8) {
    throw const ImageCodecException('Expected a TIFF header');
  }
  final Endian endian = switch ((tiff[0], tiff[1])) {
    (0x49, 0x49) => Endian.little,
    (0x4D, 0x4D) => Endian.big,
    _ => throw const ImageCodecException('Expected a classic TIFF header'),
  };
  final ByteData source = ByteData.sublistView(tiff);
  if (source.getUint16(2, endian) != 42) {
    throw const ImageCodecException('Expected a classic TIFF header');
  }
  final int directory = source.getUint32(4, endian);
  if (directory + 2 > tiff.length) {
    throw const ImageCodecException('Truncated TIFF directory');
  }
  final int count = source.getUint16(directory, endian);
  if (directory + 2 + count * 12 + 4 > tiff.length) {
    throw const ImageCodecException('Truncated TIFF directory');
  }
  const Set<int> replaced = {282, 283, 296};
  final Map<int, Uint8List> entries = {
    for (int index = 0; index < count; index++)
      if (!replaced.contains(source.getUint16(directory + 2 + index * 12, endian)))
        source.getUint16(directory + 2 + index * 12, endian): Uint8List.sublistView(tiff, directory + 2 + index * 12, directory + 14 + index * 12),
  };
  final int nextDirectory = source.getUint32(directory + 2 + count * 12, endian);
  // Word-aligned, as TIFF requires of directories and of the values they point to.
  final int newDirectory = tiff.length + tiff.length % 2;
  final int directorySize = 2 + (entries.length + 3) * 12 + 4;
  final int rationals = newDirectory + directorySize;
  Uint8List entry(int tag, int type, int value) {
    final Uint8List bytes = Uint8List(12);
    ByteData.sublistView(bytes)
      ..setUint16(0, tag, endian)
      ..setUint16(2, type, endian)
      ..setUint32(4, 1, endian);
    if (type == 3) {
      ByteData.sublistView(bytes).setUint16(8, value, endian);
    } else {
      ByteData.sublistView(bytes).setUint32(8, value, endian);
    }
    return bytes;
  }

  entries[282] = entry(282, 5, rationals);
  entries[283] = entry(283, 5, rationals + 8);
  entries[296] = entry(296, 3, 2);
  final Uint8List output = Uint8List(rationals + 16)..setRange(0, tiff.length, tiff);
  final ByteData data = ByteData.sublistView(output)
    ..setUint32(4, newDirectory, endian)
    ..setUint16(newDirectory, entries.length, endian);
  final List<int> tags = entries.keys.toList()..sort();
  for (int index = 0; index < tags.length; index++) {
    output.setRange(newDirectory + 2 + index * 12, newDirectory + 14 + index * 12, entries[tags[index]]!);
  }
  data.setUint32(newDirectory + 2 + tags.length * 12, nextDirectory, endian);
  for (int index = 0; index < 2; index++) {
    data
      ..setUint32(rationals + index * 8, numerator, endian)
      ..setUint32(rationals + index * 8 + 4, denominator, endian);
  }
  return output;
}

/// Lazily built table for the PNG chunk checksum.
final Uint32List _crcTable = Uint32List.fromList([
  for (int value = 0; value < 256; value++)
    () {
      int crc = value;
      for (int bit = 0; bit < 8; bit++) {
        crc = crc & 1 != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
      }
      return crc;
    }(),
]);

/// CRC-32 of [bytes], as PNG chunks carry it.
int _crc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
