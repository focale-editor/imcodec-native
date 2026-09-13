<p align="center">
  <img src="screenshots/overview.png" alt="ImcodecNative package illustration" width="180">
</p>

# ImcodecNative

Optional AVIF and HEIF/HEIC codecs, plus libjxl and libwebp codec replacements, for
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
await img.ImcodecNative.initialize(jpegXl: false, webP: false);
```

These flags select registrations, not compiled components. Calls are additive.
`ImcodecNative.unregister()` removes this package's current registrations and
restores the original generic JPEG XL/WebP codecs. Registration replaces a
complete generic codec entry, so registering JPEG XL or WebP replaces both its
Dart encoder and decoder. Direct instances such as `const JpegXlCodec()` and
`WebPCodec()` retain their Dart implementation. Dedicated `AvifCodec`,
`HeifCodec`, `NativeJpegXlCodec` and `NativeWebPCodec` work without global
registration.

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

Encoding follows Imcodec's `encodeWith` convention. The AVIF, HEIF, JPEG XL and
WebP `*With` helpers accept a `ParallelRunner` and submit one complete native
operation to it without requiring codec registration in its worker isolate.
Output matches synchronous encoding byte for byte. `onBoundedIsolates` moves
the operation off the calling isolate on native platforms; `runSequentially`
keeps it inline, including in browsers.

Native calls sharing an engine are serialized to protect its global tables;
HEIF/AVIF, JPEG XL and WebP use separate locks. Browser Worker decode requests
are serialized inside the background Worker.

## Format behavior

| Format    | Decoding                                                                                              | Encoding                                                        |
|-----------|-------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| AVIF      | libheif + libaom; primary still image, alpha, 8/10/12-bit samples                                     | libaom; lossy 4:2:0 or lossless RGB 4:4:4; lossless alpha       |
| HEIF/HEIC | libheif + libde265; primary HEVC still image, alpha, high depth                                       | Kvazaar; lossy 8-bit 4:2:0 colour, lossless alpha               |
| JPEG XL   | libjxl; first visible frame, orientation, straight alpha, uint8/uint16/float32 samples and output ICC | libjxl; lossless RGBA, including RGB beneath transparent pixels |
| WebP      | libwebp; still image or first composited animation frame, straight RGBA8                              | libwebp; lossless or lossy RGB, lossless alpha                  |

HEIF is a container: HEVC and AV1 payloads are bundled, not arbitrary optional
HEIF compression methods. Sequence-only brands and MP4 videos are not sniffed
as still images. Collections return the primary image; there is no animation,
multi-image, depth-map or gain-map API. Crop, rotation and mirroring are applied
by libheif. HEIC colour remains lossy even at quality 100.

`decodeAvifData`, `decodeHeifData` and registered `decodeImageData` preserve
high-depth input. HEIF-family and integer JPEG XL samples use little-endian,
full-range uint16 RGBA; floating-point JPEG XL uses little-endian float32.
Ten- and twelve-bit integer samples are normalized to 0–65535. Ordinary
`decodeImage` returns RGBA8. Samples retain the decoder output transfer
function; there is no display tone mapping. libjxl supplies the ICC profile
describing its output pixels. NCLX-only HEIF colour descriptions are not
exposed by Imcodec's current metadata model. Encoding accepts RGBA8 only and
does not copy source metadata.

`inspectImage` retains bounded ICC, EXIF and XMP packets. EXIF is the opaque
HEIF metadata payload, including its four-byte TIFF-offset prefix. Decoding
attaches the ICC payload to `DecodedImage`. Pixel, decoded-byte, ICC,
descriptive-metadata and encoded-output limits are checked independently;
codec working memory is additional to the returned pixel buffer. Lower the
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
