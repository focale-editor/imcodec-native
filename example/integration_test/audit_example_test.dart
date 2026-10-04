import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imcodec_native/imcodec_native.dart';
import 'package:imcodec_native_example/main.dart' as example;
import 'package:integration_test/integration_test.dart';

/// Exercises each encoder through the real example and its isolate runners.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('all nine example conversions succeed', (tester) async {
    await ImcodecNative.initialize();
    await tester.pumpWidget(const example.CodecExample());
    await tester.pumpAndSettle();
    for (final name in ['avif', 'heif', 'jpegXl', 'webp', 'png', 'jpeg', 'qoi', 'tiff', 'openExr']) {
      await tester.tap(find.text(name));
      for (int attempt = 0; attempt < 300; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.byType(CircularProgressIndicator), findsNothing, reason: name);
      expect(find.textContaining('$name:'), findsOneWidget, reason: name);
      expect(find.textContaining('192 × 128'), findsOneWidget, reason: name);
      expect(tester.takeException(), isNull, reason: name);
    }
  });
}
