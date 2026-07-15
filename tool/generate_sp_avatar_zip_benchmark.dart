import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

const benchmarkScaleSmallCounts = <int>[500, 2000, 5000];
const nearPixelLimitWidth = 4179;
const nearPixelLimitHeight = 5743;
const _productionMaxImageBytes = 20 * 1024 * 1024;
const _fixedZipModified = '2000-01-01T00:00:00.000Z';

const _usage = '''
Generate a deterministic Simply Plural avatar ZIP benchmark.

Usage:
  dart run tool/generate_sp_avatar_zip_benchmark.dart \\
    --profile <scale-small|near-pixel-limit|mixed-invalid> \\
    --count <count> \\
    --seed <integer> \\
    --out <avatars.zip> \\
    --app-commit <sha> [--manifest <manifest.json>]

Recommended scale-small counts: 500, 2000, 5000.

The ZIP is generated locally and is never added to the repository. The
manifest defaults to <out>.manifest.json.
''';

enum SpAvatarBenchmarkProfile {
  scaleSmall('scale-small'),
  nearPixelLimit('near-pixel-limit'),
  mixedInvalid('mixed-invalid');

  const SpAvatarBenchmarkProfile(this.cliName);

  final String cliName;

  static SpAvatarBenchmarkProfile parse(String value) {
    for (final profile in values) {
      if (profile.cliName == value) return profile;
    }
    throw FormatException('Unknown profile: $value');
  }
}

class SpAvatarBenchmarkRequest {
  const SpAvatarBenchmarkRequest({
    required this.profile,
    required this.count,
    required this.seed,
    required this.outputPath,
    required this.appCommit,
    this.manifestPath,
    this.nearPixelWidth = nearPixelLimitWidth,
    this.nearPixelHeight = nearPixelLimitHeight,
    this.maxImageBytes = _productionMaxImageBytes,
  });

  final SpAvatarBenchmarkProfile profile;
  final int count;
  final int seed;
  final String outputPath;
  final String appCommit;
  final String? manifestPath;

  /// Test-only size override for the near-24 MP fixture.
  final int nearPixelWidth;
  final int nearPixelHeight;

  /// Test-only byte limit for mixed-invalid fixtures.
  final int maxImageBytes;
}

class SpAvatarBenchmarkResult {
  const SpAvatarBenchmarkResult({
    required this.zipPath,
    required this.manifestPath,
    required this.manifest,
  });

  final String zipPath;
  final String manifestPath;
  final Map<String, Object?> manifest;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  try {
    final options = _parseOptions(args);
    final result = await generateSpAvatarZipBenchmark(
      SpAvatarBenchmarkRequest(
        profile: SpAvatarBenchmarkProfile.parse(
          _requiredOption(options, 'profile'),
        ),
        count: int.parse(_requiredOption(options, 'count')),
        seed: int.parse(_requiredOption(options, 'seed')),
        outputPath: _requiredOption(options, 'out'),
        appCommit: _requiredOption(options, 'app-commit'),
        manifestPath: options['manifest'],
      ),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.manifest));
    stdout.writeln('ZIP: ${result.zipPath}');
    stdout.writeln('Manifest: ${result.manifestPath}');
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n');
    stderr.write(_usage);
    exitCode = 64;
  }
}

Future<SpAvatarBenchmarkResult> generateSpAvatarZipBenchmark(
  SpAvatarBenchmarkRequest request,
) async {
  _validateRequest(request);

  final outputFile = File(request.outputPath);
  await outputFile.parent.create(recursive: true);
  if (await outputFile.exists()) await outputFile.delete();

  final output = OutputFileStream(outputFile.path, bufferSize: 64 * 1024);
  final encoder = ZipEncoder()
    ..startEncode(output, modified: DateTime.parse(_fixedZipModified));
  final accumulator = _ManifestAccumulator(request);

  try {
    switch (request.profile) {
      case SpAvatarBenchmarkProfile.scaleSmall:
        _addScaleSmallEntries(encoder, accumulator, request);
      case SpAvatarBenchmarkProfile.nearPixelLimit:
        _addNearPixelLimitEntry(encoder, accumulator, request);
      case SpAvatarBenchmarkProfile.mixedInvalid:
        _addMixedInvalidEntries(encoder, accumulator, request);
    }
    encoder.endEncode();
  } finally {
    output.closeSync();
  }

  final digest = await sha256.bind(outputFile.openRead()).first;
  final manifest = accumulator.toManifest(
    zipSha256: digest.toString(),
    compressedBytes: await outputFile.length(),
  );
  final manifestPath =
      request.manifestPath ?? '${outputFile.path}.manifest.json';
  final manifestFile = File(manifestPath);
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  return SpAvatarBenchmarkResult(
    zipPath: outputFile.path,
    manifestPath: manifestFile.path,
    manifest: manifest,
  );
}

