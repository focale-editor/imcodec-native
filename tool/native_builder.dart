import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// Resolves CMake's target flags from the toolchain selected by Dart or Flutter.
List<String> nativeTargetArguments(CodeConfig config) {
  final OS os = config.targetOS;
  final Architecture architecture = config.targetArchitecture;
  if (os == OS.android) {
    final CCompilerConfig? compiler = config.cCompiler;
    if (compiler == null) {
      throw StateError('Android builds require the NDK compiler selected by Flutter.');
    }
    Directory parent = File.fromUri(compiler.compiler).parent;
    while (!File('${parent.path}/build/cmake/android.toolchain.cmake').existsSync()) {
      final Directory next = parent.parent;
      if (next.path == parent.path) {
        throw StateError('Could not locate the Android NDK from ${compiler.compiler}.');
      }
      parent = next;
    }
    final String abi = switch (architecture) {
      Architecture.arm => 'armeabi-v7a',
      Architecture.arm64 => 'arm64-v8a',
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError('Unsupported Android architecture: $architecture'),
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
        _ => throw UnsupportedError('Unsupported Windows architecture: $architecture'),
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
        : throw StateError('Cannot infer the C++ compiler accompanying $cCompiler.');
    arguments.addAll(['-DCMAKE_C_COMPILER=$cCompiler', '-DCMAKE_CXX_COMPILER=$cppCompiler']);
  }
  if (os == OS.iOS || os == OS.macOS) {
    final String appleArchitecture = switch (architecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError('Unsupported Apple architecture: $architecture'),
    };
    arguments.add('-DCMAKE_OSX_ARCHITECTURES=$appleArchitecture');
    if (os == OS.iOS) {
      arguments.addAll([
        '-DCMAKE_SYSTEM_NAME=iOS',
        '-DCMAKE_OSX_SYSROOT=${config.iOS.targetSdk}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.iOS.targetVersion}.0',
        '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
      ]);
    } else {
      arguments.add('-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.macOS.targetVersion}.0');
    }
  } else if (os != OS.linux) {
    throw UnsupportedError('Unsupported native platform: $os');
  } else if (architecture != Architecture.current && compiler == null) {
    throw StateError('Cross-compiling Linux requires an explicit compiler toolchain.');
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
  final String cmake = Platform.environment['IMCODEC_NATIVE_CMAKE'] ?? 'cmake';
  stdout.writeln('Configuring bundled ImcodecNative codec engines...');
  await runBuildCommand(cmake, [
    '-S',
    '${packageRoot.path}/native',
    '-B',
    buildDirectory.path,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DIMCODEC_NATIVE_SOURCE_DIRECTORY=${sourceDirectory.path}',
    ...nativeTargetArguments(config),
  ]);
  stdout.writeln('Compiling ImcodecNative with $buildJobs parallel jobs...');
  await runBuildCommand(cmake, ['--build', buildDirectory.path, '--config', 'Release', '--target', 'imcodec_native', '--parallel', buildJobs.toString()]);
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
