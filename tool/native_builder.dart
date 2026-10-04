import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';

/// Keeps MSBuild intermediates below its legacy Windows path limit.
///
/// The native-assets output path identifies the target and compiler settings.
/// Hashing it preserves separate caches while shortening deeply nested projects.
Directory nativeBuildDirectory(
  Directory outputDirectory, {
  bool? windows,
  Directory? temporaryDirectory,
}) {
  if (!(windows ?? Platform.isWindows)) {
    return Directory.fromUri(outputDirectory.uri.resolve('cmake/'));
  }
  final String identity = outputDirectory.absolute.uri.normalizePath().toString().toLowerCase();
  final String key = sha256.convert(utf8.encode(identity)).toString().substring(0, 32);
  final Directory temporary = temporaryDirectory ?? Directory.systemTemp;
  return Directory('${temporary.path}/imcodec-native/$key');
}

/// Resolves CMake's target flags from the toolchain selected by Dart or Flutter.
List<String> nativeTargetArguments(CodeConfig config) {
  final OS os = config.targetOS;
  final Architecture architecture = config.targetArchitecture;
  if (os == OS.android) {
    final CCompilerConfig? compiler = config.cCompiler;
    if (compiler == null) {
      throw StateError(
        'Android builds require the NDK compiler selected by Flutter.',
      );
    }
    Directory parent = File.fromUri(compiler.compiler).parent;
    while (!File('${parent.path}/build/cmake/android.toolchain.cmake').existsSync()) {
      final Directory next = parent.parent;
      if (next.path == parent.path) {
        throw StateError(
          'Could not locate the Android NDK from ${compiler.compiler}.',
        );
      }
      parent = next;
    }
    final String abi = switch (architecture) {
      Architecture.arm => 'armeabi-v7a',
      Architecture.arm64 => 'arm64-v8a',
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError(
        'Unsupported Android architecture: $architecture',
      ),
    };
    return [
      '-DCMAKE_TOOLCHAIN_FILE=${parent.path}/build/cmake/android.toolchain.cmake',
      '-DANDROID_ABI=$abi',
      '-DANDROID_PLATFORM=android-${config.android.targetNdkApi}',
      '-DANDROID_STL=c++_static',
    ];
  }
  if (os == OS.windows) {
    return [
      '-A',
      switch (architecture) {
        Architecture.arm64 => 'ARM64',
        Architecture.x64 => 'x64',
        Architecture.ia32 => 'Win32',
        _ => throw UnsupportedError(
          'Unsupported Windows architecture: $architecture',
        ),
      },
    ];
  }
  final List<String> arguments = [];
  final CCompilerConfig? compiler = config.cCompiler;
  if (compiler != null) {
    final String path = compiler.compiler.toFilePath();
    // Some Linux launchers resolve /usr/bin/cc through ccache and lose cc's name.
    final String cCompiler = path.endsWith('/ccache') && Platform.isLinux ? '/usr/bin/gcc' : path;
    final String cppCompiler = cCompiler.endsWith('clang')
        ? '$cCompiler++'
        : cCompiler.endsWith('gcc')
        ? '${cCompiler.substring(0, cCompiler.length - 3)}g++'
        : cCompiler.endsWith('/cc')
        ? '${cCompiler.substring(0, cCompiler.length - 2)}c++'
        : throw StateError(
            'Cannot infer the C++ compiler accompanying $cCompiler.',
          );
    arguments.addAll([
      '-DCMAKE_C_COMPILER=$cCompiler',
      '-DCMAKE_CXX_COMPILER=$cppCompiler',
    ]);
  }
  if (os == OS.iOS || os == OS.macOS) {
    final String appleArchitecture = switch (architecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError(
        'Unsupported Apple architecture: $architecture',
      ),
    };
    arguments.add('-DCMAKE_OSX_ARCHITECTURES=$appleArchitecture');
    if (os == OS.iOS) {
      arguments.addAll([
        '-DCMAKE_SYSTEM_NAME=iOS',
        '-DCMAKE_SYSTEM_PROCESSOR=$appleArchitecture',
        '-DCMAKE_OSX_SYSROOT=${config.iOS.targetSdk}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.iOS.targetVersion}.0',
        '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
      ]);
    } else {
      // CMake 4 no longer selects a macOS SDK by default. libpng also invokes
      // the compiler directly while generating its configuration header.
      arguments.addAll([
        '-DCMAKE_OSX_SYSROOT=macosx',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.macOS.targetVersion}.0',
      ]);
    }
  } else if (os != OS.linux) {
    throw UnsupportedError('Unsupported native platform: $os');
  } else if (architecture != Architecture.current && compiler == null) {
    throw StateError(
      'Cross-compiling Linux requires an explicit compiler toolchain.',
    );
  }
  return arguments;
}

