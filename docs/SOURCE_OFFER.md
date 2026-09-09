# Corresponding source

[![Latest GitHub release](https://img.shields.io/github/v/release/focale-editor/imcodec-native?display_name=tag&sort=semver&label=latest%20release)](https://github.com/focale-editor/imcodec-native/releases/latest)

The WebAssembly module distributed by ImcodecNative contains libheif and
libde265 under the GNU Lesser General Public License version 3 or later. The
latest published source and relinking material is available from:

https://github.com/focale-editor/imcodec-native/releases/latest

For the binaries in a particular package version, use the immutable release
whose tag exactly matches the `version` field in that package's `pubspec.yaml`:

`https://github.com/focale-editor/imcodec-native/releases/tag/{package-version}`

That tag contains the exact original libheif and libde265 archives, the native
bridge, build configuration, build-time patches, license texts, pinned URLs
and SHA-256 digests. `docs/BUILDING.md` documents how to reproduce and replace the
native and WebAssembly libraries. The remaining permissively licensed source
archives are retrieved and verified by `prepare_library` from the locations
recorded in `native/cmake/sources.cmake`.

Distributors incorporating ImcodecNative binaries into another product must
preserve the applicable notices and provide corresponding source and relinking
access as required by the licenses. This engineering notice is not legal
advice.