void _addScaleSmallEntries(
  ZipEncoder encoder,
  _ManifestAccumulator accumulator,
  SpAvatarBenchmarkRequest request,
) {
  final random = _StableRandom(request.seed);
  for (var index = 0; index < request.count; index++) {
    final fixture = _smallJpeg(random, index);
    _addEntry(
      encoder,
      accumulator,
      name: 'avatars/${_sourceId(request.seed, index)}.jpg',
      bytes: fixture.bytes,
      kind: 'matched-valid',
      width: fixture.width,
      height: fixture.height,
      expectedNormalizedBytes: fixture.bytes.length,
    );
  }
}

void _addNearPixelLimitEntry(
  ZipEncoder encoder,
  _ManifestAccumulator accumulator,
  SpAvatarBenchmarkRequest request,
) {
  final color = _colorFor(request.seed, 0);
  final source = img.Image(
    width: request.nearPixelWidth,
    height: request.nearPixelHeight,
  );
  img.fill(source, color: color);
  final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 85));

  final normalizedWidth = request.nearPixelWidth >= request.nearPixelHeight
      ? 512
      : math.max(
          1,
          (request.nearPixelWidth * 512 / request.nearPixelHeight).round(),
        );
  final normalizedHeight = request.nearPixelHeight >= request.nearPixelWidth
      ? 512
      : math.max(
          1,
          (request.nearPixelHeight * 512 / request.nearPixelWidth).round(),
        );
  final normalized = img.Image(
    width: normalizedWidth,
    height: normalizedHeight,
  );
  img.fill(normalized, color: color);
  final expectedNormalizedBytes = img.encodeJpg(normalized, quality: 85).length;

  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/${_sourceId(request.seed, 0)}.jpg',
    bytes: bytes,
    kind: 'matched-valid-near-pixel-limit',
    width: request.nearPixelWidth,
    height: request.nearPixelHeight,
    expectedNormalizedBytes: expectedNormalizedBytes,
  );
}

void _addMixedInvalidEntries(
  ZipEncoder encoder,
  _ManifestAccumulator accumulator,
  SpAvatarBenchmarkRequest request,
) {
  final random = _StableRandom(request.seed);
  for (var index = 0; index < request.count; index++) {
    final fixture = _smallJpeg(random, index);
    _addEntry(
      encoder,
      accumulator,
      name: 'avatars/${_sourceId(request.seed, index)}.jpg',
      bytes: fixture.bytes,
      kind: 'matched-valid',
      width: fixture.width,
      height: fixture.height,
      expectedNormalizedBytes: fixture.bytes.length,
    );
  }

  final unmatched = _smallJpeg(random, request.count);
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/ffffffffffffffffffffffff.jpg',
    bytes: unmatched.bytes,
    kind: 'unmatched-valid',
    width: unmatched.width,
    height: unmatched.height,
    expectedNormalizedBytes: unmatched.bytes.length,
  );

  // Use distinct bytes to verify last-entry-wins behavior.
  final duplicate = _smallJpeg(random, request.count + 1);
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/${_sourceId(request.seed, 0)}.jpg',
    bytes: duplicate.bytes,
    kind: 'duplicate-valid',
    width: duplicate.width,
    height: duplicate.height,
    expectedNormalizedBytes: duplicate.bytes.length,
  );
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/empty.png',
    bytes: Uint8List(0),
    kind: 'empty',
  );
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/oversized.png',
    bytes: Uint8List(request.maxImageBytes + 1),
    kind: 'oversized',
  );
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/corrupt.webp',
    bytes: Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]),
    kind: 'corrupt',
  );
  _addEntry(
    encoder,
    accumulator,
    name: 'avatars/ignored.txt',
    bytes: Uint8List.fromList(utf8.encode('unsupported extension')),
    kind: 'unsupported-extension',
  );
}

void _addEntry(
  ZipEncoder encoder,
  _ManifestAccumulator accumulator, {
  required String name,
  required Uint8List bytes,
  required String kind,
  int? width,
  int? height,
  int? expectedNormalizedBytes,
}) {
  final file = ArchiveFile.bytes(name, bytes);
  encoder.add(file);
  accumulator.add(
    byteLength: bytes.length,
    kind: kind,
    width: width,
    height: height,
    expectedNormalizedBytes: expectedNormalizedBytes,
  );
}

_ImageFixture _smallJpeg(_StableRandom random, int index) {
  const width = 48;
  const height = 48;
  final image = img.Image(width: width, height: height);
  final base = _colorFor(random.nextUint32(), index);
  final accent = _colorFor(random.nextUint32(), index + 1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(
        x,
        y,
        ((x ~/ 8) + (y ~/ 8) + index).isEven ? base : accent,
      );
    }
  }
  return _ImageFixture(
    bytes: Uint8List.fromList(img.encodeJpg(image, quality: 82)),
    width: width,
    height: height,
  );
}

img.ColorRgb8 _colorFor(int seed, int index) {
  final value = (seed ^ (index * 0x9e3779b9)) & 0xffffffff;
  return img.ColorRgb8(
    32 + (value & 0xbf),
    32 + ((value >> 8) & 0xbf),
    32 + ((value >> 16) & 0xbf),
  );
}

