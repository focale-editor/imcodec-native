import 'dart:typed_data';

import 'package:imcodec/imcodec.dart';
import 'package:imcodec_native/src/backend/backend.dart' as backend;
import 'package:imcodec_native/src/backend/native_request.dart';
import 'package:imcodec_native/src/codecs/native_raster_encoder.dart';
import 'package:imcodec_native/src/native_image_format.dart';

part 'heif/codec.dart';
part 'heif/decoder.dart';
part 'heif/encoder.dart';

/// Conventional HEIC spelling of [HeifCodec].
typedef HeicCodec = HeifCodec;

/// Conventional HEIC spelling of [HeifDecoder].
typedef HeicDecoder = HeifDecoder;

/// Conventional HEIC spelling of [HeifDecodeOptions].
typedef HeicDecodeOptions = HeifDecodeOptions;

/// Conventional HEIC spelling of [HeifEncoder].
typedef HeicEncoder = HeifEncoder;

/// Conventional HEIC spelling of [HeifEncodeOptions].
typedef HeicEncodeOptions = HeifEncodeOptions;
