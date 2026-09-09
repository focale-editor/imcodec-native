/// Optional bundled native and WebAssembly codecs for Imcodec.
library;

export 'package:imcodec/imcodec.dart';

export 'src/backend/native_request.dart' show defaultMaxEncodedBytes;
export 'src/codecs/avif.dart' show AvifCodec, AvifDecodeOptions, AvifDecoder, AvifEncodeOptions, AvifEncoder;
export 'src/codecs/heif.dart' show HeicCodec, HeicDecodeOptions, HeicDecoder, HeicEncodeOptions, HeicEncoder, HeifCodec, HeifDecodeOptions, HeifDecoder, HeifEncodeOptions, HeifEncoder;
export 'src/codecs/jpeg_xl.dart' show NativeJpegXlCodec, NativeJpegXlDecoder, NativeJpegXlEncoder;
export 'src/codecs/webp.dart' show NativeWebPCodec, NativeWebPDecoder, NativeWebPEncoder;
export 'src/decoder.dart';
export 'src/encoder.dart';
export 'src/imcodec_native.dart';
export 'src/native_image_format.dart';