/// Builds the shared codec library into a target-specific CMake cache.
Future<File> buildNativeLibrary({
  required Directory packageRoot,
  required Directory buildDirectory,
  required Directory sourceDirectory,
  required CodeConfig config,
}) async {
  final String cmake = resolveNativeCMake(compiler: config.cCompiler);
  invalidateCMakeCacheIfSourceChanged(
    packageRoot: packageRoot,
    buildDirectory: buildDirectory,
  );
  final Directory nativeDirectory = Directory.fromUri(
    packageRoot.uri.resolve('native/'),
  );
  stdout.writeln('Configuring bundled ImcodecNative codec engines...');
  await runBuildCommand(cmake, [
    '-S',
    nativeDirectory.path,
    '-B',
    buildDirectory.path,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DIMCODEC_NATIVE_SOURCE_DIRECTORY=${nativeCMakePath(sourceDirectory.path)}',
    ...nativeTargetArguments(config),
  ]);
  stdout.writeln('Compiling ImcodecNative with $buildJobs parallel jobs...');
  await runBuildCommand(cmake, [
    '--build',
    buildDirectory.path,
    '--config',
    'Release',
    '--target',
    'imcodec_native',
    '--parallel',
    buildJobs.toString(),
  ]);
  final String libraryName = switch (config.targetOS) {
    OS.windows => 'imcodec_native.dll',
    OS.iOS || OS.macOS => 'libimcodec_native.dylib',
    _ => 'libimcodec_native.so',
  };
  final File library = File('${buildDirectory.path}/out/$libraryName');
  if (!library.existsSync()) {
    throw StateError('Native compilation did not produce ${library.path}.');
  }
  return library;
}

/// Uses forward slashes so generated CMake scripts cannot read path escapes.
///
/// FetchContent embeds its archive directory in another CMake script. Windows
/// backslashes such as `\U` must therefore never reach that generated literal.
String nativeCMakePath(String path) => path.replaceAll(r'\', '/');

/// Finds CMake on the host, including the copy bundled with Visual Studio.
///
/// An explicit override takes precedence over PATH. Windows native hooks
/// receive the selected compiler even when Visual Studio's CMake directory
/// has not been added to PATH, so the compiler locates that same installation.
String resolveNativeCMake({
  CCompilerConfig? compiler,
  Map<String, String>? environment,
  bool? windows,
}) {
  final Map<String, String> variables = environment ?? Platform.environment;
  final String? override = variables['IMCODEC_NATIVE_CMAKE'];
  if (override != null && override.trim().isNotEmpty) {
    return override;
  }
  if (!(windows ?? Platform.isWindows)) {
    return 'cmake';
  }
  final String path = variables.entries.where((entry) => entry.key.toUpperCase() == 'PATH').map((entry) => entry.value).firstOrNull ?? '';
  for (final String entry in path.split(';')) {
    final String directory = entry.trim().replaceAll(RegExp(r'^"|"$'), '');
    if (directory.isEmpty) {
      continue;
    }
    final File executable = File('$directory/cmake.exe');
    if (executable.existsSync()) {
      return executable.path;
    }
  }
  if (compiler != null) {
    Directory directory = File.fromUri(compiler.compiler).parent;
    while (true) {
      final File executable = File(
        '${directory.path}/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe',
      );
      if (executable.existsSync()) {
        return executable.path;
      }
      final Directory parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
  }
  throw StateError(
    'CMake was not found. Install Visual Studio C++ CMake tools, add CMake to PATH, or set IMCODEC_NATIVE_CMAKE.',
  );
}

/// Discards a CMake cache that belongs to another package location.
///
/// Dart's native-assets runner can retain the same shared output directory when
/// a dependency changes between a path checkout and pub.dev. CMake records the
/// absolute source path in its cache and refuses to reconfigure it elsewhere.
void invalidateCMakeCacheIfSourceChanged({
  required Directory packageRoot,
  required Directory buildDirectory,
}) {
  final File cache = File('${buildDirectory.path}/CMakeCache.txt');
  if (!cache.existsSync()) {
    return;
  }
  final RegExpMatch? match = RegExp(
    r'^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$',
    multiLine: true,
  ).firstMatch(cache.readAsStringSync());
  if (match == null) {
    return;
  }
  final Directory expected = Directory.fromUri(
    packageRoot.uri.resolve('native/'),
  );
  if (_sameDirectory(match[1]!, expected.path)) {
    return;
  }
  stdout.writeln(
    'Discarding a CMake cache created for a different ImcodecNative location.',
  );
  buildDirectory.deleteSync(recursive: true);
}

/// Compares source directories using host filesystem identity when available.
bool _sameDirectory(String first, String second) {
  try {
    if (FileSystemEntity.identicalSync(first, second)) {
      return true;
    }
  } on FileSystemException {
    // Fall back to a lexical comparison when the cached source no longer exists.
  }

  /// Canonicalizes a missing directory without requiring it to exist.
  String normalize(String path) => Directory(path).absolute.uri.normalizePath().toFilePath();
  final String normalizedFirst = normalize(first);
  final String normalizedSecond = normalize(second);
  return Platform.isWindows ? normalizedFirst.toLowerCase() == normalizedSecond.toLowerCase() : normalizedFirst == normalizedSecond;
}

/// Bounds concurrent C++ compilation to avoid exhausting developer machines.
int get buildJobs => Platform.numberOfProcessors.clamp(1, 4);

/// Runs a build tool without a shell, printing full diagnostics only on failure.
Future<void> runBuildCommand(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    throw ProcessException(
      executable,
      arguments,
      'Codec library build failed.',
      result.exitCode,
    );
  }
}
