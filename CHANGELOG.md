# 📰 ImcodecNative changelog

## v0.2.5
Released on October 5, 2026.

* **DOCS**: Updated the plugin logo. ([#3a887fe](https://github.com/focale-editor/imcodec-native/commit/3a887fe))
* **FIX**: Fixed Windows CMake discovery. ([#b243dc3](https://github.com/focale-editor/imcodec-native/commit/b243dc3))
* **FIX**: Fixed macOS ARM build flags and sysroot. ([#872a0c7](https://github.com/focale-editor/imcodec-native/commit/872a0c7))
* **FIX**: Various native builder fixes. ([#171ce8a](https://github.com/focale-editor/imcodec-native/commit/171ce8a))
* **CHORE**: Shorten Windows native build paths. ([#f3b144f](https://github.com/focale-editor/imcodec-native/commit/f3b144f))

## v0.2.4
Released on October 1, 2026.

* **CHORE**: Updated `imcodec`. ([#fc83676](https://github.com/focale-editor/imcodec-native/commit/fc83676))

## v0.2.3
Released on October 1, 2026.

* **CHORE**: Updated `imcodec`. ([#4ea4d45](https://github.com/focale-editor/imcodec-native/commit/4ea4d45))

## v0.2.2
Released on September 24, 2026.

* **FEAT**: Now handling EXIF orientation in native JPEG decoding and record pixel density in PNG, JPEG, and TIFF encoders. ([#185f05c](https://github.com/focale-editor/imcodec-native/commit/185f05c))

## v0.2.1
Released on September 24, 2026.

* **FIX**: Now preserving CMYK channels, alpha, depth and colour model when decoding TIFF images. ([#1677a2c](https://github.com/focale-editor/imcodec-native/commit/1677a2c))

## v0.2.0
Released on September 24, 2026.

* **FEAT**: Added new native codecs for WebP, PNG, JPEG, QOI, TIFF and OpenEXR. ([#197cee2](https://github.com/focale-editor/imcodec-native/commit/197cee2))
* **BREAKING CHORE**: Updated `imcodec`. ([#06f317c](https://github.com/focale-editor/imcodec-native/commit/06f317c))

## v0.1.4
Released on September 13, 2026.

* **DOCS**: Added contributing guide, package screenshot, and pubspec metadata. ([#eb4b102](https://github.com/focale-editor/imcodec-native/commit/eb4b102))

## v0.1.3
Released on September 12, 2026.

* **FIX**: Release the previous libaom and Kvazaar contexts before encoding another AVIF or HEIF colour or alpha plane. ([#5e1146e](https://github.com/focale-editor/imcodec-native/commit/5e1146e))

## v0.1.2
Released on September 11, 2026.

* **FIX**: Forced `libheif` to resolve the bundled AOM target. ([#ce03514](https://github.com/focale-editor/imcodec-native/commit/ce03514))

## v0.1.1
Released on September 10, 2026.

* **FIX**: Invalidated stale CMake caches when switching between path and hosted dependencies. ([#8dcb81a](https://github.com/focale-editor/imcodec-native/commit/8dcb81a))

## v0.1.0
Released on September 10, 2026.

* **Initial release**.
