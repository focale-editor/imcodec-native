import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:imcodec_native/imcodec_native.dart' as codec;

/// Initializes optional codecs before launching the cross-platform demo.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await codec.ImcodecNative.initialize();
  runApp(const CodecExample());
}

/// Demonstrates runner-based encoding and generic format detection.
class CodecExample extends StatefulWidget {
  /// Creates the demo application.
  const CodecExample({super.key});

  @override
  State<CodecExample> createState() => _CodecExampleState();
}

/// Owns only the ephemeral status and preview of the latest conversion.
class _CodecExampleState extends State<CodecExample> {
  /// PNG preview of the last decoded result.
  Uint8List? _preview;

  /// Conversion result or user-visible failure.
  String _status = 'Select a format to encode a synthetic RGBA image.';

  /// Prevents overlapping button actions.
  bool _busy = false;

  /// Runs native encoding through Imcodec's platform-appropriate runner.
  Future<void> _convert(codec.ImageFormat format) async {
    setState(() => _busy = true);
    try {
      final codec.Image source = codec.Image(width: 192, height: 128);
      for (int y = 0; y < source.height; y++) {
        for (int x = 0; x < source.width; x++) {
          source.setPixelRgba(x, y, x * 255 ~/ 191, y * 255 ~/ 127, 180, (x + y) % 32 < 16 ? 255 : 128);
        }
      }
      const codec.ParallelRunner runner = kIsWeb ? codec.runSequentially : codec.onBoundedIsolates;
      final Uint8List bytes = switch (format) {
        codec.NativeImageFormat.avif => await codec.encodeAvifWith(
          runner,
          source,
          options: const codec.AvifEncodeOptions(speed: 9),
        ),
        codec.NativeImageFormat.heif => await codec.encodeHeifWith(runner, source),
        codec.ImageFormat.jpegXl => await codec.encodeJpegXlWith(
          runner,
          source,
          options: const codec.JpegXlEncodeOptions(
            effort: codec.JpegXlEffort.fast,
          ),
        ),
        codec.ImageFormat.webp => await codec.encodeWebPWith(runner, source),
        codec.ImageFormat.png => await const codec.NativePngEncoder().encodeWith(runner, source),
        codec.ImageFormat.jpeg => await const codec.NativeJpegEncoder().encodeWith(runner, source),
        codec.ImageFormat.qoi => await const codec.NativeQoiEncoder().encodeWith(runner, source),
        codec.ImageFormat.tiff => await const codec.NativeTiffEncoder().encodeWith(runner, source),
        codec.ImageFormat.openExr => await const codec.NativeOpenExrEncoder().encodeWith(runner, source),
        _ => throw UnsupportedError('Unsupported demo format'),
      };
      final codec.Image decoded = switch (format) {
        codec.NativeImageFormat.avif => await codec.decodeAvifAsync(bytes),
        codec.NativeImageFormat.heif => await codec.decodeHeifAsync(bytes),
        codec.ImageFormat.jpegXl => await codec.decodeJpegXlAsync(bytes),
        codec.ImageFormat.webp => await codec.decodeWebPAsync(bytes),
        codec.ImageFormat.png => await codec.decodePngAsync(bytes),
        codec.ImageFormat.jpeg => await codec.decodeJpegAsync(bytes),
        codec.ImageFormat.qoi => await codec.decodeQoiAsync(bytes),
        codec.ImageFormat.tiff => await codec.decodeTiffAsync(bytes),
        codec.ImageFormat.openExr => await codec.decodeOpenExrAsync(bytes),
        _ => throw UnsupportedError('Unsupported demo format'),
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = codec.encodePng(decoded);
        _status = '${codec.ImageFormat.sniff(bytes)?.name}: ${bytes.length} bytes, ${decoded.width} × ${decoded.height}';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _status = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('ImcodecNative')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(codec.ImcodecNative.backendVersion),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final codec.ImageFormat format in [
                    codec.NativeImageFormat.avif,
                    codec.NativeImageFormat.heif,
                    codec.ImageFormat.jpegXl,
                    codec.ImageFormat.webp,
                    codec.ImageFormat.png,
                    codec.ImageFormat.jpeg,
                    codec.ImageFormat.qoi,
                    codec.ImageFormat.tiff,
                    codec.ImageFormat.openExr,
                  ])
                    FilledButton(onPressed: _busy ? null : () => _convert(format), child: Text(format.name)),
                ],
              ),
              const SizedBox(height: 24),
              if (_busy) const CircularProgressIndicator(),
              if (_preview case final Uint8List bytes) Image.memory(bytes, width: 384, gaplessPlayback: true),
              const SizedBox(height: 12),
              Text(_status),
            ],
          ),
        ),
      ),
    ),
  );
}
