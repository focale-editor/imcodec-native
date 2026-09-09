import 'dart:io';

/// Copies shipped assets into the static directory served by Flutter Web tests.
///
/// Flutter's test server serves `test/`, not an application's asset bundle.
/// Generated copies are ignored by Git and excluded from package publication.
void main() {
  final Directory root = File.fromUri(Platform.script).parent.parent;
  for (final String path in ['test/web_assets', 'example/test/web_assets']) {
    final Directory destination = Directory('${root.path}/$path')..createSync(recursive: true);
    for (final String name in ['imcodec_native.mjs', 'imcodec_native.wasm', 'imcodec_native_loader.js', 'imcodec_native_worker.js']) {
      File('${root.path}/assets/web/$name').copySync('${destination.path}/$name');
    }
  }
}
