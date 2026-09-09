/// Prepares ImcodecNative's pinned sources for offline native builds.
library;

import 'dart:io';
import 'dart:isolate';

import '../tool/source_preparer.dart';

/// Downloads and verifies every native codec source archive.
Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--force')) {
    stderr.writeln('Usage: dart run imcodec_native:prepare_library [--force]');
    exitCode = 64;
    return;
  }
  try {
    final Directory packageRoot = await _packageRoot();
    final Directory destination = Directory(
      '${packageRoot.path}/third_party/sources',
    );
    final List<File> archives = await prepareNativeSources(
      packageRoot: packageRoot,
      destination: destination,
      force: arguments.contains('--force'),
      log: stdout.writeln,
    );
    stdout.writeln(
      'Prepared ${archives.length} verified archives in ${destination.path}.',
    );
  } on Object catch (error) {
    stderr.writeln('Could not prepare ImcodecNative sources: $error');
    exitCode = 1;
  }
}

/// Locates this package for both path and Pub dependencies.
Future<Directory> _packageRoot() async {
  final Uri? libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:imcodec_native/imcodec_native.dart'),
  );
  if (libraryUri == null || libraryUri.scheme != 'file') {
    throw StateError('Could not locate the installed ImcodecNative package.');
  }
  return File.fromUri(libraryUri).parent.parent;
}
