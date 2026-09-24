/// Optional bundled native and WebAssembly codecs for Imcodec.
library;

export 'package:imcodec/imcodec.dart';

export 'src/backend/native_request.dart' show defaultMaxEncodedBytes;
export 'src/codecs/avif.dart' show AvifCodec, AvifDecodeOptions, AvifDecoder, AvifEncodeOptions, AvifEncoder;
export 'src/codecs/heif.dart' show HeicCodec, HeicDecodeOptions, HeicDecoder, HeicEncodeOptions, HeicEncoder, HeifCodec, HeifDecodeOptions, HeifDecoder, HeifEncodeOptions, HeifEncoder;
export 'src/codecs/jpeg.dart' show NativeJpegCodec, NativeJpegDecoder, NativeJpegEncoder;
export 'src/codecs/jpeg_xl.dart' show NativeJpegXlCodec, NativeJpegXlDecoder, NativeJpegXlEncoder;
export 'src/codecs/open_exr.dart' show NativeOpenExrCodec, NativeOpenExrDecoder, NativeOpenExrEncoder;
export 'src/codecs/png.dart' show NativePngCodec, NativePngDecoder, NativePngEncoder;
export 'src/codecs/qoi.dart' show NativeQoiCodec, NativeQoiDecoder, NativeQoiEncoder;
export 'src/codecs/tiff.dart' show NativeTiffCodec, NativeTiffDecoder, NativeTiffEncoder;
export 'src/codecs/webp.dart' show NativeWebPCodec, NativeWebPDecoder, NativeWebPEncoder;
export 'src/decoder.dart';
export 'src/encoder.dart';
export 'src/imcodec_native.dart';
export 'src/native_image_format.dart';