String _sourceId(int seed, int index) {
  final seedHex = (seed & 0xffffffff).toRadixString(16).padLeft(8, '0');
  final indexHex = index.toRadixString(16).padLeft(16, '0');
  return '$seedHex$indexHex';
}

void _validateRequest(SpAvatarBenchmarkRequest request) {
  if (request.count <= 0) throw const FormatException('count must be positive');
  if (request.appCommit.trim().isEmpty) {
    throw const FormatException('app-commit must not be empty');
  }
  if (request.outputPath.trim().isEmpty) {
    throw const FormatException('out must not be empty');
  }
  if (request.nearPixelWidth <= 0 || request.nearPixelHeight <= 0) {
    throw const FormatException('near-pixel-limit dimensions must be positive');
  }
  final pixels = request.nearPixelWidth * request.nearPixelHeight;
  if (pixels >= 24 * 1000 * 1000) {
    throw const FormatException(
      'near-pixel-limit dimensions must remain below 24 MP',
    );
  }
  if (request.maxImageBytes <= 0) {
    throw const FormatException('maxImageBytes must be positive');
  }
  if (request.profile == SpAvatarBenchmarkProfile.nearPixelLimit &&
      request.count != 1) {
    throw const FormatException('near-pixel-limit count must be 1');
  }
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--')) {
      throw FormatException('Unexpected argument: $argument');
    }
    final name = argument.substring(2);
    if (name.isEmpty || index + 1 >= args.length) {
      throw FormatException('Missing value for $argument');
    }
    final value = args[++index];
    if (value.startsWith('--')) {
      throw FormatException('Missing value for $argument');
    }
    if (options.containsKey(name)) {
      throw FormatException('Duplicate option: $argument');
    }
    options[name] = value;
  }
  const known = {'profile', 'count', 'seed', 'out', 'app-commit', 'manifest'};
  final unknown = options.keys.where((key) => !known.contains(key));
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown option: --${unknown.first}');
  }
  return options;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw FormatException('Missing --$name');
  }
  return value;
}

class _ManifestAccumulator {
  _ManifestAccumulator(this.request);

  final SpAvatarBenchmarkRequest request;
  final Map<String, int> dimensions = <String, int>{};
  final Map<String, int> entryKinds = <String, int>{};
  final List<int> entrySizes = <int>[];
  final List<int> expectedNormalizedSizes = <int>[];
  int declaredBytes = 0;

  void add({
    required int byteLength,
    required String kind,
    required int? width,
    required int? height,
    required int? expectedNormalizedBytes,
  }) {
    declaredBytes += byteLength;
    entrySizes.add(byteLength);
    entryKinds.update(kind, (count) => count + 1, ifAbsent: () => 1);
    if (width != null && height != null) {
      dimensions.update(
        '${width}x$height',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (expectedNormalizedBytes != null) {
      expectedNormalizedSizes.add(expectedNormalizedBytes);
    }
  }

  Map<String, Object?> toManifest({
    required String zipSha256,
    required int compressedBytes,
  }) {
    return <String, Object?>{
      'schemaVersion': 1,
      'profile': request.profile.cliName,
      'seed': request.seed,
      'requestedCount': request.count,
      'entryCount': entrySizes.length,
      'zipSha256': zipSha256,
      'compressedBytes': compressedBytes,
      'declaredUncompressedBytes': declaredBytes,
      'sourceDimensionHistogram': _sortedMap(dimensions),
      'entryKinds': _sortedMap(entryKinds),
      'entrySizeBytes': _byteStats(entrySizes),
      'expectedNormalizedOutputSizeBytes': _byteStats(expectedNormalizedSizes),
      'normalizationModel': 'fixture-fast-path-or-solid-resize-v1',
      'appCommit': request.appCommit,
      'zipModifiedUtc': _fixedZipModified,
    };
  }
}

Map<String, int> _sortedMap(Map<String, int> values) {
  final keys = values.keys.toList()..sort();
  return <String, int>{for (final key in keys) key: values[key]!};
}

Map<String, Object> _byteStats(List<int> values) {
  if (values.isEmpty) {
    return const <String, Object>{
      'count': 0,
      'total': 0,
      'min': 0,
      'max': 0,
      'mean': 0.0,
      'p50': 0,
      'p95': 0,
    };
  }
  final sorted = List<int>.from(values)..sort();
  final total = sorted.fold<int>(0, (sum, value) => sum + value);
  return <String, Object>{
    'count': sorted.length,
    'total': total,
    'min': sorted.first,
    'max': sorted.last,
    'mean': total / sorted.length,
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
  };
}

int _percentile(List<int> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index];
}

class _ImageFixture {
  const _ImageFixture({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Stable xorshift32 for reproducible fixtures across SDKs.
class _StableRandom {
  _StableRandom(int seed) : _state = seed & 0xffffffff {
    if (_state == 0) _state = 0x6d2b79f5;
  }

  int _state;

  int nextUint32() {
    var value = _state;
    value ^= (value << 13) & 0xffffffff;
    value ^= value >> 17;
    value ^= (value << 5) & 0xffffffff;
    _state = value & 0xffffffff;
    return _state;
  }
}
