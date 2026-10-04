# ImcodecNative example

A synthetic RGBA image is encoded through Imcodec's runner API, then
decoded and displayed. The nine buttons exercise AVIF, HEIC, JPEG XL, WebP,
PNG, JPEG, QOI, TIFF and OpenEXR.

Run `flutter create --platforms android,ios,macos,windows,linux,web .` to add any
missing platform launchers, then `flutter run`. The package build hook bundles
the native engines automatically; Web assets are already included.

For this multi-package checkout, the ignored `pubspec_overrides.yaml` points
to `../../Imcodec`. Published examples resolve Imcodec 0.5.x from pub.dev.
