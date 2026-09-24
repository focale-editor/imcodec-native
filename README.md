<p align="center">
  <img src="screenshots/overview.png" alt="ImcodecNative package illustration" width="180">
</p>

# ImcodecNative

Optional AVIF and HEIF/HEIC codecs, plus native PNG, JPEG, JPEG XL, WebP, QOI,
TIFF and OpenEXR codec replacements, for
[Imcodec](https://github.com/focale-editor/imcodec). Imcodec itself remains
pure Dart and never depends on this package.

The same engines run on Android, iOS, macOS, Windows and Linux through Dart
code assets, and in browsers through a bundled WebAssembly module. There are
no platform codec dependencies, platform channels, runtime CDN downloads or
browser-specific image decoders.

## Usage

Add `imcodec_native` to your application's dependencies, then initialize it
once before using the generic Imcodec helpers:

```dart
import 'package:imcodec_native/imcodec_native.dart' as img;

await img.ImcodecNative.initialize();

final img.ImageFormat? format = img.ImageFormat.sniff(encodedBytes);
final img.Image image = img.decodeImage(encodedBytes);
final avif = img.encodeImage(image, format: img.NativeImageFormat.avif);
final heic = img.encodeHeif(
  image,
  options: const img.HeifEncodeOptions(quality: 85),
);
final jxl = img.encodeJpegXl(image); // libjxl, lossless
final webp = img.encodeWebP(image); // libwebp, lossless
final png = img.encodePng(image); // libpng
final jpeg = img.encodeJpeg(image); // libjpeg-turbo
final qoi = img.encodeQoi(image); // reference QOI library
final tiff = img.encodeTiff(image); // libtiff
final exr = img.encodeOpenExr(image); // OpenEXR
final lossyWebP = img.encodeWebP(
  image,
  options: const img.WebPEncodeOptions(quality: 82),
);
```

The package re-exports Imcodec. `NativeImageFormat` extends `ImageFormat` and
implements `InspectableFormat`; neither AVIF nor HEIF is declared in Imcodec.
Their signatures and metadata inspectors are registered through
`ImageFormatRegistry`, while their codec implementations are registered
separately through `ImageCodecRegistry`. Adding an import alone has no side
effects. `ImageFormatRegistry.formats` is the complete ordered collection of
currently supported core and add-on formats.

Select only the registrations you want:

```dart
await img.ImcodecNative.initialize(
  jpegXl: false,
  webP: false,
  png: true,
  jpeg: true,
  qoi: false,
  tiff: true,
  openExr: false,
);
```

These flags select registrations, not compiled components. Calls are additive.
`ImcodecNative.unregister()` removes this package's current registrations and
restores the original generic Dart codecs. Registration replaces both the
encoder and decoder of each selected format. Direct instances such as `const JpegXlCodec()` and
`WebPCodec()` retain their Dart implementation. Dedicated `AvifCodec`,
`HeifCodec`, `NativeJpegXlCodec`, `NativeWebPCodec`, `NativePngCodec`,
`NativeJpegCodec`, `NativeQoiCodec`, `NativeTiffCodec` and `NativeOpenExrCodec`
work without global registration.

`NativeImageFormat.heic`, `HeicCodec`, `HeicEncoder`, `HeicDecoder` and the
`encodeHeic`/`decodeHeic` helpers are aliases of their canonical HEIF spelling.

On native platforms, synchronous `ImcodecNative.register()` is sufficient.
Call it inside each application-created isolate that uses generic helpers;
the registry is isolate-local. On browsers, await `initialize()` before any
native converter or helper, including asynchronous decoder APIs.

## Codecs and background work

The codec/encoder/decoder APIs follow Imcodec's `dart:convert` contracts:

```dart
const codec = img.AvifCodec();
final encoded = codec.encoder.convert(
  image,
  encodeOptions: const img.AvifEncodeOptions(quality: 80, speed: 6),
);
final decoded = codec.decoder.convert(encoded);

final lossless = img.encodeAvif(
  image,
  options: const img.AvifEncodeOptions(lossless: true, speed: 9),
);
final background = await img.encodeAvifWith(
  img.onBoundedIsolates,
  image,
  options: const img.AvifEncodeOptions(quality: 80),
);
final pixels = await img.decodeHeifAsync(heicBytes);
final nativeWebP = await img.encodeWebPWith(
  img.onBoundedIsolates,
  image,
);
```

Codec and encoder instances are immutable resources. Compression and allocation
settings live in typed per-operation options, matching Imcodec 0.4's API.

Decoder `*Async` helpers use a native isolate or a module Web Worker. Inputs
are copied before scheduling and returned buffers own their memory. Browsers
reuse one Worker and one Wasm instance, correlate concurrent requests, and
replace the Worker after a transport failure. Codec errors affect only their
own request.

Encoding follows Imcodec's `encodeWith` convention. Every native codec and
encoder accepts a `ParallelRunner` and submits one complete native operation
without requiring codec registration in its worker isolate. For example,
`const NativeTiffEncoder().encodeWith(onBoundedIsolates, image)` encodes TIFF
in the background. The existing generic PNG and JPEG `*With` helpers also
use their registered native implementations.
Output matches synchronous encoding byte for byte. `onBoundedIsolates` moves
the operation off the calling isolate on native platforms; `runSequentially`
keeps it inline, including in browsers.

Native calls sharing an engine are serialized to protect its global tables;
HEIF/AVIF share one lock; the other engines each have their own lock. Browser Worker decode requests
are serialized inside the background Worker.

## Format behavior

| Format    | Decoding                                                                                                             | Encoding                                                                      |
|-----------|----------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| AVIF      | libheif + libaom; primary still image, alpha, 8/10/12-bit samples                                                    | libaom; lossy 4:2:0 or lossless RGB 4:4:4; lossless alpha                     |
| HEIF/HEIC | libheif + libde265; primary HEVC still image, alpha, high depth                                                      | Kvazaar; lossy 8-bit 4:2:0 colour, lossless alpha                             |
| JPEG XL   | libjxl; first visible frame, orientation, straight alpha, uint8/uint16/float32 samples and output ICC                | libjxl; lossless RGBA, including RGB beneath transparent pixels               |
| WebP      | libwebp; still image or first composited animation frame, straight RGBA8                                             | libwebp; lossless or lossy RGB, lossless alpha                                |
| PNG       | libpng; palette/gray/RGB/RGBA, transparency, Adam7 and 8/16-bit samples                                              | libpng; lossless RGBA8, `PngEncodeOptions.level` 0–9                          |
| JPEG      | libjpeg-turbo; baseline/progressive, grayscale/RGB and 8-bit CMYK; low-depth and 12/16-bit lossless samples          | libjpeg-turbo; baseline RGB, quality and 4:4:4/4:2:0 options; alpha discarded |
| QOI       | Reference QOI library; RGB/RGBA with strict stream validation                                                        | Reference QOI library; lossless RGBA8, including hidden RGB                   |
| TIFF      | libtiff; first directory, strips/tiles, separate/interleaved planes, all orientations, RGB/gray uint8/uint16/float32 | libtiff; straight RGBA8 with no compression or PackBits                       |
| OpenEXR   | OpenEXR; single flat scanline/tiled image, RGB/RGBA or luminance, half/float samples                                 | OpenEXR; scene-linear RGBA half-float with none/ZIPS/ZIP compression          |

HEIF is a container: HEVC and AV1 payloads are bundled, not arbitrary optional
HEIF compression methods. Sequence-only brands and MP4 videos are not sniffed
as still images. Collections return the primary image; there is no animation,
multi-image, depth-map or gain-map API. Crop, rotation and mirroring are applied
by libheif. HEIC colour remains lossy even at quality 100.

`decodeAvifData`, `decodeHeifData`, native decoder `decodeData` methods and
registered `decodeImageData` preserve
high-depth input. HEIF-family and integer JPEG XL samples use little-endian,
full-range uint16 RGBA; floating-point JPEG XL uses little-endian float32.
Ten- and twelve-bit integer samples are normalized to 0–65535. Ordinary
`decodeImage` returns RGBA8. Samples retain the decoder output transfer
function; there is no display tone mapping. libjxl supplies the ICC profile
describing its output pixels. NCLX-only HEIF colour descriptions are not
exposed by Imcodec's current metadata model. Encoding accepts RGBA8 only and
does not copy source metadata.

The new codecs reuse Imcodec's `PngEncodeOptions`, `JpegEncodeOptions`,
`QoiEncodeOptions`, `TiffEncodeOptions`, `OpenExrEncodeOptions` and corresponding
decode options. Each native decoder exposes `decodeAsync` and `decodeDataAsync`,
also available as `decodePngAsync`, `decodeJpegAsync`, `decodeQoiAsync`,
`decodeTiffAsync`, `decodeOpenExrAsync` and their `*DataAsync` counterparts.

OpenEXR follows Imcodec's working-colour contract: scene-linear authored
primaries are converted to extended sRGB. `decodeData` retains HDR values in
float32; ordinary decoding clips to RGBA8. Deep images, multipart files and
subsampled colour channels are rejected. TIFF's high-depth path preserves RGB
and grayscale samples; its compatibility path converts palette, CMYK and
YCbCr to RGBA8 and undoes associated alpha. `NativeTiffDecoder` also accepts
BigTIFF directly; Imcodec's generic signature detection currently recognizes
classic TIFF only. JPEG CMYK conversion uses the conventional CMYK-to-RGB
approximation and omits the source CMYK ICC from the converted RGB raster.
TIFF EXIF directories are not serialized into EXIF packets.

`inspectImage` retains bounded ICC, EXIF and XMP packets. EXIF is the opaque
HEIF metadata payload, including its four-byte TIFF-offset prefix. Decoding
attaches the ICC payload to `DecodedImage`. Pixel, decoded-byte, ICC,
descriptive-metadata and encoded-output limits are checked independently;
codec working memory is additional to the returned pixel buffer. QOI's
reference encoder reserves its worst-case output (five bytes per pixel plus
22 bytes); `maxOutputBytes` must accommodate that reservation. TIFF and OpenEXR
also check conversion/block allocations before decoding. Lower the
defaults for untrusted images or constrained devices.

## Platform builds

Dart 3.13 or newer and a matching Flutter SDK are required. Native builds use
the build hook automatically, including when running tests. The first build
downloads the pinned sources over HTTPS, verifies every SHA-256 digest and
compiles them; subsequent builds reuse a shared source cache and a
target-specific compilation cache. No Emscripten installation is needed by
applications.

To prepare a package checkout or Pub installation for an offline native build,
download the same verified archives in advance:

```console
dart run imcodec_native:prepare_library
```

The command stores them beside the installed package. Normal application
builds need no manual command, but their first native build requires network
access if this cache has not already been prepared.

| Platform | Build requirements                                                                 |
|----------|------------------------------------------------------------------------------------|
| Android  | CMake 3.25+, Android NDK selected by Flutter; ARMv7, ARM64, x86 and x64 toolchains |
| iOS      | macOS, Xcode and CMake 3.25+; ARM64 device, ARM64/x64 simulator                    |
| macOS    | Xcode command-line tools and CMake 3.25+; ARM64/x64                                |
| Windows  | Visual Studio C++ toolchain and CMake 3.25+; x64/ARM64                             |
| Linux    | CMake 3.25+, C/C++20 toolchain and Make or Ninja                                   |
| Web      | Bundled `.mjs`, `.wasm`, loader and worker assets; no native compiler              |

Android uses a statically linked C++ runtime and 16 KB-compatible ELF segment
alignment. Release libraries are stripped on Android. Native outputs expose
only the small bridge ABI and bundle all codec engines into one dynamic library.
`IMCODEC_NATIVE_CMAKE` can select the CMake executable. Cross-compiling Linux
requires an appropriate compiler toolchain; a host binary is not a substitute.

Flutter bundles Web assets automatically. For a custom asset server, pass
`assetBaseUrl` to `initialize()`. Keep all four files together, serve `.wasm`
as `application/wasm`, and allow the module/worker URLs in your CSP. WebAssembly
compilation must also be permitted (typically `script-src 'self'
'wasm-unsafe-eval'` and `worker-src 'self'`). The worker script must be
same-origin. No `SharedArrayBuffer`, COOP or COEP headers are needed.
If the host nevertheless enables cross-origin isolation, add `blob:` to
`worker-src`; the loader uses a tiny blob bootstrap so the Worker inherits the
document's COEP policy even when the asset response omits that header.

See [docs/BUILDING.md](docs/BUILDING.md) for rebuilding, testing and replacing the engines.

## Licensing

The Dart integration and bridge are MIT licensed. Codec components have their
own licenses, including LGPL-3.0-or-later for libheif and libde265. Published
Pub packages omit upstream source archives; repository tags retain the exact
LGPL sources and complete reconstruction material. See
[docs/SOURCE_OFFER.md](docs/SOURCE_OFFER.md) and
[docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md). Application distributors
must retain applicable notices and satisfy the relevant source/relinking
requirements. Codec software licenses do not grant all possible HEVC patent
rights; assess your distribution's requirements.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
