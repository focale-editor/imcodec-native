# Third-party notices

ImcodecNative's own Dart code, C ABI bridge and build scripts are covered by
the root MIT [LICENSE](../LICENSE). This does not relicense any bundled library.

| Component     | Version                                  | License                             | Role                                     |
|---------------|------------------------------------------|-------------------------------------|------------------------------------------|
| libheif       | 1.21.2                                   | LGPL-3.0-or-later                   | HEIF/AVIF container and pixel conversion |
| libde265      | 1.1.2                                    | LGPL-3.0-or-later                   | HEVC decoding                            |
| Kvazaar       | 2.3.2                                    | BSD-3-Clause                        | HEVC encoding                            |
| libaom        | 3.14.1                                   | BSD-2-Clause and AOM patent license | AV1 encoding/decoding                    |
| libjxl        | 0.12.0                                   | BSD-3-Clause and patent license     | JPEG XL encoding and decoding            |
| libwebp       | 1.6.0                                    | BSD-3-Clause and patent license     | WebP encoding and decoding               |
| Brotli        | 028fb5a23661f123017c060daa546b55cf4bde29 | MIT                                 | JPEG XL compression                      |
| Highway       | 457c891775a7397bdb0376bb1031e6e027af1c48 | Apache-2.0 or BSD-3-Clause          | JPEG XL SIMD                             |
| skcms         | 96d9171c94b937a1b5f0293de7309ac16311b722 | BSD-3-Clause                        | JPEG XL colour support                   |
| libpng        | 1.6.58                                   | PNG Reference Library License v2    | PNG encoding and decoding                |
| libjpeg-turbo | 3.2.0                                    | IJG, BSD-3-Clause and zlib          | JPEG encoding and decoding               |
| QOI           | 97bacc86a9c4abf5a2d452102dc26546c4c670b9 | MIT                                 | QOI encoding and decoding                |
| libtiff       | 4.7.2                                    | libtiff license                     | TIFF encoding and decoding               |
| OpenEXR       | 3.4.14                                   | BSD-3-Clause                        | OpenEXR encoding and decoding            |
| Imath         | 3.2.3                                    | BSD-3-Clause                        | OpenEXR math and half-float support      |
| libdeflate    | 1.26                                     | MIT                                 | OpenEXR compression                      |
| zlib          | 1.3.2                                    | zlib                                | PNG and TIFF compression                 |
| OpenJPH       | 0.31.0 (vendored by OpenEXR)             | BSD-2-Clause                        | OpenEXR HTJ2K compression                |

Original notices and patent grants are in [third_party/licenses](../third_party/licenses).
The libheif notice also contains the GNU GPL v3 text incorporated by LGPL v3.
Tagged repository revisions retain the exact original libheif and libde265
archives under `third_party/sources`. Pub packages intentionally omit all
upstream archives. The build hook retrieves them over HTTPS into its shared
cache and verifies the URLs and SHA-256 digests recorded in
[native/cmake/sources.cmake](../native/cmake/sources.cmake). The optional
`prepare_library` command performs the same verified download for offline
builds.

The distributed WebAssembly is linked from the tagged sources and accompanying
MIT bridge. [BUILDING.md](BUILDING.md) supplies the scripts and toolchain
version necessary to rebuild and relink it. The native dynamic library is
built from the same pinned inputs by the Dart build hook. Applications can
rebuild with modified libraries through CMake's
`FETCHCONTENT_SOURCE_DIR_<NAME>` overrides and replace the corresponding
dynamic library or Web assets. [SOURCE_OFFER.md](SOURCE_OFFER.md) identifies
the immutable source revision for this package version. Distributors must keep
equivalent corresponding-source access when redistributing the binaries.

Our build applies these changes to the extracted sources, leaving the original
archives intact:

* Rename libde265's and Kvazaar's `dist` build targets so all libraries can
  coexist in a single CMake project.
* In libheif's Kvazaar plugin, select lossless compression for the auxiliary
  alpha image even when colour is lossy. The exact replacement is validated
  against the pinned source by `native/CMakeLists.txt`.
* Compile libjpeg-turbo in its supported standalone CMake project and forward
  the platform toolchain; share the pinned static JPEG and zlib targets with TIFF.
* Enable glibc endian helpers for OpenEXRCore on Linux and explicitly include
  `strings.h` and POSIX declarations for its DWA classifier on Emscripten.
* Allow integer vector conversions in libdeflate with Android NDK Clang before
  version 20, matching the polynomial vector intrinsics in those NDK headers.
* Configure static engines, disable unused tools/plugins and internal codec
  threading, and apply the platform compiler definitions in that same file.

No x265, FFmpeg or other GPL-only codec engine is linked. LGPL obligations
still apply to libheif and libde265. This notice is not a patent clearance or
a substitute for reviewing the licenses applicable to an application.
