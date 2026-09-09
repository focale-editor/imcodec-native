import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';
import 'package:imcodec_native_example/main.dart';

/// Checks that the example offers each optional format after initialization.
void main() {
  setUpAll(() => ImcodecNative.initialize(assetBaseUrl: kIsWeb ? '/web_assets/' : null));

  testWidgets('shows every optional encoder', (tester) async {
    await tester.pumpWidget(const CodecExample());
    for (final String name in ['avif', 'heif', 'jpegXl', 'webp']) {
      expect(find.text(name), findsOneWidget);
    }
  });
}
