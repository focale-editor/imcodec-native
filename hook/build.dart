import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import '../tool/native_builder.dart';
import '../tool/source_preparer.dart';

/// Builds and bundles all native engines for Dart's exact target platform.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final Directory packageRoot = Directory.fromUri(input.packageRoot);
    final Directory sourceDirectory = Directory.fromUri(
      input.outputDirectoryShared.resolve('codec-sources/'),
    );
    await prepareNativeSources(
      packageRoot: packageRoot,
      destination: sourceDirectory,
      log: stdout.writeln,
    );
    final Directory buildDirectory = Directory.fromUri(input.outputDirectory.resolve('cmake/'));
    final File library = await buildNativeLibrary(
      packageRoot: packageRoot,
      buildDirectory: buildDirectory,
      sourceDirectory: sourceDirectory,
      config: input.config.code,
    );
    output.assets.code.add(CodeAsset(package: input.packageName, name: 'src/native/bindings.dart', file: library.uri, linkMode: DynamicLoadingBundled()));
    output.dependencies.addAll(
      Directory('${packageRoot.path}/native').listSync(recursive: true).whereType<File>().map((file) => file.uri),
    );
  });
}
