import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/codecs/avif.dart';
import 'package:imcodec_native/src/codecs/heif.dart';
import 'package:imcodec_native/src/codecs/jpeg.dart';
import 'package:imcodec_native/src/codecs/jpeg_xl.dart';
import 'package:imcodec_native/src/codecs/open_exr.dart';
import 'package:imcodec_native/src/codecs/png.dart';
import 'package:imcodec_native/src/codecs/qoi.dart';
import 'package:imcodec_native/src/codecs/tiff.dart';
import 'package:imcodec_native/src/codecs/webp.dart';
import 'package:imcodec_native/src/native_image_format.dart';

/// Installs optional codecs into Imcodec after preparing the platform backend.
abstract final class ImcodecNative {
  /// Canonical registrations owned by this package.
  static const List<ImageCodecExtension> _extensions = [
    _AvifExtension(),
    _HeifExtension(),
    _JpegXlExtension(),
    _WebPExtension(),
    _PngExtension(),
    _JpegExtension(),
    _QoiExtension(),
    _TiffExtension(),
    _OpenExrExtension(),
  ];

  /// Initializes the backend and registers the selected codecs in this isolate.
  ///
  /// AVIF and HEIF add formats; the other registrations replace Imcodec's Dart
  /// codecs. Every registration provides native decoding and encoding.
  /// Direct codec instances remain unchanged. On the Web, await this before
  /// using synchronous converters.
  /// [assetBaseUrl] overrides Flutter's default package asset URL in browsers.
  /// Repeated calls are additive; [unregister] removes this package's entries.
  static Future<void> initialize({
    bool avif = true,
    bool heif = true,
    bool jpegXl = true,
    bool webP = true,
    bool png = true,
    bool jpeg = true,
    bool qoi = true,
    bool tiff = true,
    bool openExr = true,
    String? assetBaseUrl,
  }) async {
    await backend.initializeBackend(assetBaseUrl: assetBaseUrl);
    register(
      avif: avif,
      heif: heif,
      jpegXl: jpegXl,
      webP: webP,
      png: png,
      jpeg: jpeg,
      qoi: qoi,
      tiff: tiff,
      openExr: openExr,
    );
  }

  /// Registers selected formats without loading a backend.
  ///
  /// This is sufficient on native platforms and for format sniffing everywhere.
  /// All browser codec operations still require [initialize]. Call this again
  /// inside an application-created native isolate when using generic helpers.
  static void register({
    bool avif = true,
    bool heif = true,
    bool jpegXl = true,
    bool webP = true,
    bool png = true,
    bool jpeg = true,
    bool qoi = true,
    bool tiff = true,
    bool openExr = true,
  }) {
    final List<bool> enabled = [avif, heif, jpegXl, webP, png, jpeg, qoi, tiff, openExr];
    for (int index = 0; index < _extensions.length; index++) {
      if (!enabled[index]) {
        continue;
      }
      final ImageCodecExtension extension = _extensions[index];
      if (extension.format is NativeImageFormat) {
        ImageFormatRegistry.register(extension.format);
      }
      ImageCodecRegistry.register(extension);
    }
  }

  /// Removes only this package's current registrations, restoring Dart codecs.
  static void unregister() {
    for (final ImageCodecExtension extension in _extensions) {
      if (!identical(ImageCodecRegistry.lookup(extension.format), extension)) {
        continue;
      }
      ImageCodecRegistry.unregister(extension.format);
      if (extension.format is NativeImageFormat) {
        ImageFormatRegistry.unregister(extension.format);
      }
    }
  }

  /// Versions read from the actually loaded native or WebAssembly bridge.
  static String get backendVersion => backend.backendVersion;
}

/// Adds AVIF to Imcodec's generic helpers.
final class _AvifExtension extends ImageCodecExtension<AvifEncodeOptions, AvifDecodeOptions> with ParallelImageCodecExtension<AvifEncodeOptions, AvifDecodeOptions> {
  /// Creates the canonical AVIF registration.
  const _AvifExtension();

