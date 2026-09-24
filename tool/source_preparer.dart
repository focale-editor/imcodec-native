import 'dart:io';

import 'package:crypto/crypto.dart';

/// Maximum accepted size for one downloaded codec source archive.
const int maximumSourceArchiveBytes = 512 * 1024 * 1024;

/// Describes one checksum-pinned upstream source archive.
final class NativeSourceArchive {
  /// CMake dependency name used for this archive.
  final String name;

  /// HTTPS location of the upstream release archive.
  final Uri uri;

  /// Expected lowercase SHA-256 digest.
  final String sha256;

  /// Creates a pinned source archive description.
  const NativeSourceArchive({
    required this.name,
    required this.uri,
    required this.sha256,
  });

  /// File name used by the source cache.
  String get fileName => uri.pathSegments.last;
}

/// Reads the codec source manifest used by CMake.
List<NativeSourceArchive> readNativeSourceManifest(Directory packageRoot) {
  final File manifest = File(
    '${packageRoot.path}/native/cmake/sources.cmake',
  );
  final String contents = manifest.readAsStringSync();
  final RegExp declaration = RegExp(
    r'imcodec_source\((\w+)\s+URL (https://\S+)\s+URL_HASH SHA256=([a-f0-9]{64})',
  );
  final List<NativeSourceArchive> sources = declaration
      .allMatches(contents)
      .map(
        (match) => NativeSourceArchive(
          name: match[1]!,
          uri: Uri.parse(match[2]!),
          sha256: match[3]!,
        ),
      )
      .toList(growable: false);
  if (sources.length != 17 || sources.map((source) => source.fileName).toSet().length != sources.length) {
    throw StateError(
      'Expected seventeen uniquely named sources in ${manifest.path}.',
    );
  }
  return sources;
}

/// Downloads every missing source archive and verifies its SHA-256 digest.
///
/// Existing valid files are reused. A source directory beside the package is
/// accepted as an offline seed, but published packages intentionally omit it.
Future<List<File>> prepareNativeSources({
  required Directory packageRoot,
  required Directory destination,
  bool force = false,
  void Function(String message)? log,
}) async {
  final List<NativeSourceArchive> sources = readNativeSourceManifest(
    packageRoot,
  );
  await destination.create(recursive: true);
  final Directory seed = Directory(
    '${packageRoot.path}/third_party/sources',
  );
  final List<File> archives = [];
  for (final NativeSourceArchive source in sources) {
    final File target = File('${destination.path}/${source.fileName}');
    final RandomAccessFile lock = await File('${target.path}.lock').open(
      mode: FileMode.append,
    );
    await lock.lock(FileLock.exclusive);
    try {
      if (!force && await _hasExpectedDigest(target, source.sha256)) {
        log?.call('Using cached ${source.fileName}.');
        archives.add(target);
        continue;
      }
      final File seeded = File('${seed.path}/${source.fileName}');
      if (!force && await _hasExpectedDigest(seeded, source.sha256)) {
        if (await target.exists()) {
          await target.delete();
        }
        await seeded.copy(target.path);
        log?.call('Cached packaged ${source.fileName}.');
        archives.add(target);
        continue;
      }
      log?.call('Downloading ${source.name} from ${source.uri.host}...');
      await _download(source, target);
      archives.add(target);
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }
  return List<File>.unmodifiable(archives);
}

/// Downloads [source] atomically into [target].
Future<void> _download(NativeSourceArchive source, File target) async {
  final File partial = File('${target.path}.partial-$pid');
  if (await partial.exists()) {
    await partial.delete();
  }
  final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final HttpClientRequest request = await client.getUrl(source.uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'ImcodecNative source preparer',
    );
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'The source server returned HTTP ${response.statusCode}.',
        uri: source.uri,
      );
    }
    if (response.redirects.any(
      (redirect) => redirect.location.scheme != 'https',
    )) {
      await response.drain<void>();
      throw HttpException(
        'A source download redirected outside HTTPS.',
        uri: source.uri,
      );
    }
    final IOSink output = partial.openWrite();
    int receivedBytes = 0;
    try {
      await for (final List<int> chunk in response) {
        receivedBytes += chunk.length;
        if (receivedBytes > maximumSourceArchiveBytes) {
          throw StateError(
            '${source.fileName} exceeds the source archive size limit.',
          );
        }
        output.add(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    final String actualDigest = await _digest(partial);
    if (actualDigest != source.sha256) {
      throw StateError(
        'Checksum mismatch for ${source.fileName}: expected '
        '${source.sha256}, got $actualDigest.',
      );
    }
    if (await target.exists()) {
      await target.delete();
    }
    await partial.rename(target.path);
  } finally {
    client.close(force: true);
    if (await partial.exists()) {
      await partial.delete();
    }
  }
}

/// Reports whether [file] exists with [expectedDigest].
Future<bool> _hasExpectedDigest(File file, String expectedDigest) async => await file.exists() && await _digest(file) == expectedDigest;

/// Calculates the lowercase SHA-256 digest of [file].
Future<String> _digest(File file) async => (await sha256.bind(file.openRead()).first).toString();
