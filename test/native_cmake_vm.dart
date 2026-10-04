import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../tool/native_builder.dart';

/// Checks host tool discovery without launching CMake or compiling codecs.
void registerNativeCMakeTests() {
  test('archive directories cannot become CMake escape sequences', () {
    expect(nativeCMakePath(r'C:\Users\some person\codec-sources\'), 'C:/Users/some person/codec-sources/');
    expect(nativeCMakePath('/tmp/codec-sources/'), '/tmp/codec-sources/');
  });

  test('explicit executable overrides PATH and Visual Studio discovery', () {
    expect(
      resolveNativeCMake(
        windows: true,
        environment: {'IMCODEC_NATIVE_CMAKE': 'custom/cmake.exe'},
      ),
      'custom/cmake.exe',
    );
  });

  test('non-Windows hosts retain PATH-based CMake invocation', () {
    expect(resolveNativeCMake(windows: false, environment: {}), 'cmake');
  });

  test('Windows PATH is case insensitive and accepts quoted directories', () {
    final Directory directory = Directory.systemTemp.createTempSync(
      'cmake path ',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final File executable = File('${directory.path}/cmake.exe')..createSync();
    expect(
      resolveNativeCMake(
        windows: true,
        environment: {'Path': ';"${directory.path}";'},
      ),
      executable.path,
    );
  });

  test('finds CMake in the same Visual Studio installation as the compiler', () {
    final Directory installation = Directory.systemTemp.createTempSync(
      'visual studio ',
    );
    addTearDown(() => installation.deleteSync(recursive: true));
    final File executable = File(
      '${installation.path}/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe',
    )..createSync(recursive: true);
    final File compiler = File(
      '${installation.path}/VC/Tools/MSVC/version/bin/Hostx64/x64/cl.exe',
    )..createSync(recursive: true);
    final CCompilerConfig config = CCompilerConfig(
      compiler: compiler.uri,
      linker: compiler.uri,
      archiver: compiler.uri,
    );
    expect(
      resolveNativeCMake(compiler: config, windows: true, environment: {}),
      executable.path,
    );
  });

  test('missing Windows tool reports an actionable error', () {
    expect(
      () => resolveNativeCMake(windows: true, environment: {}),
      throwsA(isA<StateError>()),
    );
  });

  test('preserves a cache from the same package and discards a relocated one', () {
    final Directory workspace = Directory.systemTemp.createTempSync('imcodec cache ');
    addTearDown(() => workspace.deleteSync(recursive: true));
    final Directory package = Directory('${workspace.path}/package');
    final Directory native = Directory('${package.path}/native')..createSync(recursive: true);
    final Directory build = Directory('${workspace.path}/build')..createSync();
    final File cache = File('${build.path}/CMakeCache.txt');
    final File sentinel = File('${build.path}/old-generated-project')..writeAsStringSync('cached');
    cache.writeAsStringSync('CMAKE_HOME_DIRECTORY:INTERNAL=${native.path}\n');

    invalidateCMakeCacheIfSourceChanged(packageRoot: package, buildDirectory: build);
    expect(sentinel.existsSync(), isTrue);

    cache.writeAsStringSync('CMAKE_HOME_DIRECTORY:INTERNAL=${workspace.path}/old-package/native\n');
    invalidateCMakeCacheIfSourceChanged(packageRoot: package, buildDirectory: build);
    expect(build.existsSync(), isFalse);
    expect(native.existsSync(), isTrue);
  });
}