  @override
  NativeImageFormat get format => NativeImageFormat.avif;

  @override
  Image decode(
    Uint8List bytes, {
    AvifDecodeOptions? decodeOptions,
  }) => const AvifDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    AvifDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const AvifDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    AvifEncodeOptions? encodeOptions,
  }) => const AvifEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    AvifEncodeOptions? encodeOptions,
  }) => const AvifEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Adds HEIF/HEIC to Imcodec's generic helpers.
final class _HeifExtension extends ImageCodecExtension<HeifEncodeOptions, HeifDecodeOptions> with ParallelImageCodecExtension<HeifEncodeOptions, HeifDecodeOptions> {
  /// Creates the canonical HEIF registration.
  const _HeifExtension();

  @override
  NativeImageFormat get format => NativeImageFormat.heif;

  @override
  Image decode(
    Uint8List bytes, {
    HeifDecodeOptions? decodeOptions,
  }) => const HeifDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    HeifDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const HeifDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    HeifEncodeOptions? encodeOptions,
  }) => const HeifEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    HeifEncodeOptions? encodeOptions,
  }) => const HeifEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the JPEG XL codec behind generic Imcodec helpers.
final class _JpegXlExtension extends ImageCodecExtension<JpegXlEncodeOptions, JpegXlDecodeOptions> with ParallelImageCodecExtension<JpegXlEncodeOptions, JpegXlDecodeOptions> {
  /// Creates the lossless native JPEG XL registration.
  const _JpegXlExtension();

  @override
  ImageFormat get format => ImageFormat.jpegXl;

  @override
  Image decode(
    Uint8List bytes, {
    JpegXlDecodeOptions? decodeOptions,
  }) => const NativeJpegXlDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    JpegXlDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeJpegXlDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativeJpegXlDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    JpegXlEncodeOptions? encodeOptions,
  }) => const NativeJpegXlEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    JpegXlEncodeOptions? encodeOptions,
  }) => const NativeJpegXlEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the WebP codec behind generic Imcodec helpers.
final class _WebPExtension extends ImageCodecExtension<WebPEncodeOptions, WebPDecodeOptions> with ParallelImageCodecExtension<WebPEncodeOptions, WebPDecodeOptions> {
  /// Creates the native WebP registration.
  const _WebPExtension();

  @override
  ImageFormat get format => ImageFormat.webp;

  @override
  Image decode(
    Uint8List bytes, {
    WebPDecodeOptions? decodeOptions,
  }) => const NativeWebPDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    WebPDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeWebPDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    WebPEncodeOptions? encodeOptions,
  }) => const NativeWebPEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    WebPEncodeOptions? encodeOptions,
  }) => const NativeWebPEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the PNG codec behind generic Imcodec helpers.
final class _PngExtension extends ImageCodecExtension<PngEncodeOptions, PngDecodeOptions> with ParallelImageCodecExtension<PngEncodeOptions, PngDecodeOptions> {
  /// Creates the native PNG registration.
  const _PngExtension();

  @override
  ImageFormat get format => ImageFormat.png;

  @override
  Image decode(
    Uint8List bytes, {
    PngDecodeOptions? decodeOptions,
  }) => const NativePngDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    PngDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativePngDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativePngDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    PngEncodeOptions? encodeOptions,
  }) => const NativePngEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    PngEncodeOptions? encodeOptions,
  }) => const NativePngEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the JPEG codec behind generic Imcodec helpers.
final class _JpegExtension extends ImageCodecExtension<JpegEncodeOptions, JpegDecodeOptions> with ParallelImageCodecExtension<JpegEncodeOptions, JpegDecodeOptions> {
  /// Creates the native JPEG registration.
  const _JpegExtension();

  @override
  ImageFormat get format => ImageFormat.jpeg;

