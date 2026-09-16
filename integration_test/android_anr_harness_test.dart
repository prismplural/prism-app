// Profile-mode Android responsiveness harness for ANR-sensitive workloads.
//
// Run through tool/run_android_anr_harness.sh so logcat, memory samples, device
// provenance, and the structured events below are captured together.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;
import 'package:prism_plurality/core/services/media/hashing_helper.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/encrypted_export_file_writer.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

import 'support/main_isolate_pulse_monitor.dart';

const _maxPulseGapMicros = int.fromEnvironment(
  'PRISM_ANR_MAX_PULSE_GAP_MICROS',
  defaultValue: 500000,
);
const _exportRecords = int.fromEnvironment(
  'PRISM_ANR_EXPORT_RECORDS',
  defaultValue: 20000,
);
const _exportMediaMiB = int.fromEnvironment(
  'PRISM_ANR_EXPORT_MEDIA_MIB',
  defaultValue: 16,
);
const _hashMiB = int.fromEnvironment('PRISM_ANR_HASH_MIB', defaultValue: 32);
const _exportImageMembers = int.fromEnvironment(
  'PRISM_ANR_EXPORT_IMAGE_MEMBERS',
  defaultValue: 48,
);
const _exportImageKiB = int.fromEnvironment(
  'PRISM_ANR_EXPORT_IMAGE_KIB',
  defaultValue: 512,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('The ANR harness must run on Android.');
    }
    if (_maxPulseGapMicros <= 0 ||
        _exportRecords <= 0 ||
        _exportMediaMiB <= 0 ||
        _exportImageMembers <= 0 ||
        _exportImageKiB <= 0 ||
        _hashMiB <= 0) {
      throw StateError(
        'ANR harness sizes and pulse threshold must be positive.',
      );
    }
    await media_codec.initializeMediaCodec();
    _emit('harness_begin', {
      'maxPulseGapMicros': _maxPulseGapMicros,
      'exportRecords': _exportRecords,
      'exportMediaMiB': _exportMediaMiB,
      'exportImageMembers': _exportImageMembers,
      'exportImageKiB': _exportImageKiB,
      'hashMiB': _hashMiB,
    });
  });

  testWidgets('pulse monitor detects a known main-isolate stall', (
    tester,
  ) async {
    final monitor = await MainIsolatePulseMonitor.start();
    final stall = Stopwatch()..start();
    while (stall.elapsed < const Duration(milliseconds: 650)) {
      // Calibration: intentionally starve this isolate.
    }
    stall.stop();
    final summary = await monitor.stop();
    _emit('monitor_calibration', summary.toJson(thresholdMicros: 500000));
    expect(summary.maximumGapMicros, greaterThan(500000));
  });

  testWidgets('encrypted export keeps the main isolate responsive', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('prism-anr-export-');
    try {
      final media = File('${root.path}/media.enc');
      await media.writeAsBytes(_patternBytes(_exportMediaMiB * 1024 * 1024));
      final stat = await media.stat();
      final export = _largeExport(_exportRecords);
      final output = File('${root.path}/large.prism');

      final result = await _measure('encrypted_export', () async {
        return writeEncryptedExportFileOffMain(
          EncryptedExportWriteTask(
            export: export,
            mediaBlobs: [
              ExportMediaBlobTask(
                mediaId: 'benchmark-media',
                path: media.path,
                lengthBytes: stat.size,
                modifiedMillisecondsSinceEpoch:
                    stat.modified.millisecondsSinceEpoch,
              ),
            ],
            password: 'android-anr-harness-password',
            outputPath: output.path,
          ),
        );
      });

      expect(result.value, greaterThan(0));
      expect(await output.length(), result.value);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  testWidgets('profile-header preparation keeps the main isolate responsive', (
    tester,
  ) async {
    final source = _largeHeaderFixture();
    final result = await _measure('profile_header', () {
      return ProfileHeaderImageNormalizer().normalizeOffMainIsolate(source);
    });

    expect(result.value, isNotEmpty);
    expect(
      result.value.length,
      lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
    );
  });

  testWidgets('large media hashing keeps the main isolate responsive', (
    tester,
  ) async {
    final bytes = _patternBytes(_hashMiB * 1024 * 1024);
    final result = await _measure(
      'media_hash',
      () => hashBytesForIntegrity(bytes),
    );

    expect(result.value, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  tearDownAll(() {
    // This marker means the suite reached teardown. The authoritative pass/fail
    // signal is Flutter's process exit status plus the per-scenario evidence.
    _emit('harness_teardown_reached', const {});
  });
}

Future<_Measured<T>> _measure<T>(
  String scenario,
  Future<T> Function() action,
) async {
  _emit('scenario_begin', {'scenario': scenario});
  final monitor = await MainIsolatePulseMonitor.start();
  final elapsed = Stopwatch()..start();
  late T value;
  late final MainIsolatePulseSummary pulse;
  try {
    value = await action();
  } finally {
    elapsed.stop();
    pulse = await monitor.stop();
    _emit('scenario_end', {
      'scenario': scenario,
      'elapsedMicros': elapsed.elapsedMicroseconds,
      'heartbeat': pulse.toJson(thresholdMicros: _maxPulseGapMicros),
    });
  }

  expect(
    pulse.pulseCount,
    greaterThan(0),
    reason: '$scenario emitted no pulses',
  );
  expect(
    pulse.maximumGapMicros,
    lessThanOrEqualTo(_maxPulseGapMicros),
    reason: '$scenario blocked the main isolate beyond the configured gate',
  );
  return _Measured(value: value, pulse: pulse);
}

V1Export _largeExport(int count) {
  const timestamp = '2026-09-15T00:00:00.000Z';
  final body = List<String>.filled(16, 'ANR export payload').join(' ');
  return V1Export(
    formatVersion: '1.0',
    version: '1.0',
    appName: 'Prism ANR Harness',
    exportDate: timestamp,
    totalRecords: count + _exportImageMembers,
    headmates: [
      for (var index = 0; index < _exportImageMembers; index++)
        V1Headmate(
          id: 'image-member-$index',
          name: 'Image Member $index',
          createdAt: timestamp,
          profilePhotoData: _inlineImageBase64(index, 0),
          profileHeaderImageData: _inlineImageBase64(index, 1),
          pkBannerImageData: _inlineImageBase64(index, 2),
        ),
    ],
    frontSessions: const [],
    sleepSessions: const [],
    conversations: const [],
    messages: [
      for (var index = 0; index < count; index++)
        V1Message(
          id: 'message-$index',
          content: '$body $index',
          timestamp: timestamp,
          conversationId: 'benchmark-conversation',
          authorId: 'benchmark-member',
        ),
    ],
    polls: const [],
    pollOptions: const [],
    systemSettings: const [],
    habits: const [],
    habitCompletions: const [],
  );
}

String _inlineImageBase64(int memberIndex, int imageKind) {
  final bytes = Uint8List(_exportImageKiB * 1024);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = (index * 31 + memberIndex * 17 + imageKind * 53) & 0xff;
  }
  return base64Encode(bytes);
}

Uint8List _largeHeaderFixture() {
  const width = 3600;
  const height = 1800;
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        (x * 17 + y * 3) & 0xff,
        (x * 5 + y * 11) & 0xff,
        (x + y * 7) & 0xff,
        ((x ~/ 32 + y ~/ 32).isEven ? 180 : 255),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _patternBytes(int length) {
  final bytes = Uint8List(length);
  for (var index = 0; index < length; index++) {
    bytes[index] = (index * 31 + 17) & 0xff;
  }
  return bytes;
}

void _emit(String event, Map<String, Object?> fields) {
  // ignore: avoid_print
  print('PRISM_ANR_HARNESS ${jsonEncode({'event': event, ...fields})}');
}

final class _Measured<T> {
  const _Measured({required this.value, required this.pulse});

  final T value;
  final MainIsolatePulseSummary pulse;
}
