import 'package:flutter_test/flutter_test.dart';

/// Registers the browser placeholder for native toolchain mapping tests.
void registerNativeBuilderTests() {
  test(
    'native builder mappings require a Dart VM',
    () {},
    skip: 'CMake toolchains are not available in a browser.',
  );
}