  @override
  Image decode(
    Uint8List bytes, {
    JpegDecodeOptions? decodeOptions,
  }) => const NativeJpegDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    JpegDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeJpegDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativeJpegDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    JpegEncodeOptions? encodeOptions,
  }) => const NativeJpegEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    JpegEncodeOptions? encodeOptions,
  }) => const NativeJpegEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the QOI codec behind generic Imcodec helpers.
final class _QoiExtension extends ImageCodecExtension<QoiEncodeOptions, QoiDecodeOptions> with ParallelImageCodecExtension<QoiEncodeOptions, QoiDecodeOptions> {
  /// Creates the native QOI registration.
  const _QoiExtension();

  @override
  ImageFormat get format => ImageFormat.qoi;

  @override
  Image decode(
    Uint8List bytes, {
    QoiDecodeOptions? decodeOptions,
  }) => const NativeQoiDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    QoiDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeQoiDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativeQoiDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    QoiEncodeOptions? encodeOptions,
  }) => const NativeQoiEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    QoiEncodeOptions? encodeOptions,
  }) => const NativeQoiEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the TIFF codec behind generic Imcodec helpers.
final class _TiffExtension extends ImageCodecExtension<TiffEncodeOptions, TiffDecodeOptions> with ParallelImageCodecExtension<TiffEncodeOptions, TiffDecodeOptions> {
  /// Creates the native TIFF registration.
  const _TiffExtension();

  @override
  ImageFormat get format => ImageFormat.tiff;

  @override
  Image decode(
    Uint8List bytes, {
    TiffDecodeOptions? decodeOptions,
  }) => const NativeTiffDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    TiffDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeTiffDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativeTiffDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    TiffEncodeOptions? encodeOptions,
  }) => const NativeTiffEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    TiffEncodeOptions? encodeOptions,
  }) => const NativeTiffEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}

/// Replaces the OpenEXR codec behind generic Imcodec helpers.
final class _OpenExrExtension extends ImageCodecExtension<OpenExrEncodeOptions, OpenExrDecodeOptions> with ParallelImageCodecExtension<OpenExrEncodeOptions, OpenExrDecodeOptions> {
  /// Creates the native OpenEXR registration.
  const _OpenExrExtension();

  @override
  ImageFormat get format => ImageFormat.openExr;

  @override
  Image decode(
    Uint8List bytes, {
    OpenExrDecodeOptions? decodeOptions,
  }) => const NativeOpenExrDecoder().decode(
    bytes,
    decodeOptions: decodeOptions,
  );

  @override
  DecodedImage decodeData(
    Uint8List bytes, {
    OpenExrDecodeOptions? decodeOptions,
    required int maxDecodedBytes,
    required int maxIccProfileBytes,
  }) => const NativeOpenExrDecoder().decodeData(
    bytes,
    decodeOptions: decodeOptions,
    maxDecodedBytes: maxDecodedBytes,
    maxIccProfileBytes: maxIccProfileBytes,
  );

  @override
  DecodedImageMetadata inspect(
    Uint8List bytes, {
    int maxIccProfileBytes = defaultMaxIccProfileBytes,
    int maxDescriptiveMetadataBytes = defaultMaxDescriptiveMetadataBytes,
  }) => const NativeOpenExrDecoder().inspect(
    bytes,
    maxIccProfileBytes: maxIccProfileBytes,
    maxMetadataBytes: maxDescriptiveMetadataBytes,
  );

  @override
  Uint8List encode(
    Image image, {
    OpenExrEncodeOptions? encodeOptions,
  }) => const NativeOpenExrEncoder().encode(
    image,
    encodeOptions: encodeOptions,
  );

  @override
  Future<Uint8List> encodeWith(
    ParallelRunner runner,
    Image image, {
    OpenExrEncodeOptions? encodeOptions,
  }) => const NativeOpenExrEncoder().encodeWith(
    runner,
    image,
    encodeOptions: encodeOptions,
  );
}
