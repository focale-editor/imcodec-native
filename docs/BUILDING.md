# Building and validating ImcodecNative

Published Pub packages contain no upstream source archives. The native build
hook downloads all seventeen pinned archives over HTTPS into its shared cache and
verifies their SHA-256 digests before CMake extracts them. A tagged repository
revision additionally retains the exact libheif and libde265 archives required
by their LGPL license; `.pubignore` keeps them out of the Pub package. The tag,
bridge and build scripts are the reconstruction material for the bundled
WebAssembly.

To populate `third_party/sources` before an offline native build, run:

```sh
dart run imcodec_native:prepare_library
```

## Native

Normal application builds and `flutter test` invoke `hook/build.dart`. For a
standalone host build using CMake 3.25+ and a C++20 compiler:

```sh
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --config Release --target imcodec_native --parallel 4
```

The result is in `build/native/out`. Android uses the NDK's
`build/cmake/android.toolchain.cmake`, `ANDROID_ABI`, `ANDROID_PLATFORM`, and
`ANDROID_STL=c++_static`. Apple builds use the SDK and minimum deployment
target selected by Flutter. Windows uses a Visual Studio CMake generator.

Standalone CMake downloads any archive absent from
`IMCODEC_NATIVE_SOURCE_DIRECTORY` and `third_party/sources` using the same URL
and digest. The hook records the native manifest and build files as
dependencies; cached archives are verified again before use. Do not share a
CMake build directory between target platforms or architectures.

## WebAssembly

Install and activate [Emscripten](https://emscripten.org/docs/getting_started/downloads.html)
**4.0.15**, then run from the package root:

```sh
flutter pub get
dart --packages=.dart_tool/package_config.json tool/web_library_builder.dart
```

The explicit `--packages` invocation runs this maintenance tool without first
triggering a host-native build hook. `--emcmake=/absolute/path/to/emcmake` or
`IMCODEC_NATIVE_EMCMAKE` selects another installation. Its sibling `emcc` must
report the pinned version. The script prepares verified sources under
`build/source-cache`, compiles `build/web/out` and copies the `.mjs` and `.wasm`
outputs into `assets/web`, next to the loader and worker. Commit both generated
files when updating an engine or the bridge.

The module is single-threaded, has a growable heap capped at 2 GiB and a 5 MiB
stack. Background work reuses one module Web Worker and does not require shared
Wasm memory. Concurrent requests are correlated and processed serially away
from the UI thread. All exported buffers are copied or transferred before
native allocations are released. The same module supports Flutter's
Dart-to-JavaScript and Dart-to-WebAssembly outputs.

The loader normally starts the external Worker URL directly. In a
cross-origin-isolated document it uses a minimal `blob:` bootstrap so a server
that applies COEP only to HTML cannot prevent the Worker from starting. Such a
deployment must allow `blob:` in its `worker-src` CSP directive.

## Modifying or updating an engine

For development or LGPL relinking, extract the corresponding archive to a
separate directory, make your changes and pass, for example,
`-DFETCHCONTENT_SOURCE_DIR_LIBHEIF=/absolute/path/to/modified/libheif` to CMake.
Use the complete existing build configuration so all required engines remain
enabled. For Web, the equivalent configure command is:

```sh
emcmake cmake -S native -B build/custom-web -DCMAKE_BUILD_TYPE=Release \
  -DFETCHCONTENT_SOURCE_DIR_LIBHEIF=/absolute/path/to/modified/libheif
cmake --build build/custom-web --target imcodec_native --parallel 4
```

Replace both Web outputs together. To replace a native engine in an application,
use a path dependency on your modified ImcodecNative package and change its
native build configuration; the hook then rebuilds and bundles its code asset.

For an upstream version update, change its URL and checksum in
`native/cmake/sources.cmake`, clear only its file from `build/source-cache`, and
configure a fresh build directory. For libheif or libde265, also replace the
exact archive retained under `third_party/sources`; these are the only upstream
archives committed to tagged revisions. Update version reporting, notices,
and tests, then rebuild the Web assets before creating the matching version
tag. Publish that tag as a GitHub Release, without any custom asset if none is
needed, so the dynamic badge and `/releases/latest` source link resolve. GitHub
supplies the source archives generated from the tag.

## Tests

```sh
dart format --output=none --set-exit-if-changed lib hook tool test
dart analyze
flutter test
dart --packages=.dart_tool/package_config.json tool/prepare_web_tests.dart
flutter test --platform chrome
```

The same codec tests exercise actual bundled engines on native and Web:
sniffing, format-owned inspection, optional registration, lossless RGBA, lossy
HEIC alpha, native JPEG XL/WebP decoding, PNG/JPEG/QOI/TIFF/OpenEXR interoperability,
high-depth/float rasters, malformed inputs, output limits,
runner-based encoding and background decoder workers.
Platform build configurations are maintained in `.github/workflows/ci.yml`.

## AVIF encoder context lifetime

The pinned libheif 1.21.2 AOM plugin reuses an encoder for colour and alpha.
CMake applies a checked, idempotent patch that zero-initializes its context and
destroys an existing context before `aom_codec_enc_init` overwrites it. The
plugin destructor still frees the last context. Removing the patch requires
verifying equivalent ownership in the replacement upstream source.

Rebuild both native libraries and bundled WebAssembly after this source change;
an existing `.wasm` binary cannot acquire a source patch at runtime. Repeated
AVIF exports with non-opaque RGBA inputs must accompany round-trip validation.

The same ownership correction closes the preceding Kvazaar encoder and frees
its configuration before HEIC alpha initialization replaces their pointers.
Repeated HEIC exports are therefore included in the memory validation.

## Additional raster fixtures

`tool/raster_fixture_generator.py` creates original synthetic fixtures with
Pillow, NumPy, tifffile and Python's zlib. Install those development-only tools
in a virtual environment and run the script from the repository root, then
format `test/raster_fixtures.dart`. The fixtures are embedded as base64 so the
same interoperability tests run on the VM and in browsers.
`tool/raster_fixture_generator.cpp` additionally creates lossless 4/12/16-bit
JPEG and floating/tiled OpenEXR fixtures through the upstream APIs. Build its
`imcodec_raster_fixture_generator` target with `IMCODEC_BUILD_FIXTURES=ON`;
pass an output directory and base64-encode those files into
`test/advanced_raster_fixtures.dart`. Tests also cross
native encoders and decoders with direct Imcodec Dart codec instances.
`tool/dart_raster_fixture_generator.dart` freezes reference files produced on
the Dart VM for browsers: Imcodec 0.4.2's Dart OpenEXR path uses unsupported
JavaScript uint64 accessors, and its Dart JPEG path differs in JavaScript.
Native/WebAssembly codecs are exercised on both platforms, with independent
reference files in the browser and live cross-encoding on the VM.

The PNG, JPEG and TIFF engines share the pinned zlib/libjpeg archives. The
libjpeg-turbo build runs through CMake ExternalProject because upstream does
not support `add_subdirectory`; no platform JPEG library is linked. OpenEXR
uses the pinned Imath and libdeflate targets, its vendored OpenJPH sources,
and no internal worker threads.
