import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/codec_test.dart' as codecs;
import '../../test/format_test.dart' as formats;
import '../../test/raster_codec_test.dart' as rasters;
import '../../test/raster_metadata_test.dart' as metadata;

/// Runs the existing real-codec suites inside the target operating system.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('format registration', formats.main);
  group('native codecs', codecs.main);
  group('native rasters', rasters.main);
  group('native metadata', metadata.main);
}
