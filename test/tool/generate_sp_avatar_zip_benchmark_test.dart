import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_sp_avatar_zip_benchmark.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sp-avatar-benchmark-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('scale-small ZIP and manifest are deterministic', () async {
    expect(benchmarkScaleSmallCounts, [500, 2000, 5000]);

    final first = await _generate(
      tempDir: tempDir,
      basename: 'first',
      profile: SpAvatarBenchmarkProfile.scaleSmall,
      count: 3,
      seed: 0x12345678,
    );
    final second = await _generate(
      tempDir: tempDir,
      basename: 'second',
      profile: SpAvatarBenchmarkProfile.scaleSmall,
      count: 3,
      seed: 0x12345678,
    );

    expect(first.manifest, second.manifest);
    expect(
      first.manifest['zipSha256'],
      'c59086e297d5276324198b6d3e89b13ad0c57f7b7ad75787c010f118bf3ac78d',
    );
    expect(first.manifest['seed'], 0x12345678);
    expect(first.manifest['requestedCount'], 3);
    expect(first.manifest['entryCount'], 3);
    expect(first.manifest['sourceDimensionHistogram'], {'48x48': 3});
    expect(first.manifest['appCommit'], 'test-app-commit');
    expect(first.manifest['compressedBytes'], 2025);
    expect(first.manifest['declaredUncompressedBytes'], 2380);
    expect(
      (first.manifest['expectedNormalizedOutputSizeBytes']! as Map)['count'],
      3,
    );
    await _expectSidecarMatches(first);
  });

  test(
    'near-pixel-limit records bounded test dimensions and output stats',
    () async {
      expect(
        nearPixelLimitWidth * nearPixelLimitHeight,
        lessThan(24 * 1000 * 1000),
      );
      expect(24 * 1000 * 1000 - nearPixelLimitWidth * nearPixelLimitHeight, 3);

      final result = await _generate(
        tempDir: tempDir,
        basename: 'near',
        profile: SpAvatarBenchmarkProfile.nearPixelLimit,
        count: 1,
        seed: 7,
        nearPixelWidth: 47,
        nearPixelHeight: 31,
      );

      expect(result.manifest['entryCount'], 1);
      expect(result.manifest['sourceDimensionHistogram'], {'47x31': 1});
      expect(result.manifest['entryKinds'], {
        'matched-valid-near-pixel-limit': 1,
      });
      final outputStats =
          result.manifest['expectedNormalizedOutputSizeBytes']! as Map;
      expect(outputStats['count'], 1);
      expect(outputStats['min'], greaterThan(0));
      expect(outputStats['min'], outputStats['max']);
      await _expectSidecarMatches(result);
    },
  );

  test('mixed-invalid manifest accounts for every edge entry', () async {
    final result = await _generate(
      tempDir: tempDir,
      basename: 'mixed',
      profile: SpAvatarBenchmarkProfile.mixedInvalid,
      count: 1,
      seed: 99,
      maxImageBytes: 64,
    );

    expect(result.manifest['entryCount'], 7);
    expect(result.manifest['entryKinds'], {
      'corrupt': 1,
      'duplicate-valid': 1,
      'empty': 1,
      'matched-valid': 1,
      'oversized': 1,
      'unmatched-valid': 1,
      'unsupported-extension': 1,
    });
    expect(result.manifest['sourceDimensionHistogram'], {'48x48': 3});
    expect(
      (result.manifest['expectedNormalizedOutputSizeBytes']! as Map)['count'],
      3,
    );
    expect(result.manifest['declaredUncompressedBytes'], greaterThan(64));
    await _expectSidecarMatches(result);
  });
}

Future<SpAvatarBenchmarkResult> _generate({
  required Directory tempDir,
  required String basename,
  required SpAvatarBenchmarkProfile profile,
  required int count,
  required int seed,
  int nearPixelWidth = nearPixelLimitWidth,
  int nearPixelHeight = nearPixelLimitHeight,
  int maxImageBytes = 20 * 1024 * 1024,
}) {
  return generateSpAvatarZipBenchmark(
    SpAvatarBenchmarkRequest(
      profile: profile,
      count: count,
      seed: seed,
      outputPath: '${tempDir.path}/$basename.zip',
      manifestPath: '${tempDir.path}/$basename.json',
      appCommit: 'test-app-commit',
      nearPixelWidth: nearPixelWidth,
      nearPixelHeight: nearPixelHeight,
      maxImageBytes: maxImageBytes,
    ),
  );
}

Future<void> _expectSidecarMatches(SpAvatarBenchmarkResult result) async {
  final decoded = jsonDecode(await File(result.manifestPath).readAsString());
  expect(decoded, result.manifest);
}
