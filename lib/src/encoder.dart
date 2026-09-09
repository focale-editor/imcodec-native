import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/codecs/avif.dart';
import 'package:imcodec_native/src/codecs/heif.dart';

/// Encodes straight RGBA8 as AVIF with lossless alpha.
Uint8List encodeAvif(
  Image image, {
  AvifEncodeOptions? options,
}) => const AvifEncoder().encode(
  image,
  encodeOptions: options,
);

/// Encodes straight RGBA8 as HEIC with lossless alpha.
Uint8List encodeHeif(
  Image image, {
  HeifEncodeOptions? options,
}) => const HeifEncoder().encode(
  image,
  encodeOptions: options,
);

/// Encodes straight RGBA8 as HEIC with lossless alpha.
Uint8List encodeHeic(
  Image image, {
  HeifEncodeOptions? options,
}) => encodeHeif(
  image,
  options: options,
);

/// Encodes AVIF through [runner].
Future<Uint8List> encodeAvifWith(
  ParallelRunner runner,
  Image image, {
  AvifEncodeOptions? options,
}) => const AvifEncoder().encodeWith(
  runner,
  image,
  encodeOptions: options,
);

/// Encodes HEIF/HEIC through [runner].
Future<Uint8List> encodeHeifWith(
  ParallelRunner runner,
  Image image, {
  HeifEncodeOptions? options,
}) => const HeifEncoder().encodeWith(
  runner,
  image,
  encodeOptions: options,
);

/// Encodes HEIC through [runner].
Future<Uint8List> encodeHeicWith(
  ParallelRunner runner,
  Image image, {
  HeifEncodeOptions? options,
}) => encodeHeifWith(
  runner,
  image,
  options: options,
);
