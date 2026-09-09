import 'dart:io';

import 'native_builder.dart';
import 'source_preparer.dart';

/// Emscripten version used to produce the shipped browser assets.
const String emscriptenVersion = '4.0.15';

/// Rebuilds the browser module with the same engines and bridge as native builds.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 || (arguments.isNotEmpty && !arguments.single.startsWith('--emcmake='))) {
    stderr.writeln('Usage: dart run tool/web_library_builder.dart [--emcmake=/path/to/emcmake]');
    exitCode = 64;
    return;
  }
  final Directory root = File.fromUri(Platform.script).parent.parent;
  final String emcmake = arguments.isNotEmpty ? arguments.single.substring('--emcmake='.length) : Platform.environment['IMCODEC_NATIVE_EMCMAKE'] ?? 'emcmake';
  final String emcc = emcmake.contains(Platform.pathSeparator) ? '${File(emcmake).parent.path}/emcc' : 'emcc';
  final ProcessResult version = await Process.run(emcc, ['--version']);
  if (version.exitCode != 0 || !version.stdout.toString().contains(' $emscriptenVersion ')) {
    throw StateError('Web assets require Emscripten $emscriptenVersion: ${version.stdout} ${version.stderr}');
  }
  final String buildPath = '${root.path}/build/web';
  final Directory sourceDirectory = Directory(
    '${root.path}/build/source-cache',
  );
  await prepareNativeSources(
    packageRoot: root,
    destination: sourceDirectory,
    log: stdout.writeln,
  );
  await runBuildCommand(emcmake, [
    'cmake',
    '-S',
    '${root.path}/native',
    '-B',
    buildPath,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DIMCODEC_NATIVE_SOURCE_DIRECTORY=${sourceDirectory.path}',
  ]);
  await runBuildCommand('cmake', ['--build', buildPath, '--target', 'imcodec_native', '--parallel', buildJobs.toString()]);
  for (final String name in ['imcodec_native.mjs', 'imcodec_native.wasm']) {
    await File('$buildPath/out/$name').copy('${root.path}/assets/web/$name');
  }
}
