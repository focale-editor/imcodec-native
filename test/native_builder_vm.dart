import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

import '../tool/native_builder.dart';
import '../tool/source_preparer.dart';

/// Verifies every target mapping without invoking a platform compiler.
void registerNativeBuilderTests() {
  final Directory toolDirectory = Directory.systemTemp.createTempSync('imcodec-native-toolchain-');
  tearDownAll(() => toolDirectory.deleteSync(recursive: true));
  final String toolPath = toolDirectory.path;
  for (final String name in ['clang', 'clang++', 'ld.lld', 'llvm-ar']) {
    File('$toolPath/$name').createSync();
  }
  final CCompilerConfig clang = CCompilerConfig(
    archiver: Uri.file('$toolPath/llvm-ar'),
    compiler: Uri.file('$toolPath/clang'),
    linker: Uri.file('$toolPath/ld.lld'),
  );

  test('pins all codec sources to HTTPS archives and SHA-256 digests', () {
    final List<NativeSourceArchive> sources = readNativeSourceManifest(
      Directory.current,
    );

    expect(sources, hasLength(9));
    expect(sources.map((source) => source.name).toSet(), hasLength(9));
    expect(
      sources.every(
        (source) => source.uri.scheme == 'https' && RegExp(r'^[a-f0-9]{64}$').hasMatch(source.sha256),
      ),
      isTrue,
    );
  });

  test('forces libheif to resolve the bundled AOM target', () {
    final String sources = File(
      'native/cmake/sources.cmake',
    ).readAsStringSync();
    final int aomStart = sources.indexOf('imcodec_source(aom');
    final int webpStart = sources.indexOf('imcodec_source(libwebp');
    expect(aomStart, greaterThanOrEqualTo(0));
    expect(webpStart, greaterThan(aomStart));
    final String aomDeclaration = sources.substring(aomStart, webpStart);
    final String project = File('native/CMakeLists.txt').readAsStringSync();

    expect(aomDeclaration, contains('OVERRIDE_FIND_PACKAGE'));
    expect(project, contains('add_library(AOM::aom ALIAS aom)'));
    expect(project, contains('set(AOM_FOUND TRUE)'));
    expect(project, contains(r'set(AOM_INCLUDE_DIRS "${aom_SOURCE_DIR}")'));
    expect(project, contains('set(AOM_LIBRARIES aom)'));
  });

  test('corresponding-source links are dynamic and version-agnostic', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String sourceOffer = File('docs/SOURCE_OFFER.md').readAsStringSync();
    final RegExpMatch? version = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(version, isNotNull);
    expect(
      sourceOffer,
      contains(
        'https://img.shields.io/github/v/release/'
        'focale-editor/imcodec-native',
      ),
    );
    expect(
      sourceOffer,
      contains(
        'https://github.com/focale-editor/imcodec-native/releases/latest',
      ),
    );
    expect(
      sourceOffer,
      contains(
        'https://github.com/focale-editor/imcodec-native/releases/tag/'
        '{package-version}',
      ),
    );
    expect(sourceOffer, isNot(contains('/releases/tag/${version![1]}')));
  });

  test('maps Android architecture, API and NDK toolchain', () async {
    final Directory ndk = Directory.systemTemp.createTempSync('imcodec-native-ndk-');
    addTearDown(() => ndk.deleteSync(recursive: true));
    final File toolchain = File('${ndk.path}/build/cmake/android.toolchain.cmake')..createSync(recursive: true);
    for (final String name in ['clang', 'ld.lld', 'llvm-ar']) {
      File('${ndk.path}/toolchains/llvm/prebuilt/host/bin/$name').createSync(recursive: true);
    }
    final CCompilerConfig compiler = CCompilerConfig(
      archiver: Uri.file(
        '${ndk.path}/toolchains/llvm/prebuilt/host/bin/llvm-ar',
      ),
      compiler: Uri.file(
        '${ndk.path}/toolchains/llvm/prebuilt/host/bin/clang',
      ),
      linker: Uri.file(
        '${ndk.path}/toolchains/llvm/prebuilt/host/bin/ld.lld',
      ),
    );
    for (final (Architecture, String) mapping in [
      (Architecture.arm, 'armeabi-v7a'),
      (Architecture.arm64, 'arm64-v8a'),
      (Architecture.ia32, 'x86'),
      (Architecture.x64, 'x86_64'),
    ]) {
      expect(
        await _argumentsFor(
          os: OS.android,
          architecture: mapping.$1,
          compiler: compiler,
          androidApi: 24,
        ),
        [
          '-DCMAKE_TOOLCHAIN_FILE=${toolchain.path}',
          '-DANDROID_ABI=${mapping.$2}',
          '-DANDROID_PLATFORM=android-24',
          '-DANDROID_STL=c++_static',
        ],
      );
    }
  });

  test('maps iOS device and simulator SDKs', () async {
    expect(
      await _argumentsFor(
        os: OS.iOS,
        architecture: Architecture.arm64,
        compiler: clang,
        iOSSdk: IOSSdk.iPhoneOS,
        iOSVersion: 13,
      ),
      containsAll([
        '-DCMAKE_C_COMPILER=$toolPath/clang',
        '-DCMAKE_CXX_COMPILER=$toolPath/clang++',
        '-DCMAKE_OSX_ARCHITECTURES=arm64',
        '-DCMAKE_SYSTEM_NAME=iOS',
        '-DCMAKE_OSX_SYSROOT=iphoneos',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
      ]),
    );
    expect(
      await _argumentsFor(
        os: OS.iOS,
        architecture: Architecture.x64,
        compiler: clang,
        iOSSdk: IOSSdk.iPhoneSimulator,
      ),
      containsAll([
        '-DCMAKE_OSX_ARCHITECTURES=x86_64',
        '-DCMAKE_OSX_SYSROOT=iphonesimulator',
      ]),
    );
    expect(
      await _argumentsFor(
        os: OS.iOS,
        architecture: Architecture.arm64,
        compiler: clang,
        iOSSdk: IOSSdk.iPhoneSimulator,
      ),
      containsAll([
        '-DCMAKE_OSX_ARCHITECTURES=arm64',
        '-DCMAKE_OSX_SYSROOT=iphonesimulator',
      ]),
    );
  });

  test('maps macOS and Windows architectures', () async {
    expect(
      await _argumentsFor(
        os: OS.macOS,
        architecture: Architecture.x64,
        compiler: clang,
        macOSVersion: 12,
      ),
      containsAll([
        '-DCMAKE_OSX_ARCHITECTURES=x86_64',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
      ]),
    );
    expect(
      await _argumentsFor(
        os: OS.macOS,
        architecture: Architecture.arm64,
        compiler: clang,
      ),
      contains('-DCMAKE_OSX_ARCHITECTURES=arm64'),
    );
    for (final (Architecture, String) mapping in [
      (Architecture.ia32, 'Win32'),
      (Architecture.x64, 'x64'),
      (Architecture.arm64, 'ARM64'),
    ]) {
      expect(
        await _argumentsFor(
          os: OS.windows,
          architecture: mapping.$1,
        ),
        ['-A', mapping.$2],
      );
    }
  });

  test('uses the configured Linux C and C++ compiler pair', () async {
    expect(
      await _argumentsFor(
        os: OS.linux,
        architecture: Architecture.x64,
        compiler: clang,
      ),
      [
        '-DCMAKE_C_COMPILER=$toolPath/clang',
        '-DCMAKE_CXX_COMPILER=$toolPath/clang++',
      ],
    );
  });

  test('invalidates a CMake cache from another package location', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'imcodec-native-cmake-cache-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory firstPackage = Directory('${root.path}/first')..createSync();
    final Directory secondPackage = Directory('${root.path}/second')..createSync();
    final Directory firstNative = Directory('${firstPackage.path}/native')..createSync();
    Directory('${secondPackage.path}/native').createSync();
    final Directory buildDirectory = Directory('${root.path}/build')..createSync();
    File('${buildDirectory.path}/CMakeCache.txt').writeAsStringSync(
      'CMAKE_HOME_DIRECTORY:INTERNAL=${firstNative.path}\n',
    );
    File('${buildDirectory.path}/sentinel').createSync();

    invalidateCMakeCacheIfSourceChanged(
      packageRoot: secondPackage,
      buildDirectory: buildDirectory,
    );

    expect(buildDirectory.existsSync(), isFalse);
  });

  test('retains a CMake cache from the current package location', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'imcodec-native-cmake-cache-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory nativeDirectory = Directory('${root.path}/native')..createSync();
    final Directory buildDirectory = Directory('${root.path}/build')..createSync();
    final File cache = File('${buildDirectory.path}/CMakeCache.txt')
      ..writeAsStringSync(
        'CMAKE_HOME_DIRECTORY:INTERNAL=${nativeDirectory.path}\n',
      );

    invalidateCMakeCacheIfSourceChanged(
      packageRoot: root,
      buildDirectory: buildDirectory,
    );

    expect(cache.existsSync(), isTrue);
  });
}

/// Creates a protocol-authentic [CodeConfig] and captures its CMake arguments.
Future<List<String>> _argumentsFor({
  required OS os,
  required Architecture architecture,
  CCompilerConfig? compiler,
  IOSSdk iOSSdk = IOSSdk.iPhoneOS,
  int iOSVersion = 17,
  int macOSVersion = 13,
  int androidApi = 30,
}) async {
  final List<List<String>> captured = [];
  await testCodeBuildHook(
    mainMethod: (arguments) => build(arguments, (input, output) async {
      captured.add(nativeTargetArguments(input.config.code));
    }),
    check: (input, output) {},
    targetOS: os,
    targetArchitecture: architecture,
    targetIOSSdk: iOSSdk,
    targetIOSVersion: iOSVersion,
    targetMacOSVersion: macOSVersion,
    targetAndroidNdkApi: androidApi,
    cCompiler: compiler,
  );
  return captured.single;
}
