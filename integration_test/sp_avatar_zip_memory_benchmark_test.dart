// Android strict-memory gate for large Simply Plural avatar ZIP imports.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';

import '../tool/generate_sp_avatar_zip_benchmark.dart';

const _caseName = String.fromEnvironment('SP_AVATAR_ZIP_BENCHMARK_CASE');
const _profileName = String.fromEnvironment('SP_AVATAR_ZIP_BENCHMARK_PROFILE');
const _count = int.fromEnvironment('SP_AVATAR_ZIP_BENCHMARK_COUNT');
const _repetitions = int.fromEnvironment('SP_AVATAR_ZIP_BENCHMARK_REPETITIONS');
const _seed = int.fromEnvironment('SP_AVATAR_ZIP_BENCHMARK_SEED');
const _appCommit = String.fromEnvironment('SP_AVATAR_ZIP_APP_COMMIT');
const _beforeIdleSeconds = int.fromEnvironment(
  'SP_AVATAR_ZIP_BEFORE_IDLE_SECONDS',
  defaultValue: 10,
);
const _afterIdleSeconds = int.fromEnvironment(
  'SP_AVATAR_ZIP_AFTER_IDLE_SECONDS',
  defaultValue: 30,
);
const _cleanupIdleSeconds = int.fromEnvironment(
  'SP_AVATAR_ZIP_CLEANUP_IDLE_SECONDS',
  defaultValue: 10,
);
const _importSamplingHoldSeconds = 2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'profile large avatar ZIP import under strict memory',
    (tester) async {
      if (!Platform.isAndroid) {
        throw UnsupportedError('The avatar ZIP memory gate is Android-only.');
      }
      _validateDefines();

      final profile = SpAvatarBenchmarkProfile.parse(_profileName);
      final root = await Directory.systemTemp.createTemp(
        'sp-avatar-zip-memory-',
      );
      AppDatabase? db;
      String? fixtureZipSha256;
      var maximumHeartbeatGapMicros = 0;
      final importSummaries = <Map<String, Object?>>[];

      try {
        final fixture = await generateSpAvatarZipBenchmark(
          SpAvatarBenchmarkRequest(
            profile: profile,
            count: _count,
            seed: _seed,
            outputPath: '${root.path}/avatars.zip',
            appCommit: _appCommit,
          ),
        );
        fixtureZipSha256 = fixture.manifest['zipSha256']! as String;
        _emit('fixture_ready', {
          'case': _caseName,
          'profile': _profileName,
          'count': _count,
          'seed': _seed,
          'appCommit': _appCommit,
          'fixtureManifest': fixture.manifest,
        });

        db = AppDatabase(NativeDatabase.memory());
        await _seedMembersAndMappings(db, _count, _seed);
        final repository = DriftMemberRepository(db.membersDao, null);
        final importer = SpAvatarZipImporter();

        _memoryWindow('before');
        await Future<void>.delayed(const Duration(seconds: _beforeIdleSeconds));

        for (var run = 1; run <= _repetitions; run++) {
          final pulse = await _PulseMonitor.start();
          var lastProcessed = 0;
          var lastCommitted = 0;
          var maximumProcessedDelta = 0;
          var maximumCommittedDelta = 0;
          var progressEvents = 0;
          _memoryWindow('import-$run');
          _emit('import_begin', {'run': run});

          late final SpAvatarZipImportResult result;
          try {
            result = await importer.importZipFile(
              filePath: fixture.zipPath,
              memberRepo: repository,
              avatarBatchWriter: repository,
              spImportDao: db.spImportDao,
              onProgress: (progress) {
                if (progress.processedCandidates < lastProcessed ||
                    progress.committedMemberUpdates < lastCommitted) {
                  throw StateError('Avatar ZIP progress moved backwards.');
                }
                maximumProcessedDelta = max(
                  maximumProcessedDelta,
                  progress.processedCandidates - lastProcessed,
                );
                maximumCommittedDelta = max(
                  maximumCommittedDelta,
                  progress.committedMemberUpdates - lastCommitted,
                );
                lastProcessed = progress.processedCandidates;
                lastCommitted = progress.committedMemberUpdates;
                progressEvents++;
              },
            );
          } finally {
            final pulseSummary = await pulse.stop();
            maximumHeartbeatGapMicros = max(
              maximumHeartbeatGapMicros,
              pulseSummary.maximumGapMicros,
            );
            expect(
              pulseSummary.maximumGapMicros,
              lessThanOrEqualTo(500000),
              reason: 'main-isolate heartbeat exceeded 500 ms',
            );
            expect(pulseSummary.pulseCount, greaterThan(0));
          }

          expect(result.completion, SpAvatarZipImportCompletion.complete);
          expect(result.memberIdsMissingOrDeleted, isEmpty);
          expect(result.warnings, isEmpty);
          if (run == 1) {
            expect(result.memberAvatarsUpdated, _count);
            expect(result.memberAvatarsUnchanged, 0);
          } else {
            expect(result.memberAvatarsUpdated, 0);
            expect(result.memberAvatarsUnchanged, _count);
          }
          expect(lastProcessed, _count);
          // Cross-check the production worker's 32-entry chunk bound.
          expect(maximumProcessedDelta, lessThanOrEqualTo(32));
          expect(maximumCommittedDelta, lessThanOrEqualTo(32));

          final summary = <String, Object?>{
            'run': run,
            'updated': result.memberAvatarsUpdated,
            'unchanged': result.memberAvatarsUnchanged,
            'progressEvents': progressEvents,
            'maximumProcessedDelta': maximumProcessedDelta,
            'maximumCommittedDelta': maximumCommittedDelta,
            'heartbeat': pulse.lastSummary!.toJson(),
          };
          importSummaries.add(summary);
          _emit('import_end', summary);
          // Leave the marker active long enough for the external PSS sampler.
          await Future<void>.delayed(
            const Duration(seconds: _importSamplingHoldSeconds),
          );
          _memoryWindow('after-$run');
          await Future<void>.delayed(
            const Duration(seconds: _afterIdleSeconds),
          );
        }

        final stored = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM members '
              'WHERE avatar_image_data IS NOT NULL',
            )
            .getSingle();
        expect(stored.read<int>('c'), _count);
      } finally {
        await db?.close();
        if (await root.exists()) await root.delete(recursive: true);
      }

      final cacheCleaned = !await root.exists();
      expect(cacheCleaned, isTrue);
      _memoryWindow('cleanup');
      await Future<void>.delayed(const Duration(seconds: _cleanupIdleSeconds));
      _emit('benchmark_complete', {
        'case': _caseName,
        'profile': _profileName,
        'count': _count,
        'repetitions': _repetitions,
        'seed': _seed,
        'appCommit': _appCommit,
        'fixtureZipSha256': fixtureZipSha256,
        'maximumHeartbeatGapMicros': maximumHeartbeatGapMicros,
        'importSamplingHoldSeconds': _importSamplingHoldSeconds,
        'cacheCleaned': cacheCleaned,
        'imports': importSummaries,
      });
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

void _validateDefines() {
  if (_caseName.isEmpty || _appCommit.isEmpty) {
    throw StateError(
      'Benchmark case and app commit dart-defines are required.',
    );
  }
  if (_count <= 0 || _repetitions <= 0 || _seed == 0) {
    throw StateError('Count, repetitions, and non-zero seed are required.');
  }
  if (_beforeIdleSeconds < 5 ||
      _afterIdleSeconds < 30 ||
      _cleanupIdleSeconds < 5) {
    throw StateError('Strict-memory idle windows were shortened.');
  }
  if (_profileName == SpAvatarBenchmarkProfile.nearPixelLimit.cliName &&
      _count != 1) {
    throw StateError('near-pixel-limit requires count 1.');
  }
  if (_profileName == SpAvatarBenchmarkProfile.scaleSmall.cliName &&
      _count != 500 &&
      _count != 2000 &&
      _count != 5000) {
    throw StateError(
      'scale-small strict gate requires count 500, 2000, or 5000.',
    );
  }
}

Future<void> _seedMembersAndMappings(
  AppDatabase db,
  int count,
  int seed,
) async {
  const chunkSize = 500;
  for (var start = 0; start < count; start += chunkSize) {
    final end = min(start + chunkSize, count);
    await db.membersDao.batchInsertMembers([
      for (var index = start; index < end; index++)
        MembersCompanion.insert(
          id: 'prism-$index',
          name: 'Benchmark member $index',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
    ]);
    await db.spImportDao.upsertMappings([
      for (var index = start; index < end; index++)
        SpIdMapTableCompanion(
          spId: Value(_sourceId(seed, index)),
          entityType: const Value('member'),
          prismId: Value('prism-$index'),
        ),
    ]);
  }
}

String _sourceId(int seed, int index) {
  final seedHex = (seed & 0xffffffff).toRadixString(16).padLeft(8, '0');
  final indexHex = index.toRadixString(16).padLeft(16, '0');
  return '$seedHex$indexHex';
}

void _memoryWindow(String phase) =>
    _emit('memory_window', {'memoryPhase': phase});

void _emit(String event, Map<String, Object?> fields) {
  // ignore: avoid_print
  print('SP_AVATAR_ZIP_BENCHMARK ${jsonEncode({'event': event, ...fields})}');
}

class _PulseMonitor {
  _PulseMonitor._({
    required this.receivePort,
    required this.subscription,
    required this.controlPort,
    required this.clock,
    required this.readPulseCount,
    required this.readMaximumGapMicros,
  });

  final ReceivePort receivePort;
  final StreamSubscription<Object?> subscription;
  final SendPort controlPort;
  final Stopwatch clock;
  final int Function() readPulseCount;
  final int Function() readMaximumGapMicros;
  _PulseSummary? lastSummary;

  static Future<_PulseMonitor> start() async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    final clock = Stopwatch()..start();
    var lastPulseMicros = 0;
    var pulseCount = 0;
    var maximumGapMicros = 0;
    // ignore: cancel_subscriptions
    late final StreamSubscription<Object?> subscription;
    subscription = receive.listen((message) {
      if (message is SendPort) {
        lastPulseMicros = clock.elapsedMicroseconds;
        ready.complete(message);
        return;
      }
      final nowMicros = clock.elapsedMicroseconds;
      maximumGapMicros = max(maximumGapMicros, nowMicros - lastPulseMicros);
      lastPulseMicros = nowMicros;
      pulseCount++;
    });
    await Isolate.spawn(_pulseEmitter, receive.sendPort);
    return _PulseMonitor._(
      receivePort: receive,
      subscription: subscription,
      controlPort: await ready.future,
      clock: clock,
      readPulseCount: () => pulseCount,
      readMaximumGapMicros: () => maximumGapMicros,
    );
  }

  Future<_PulseSummary> stop() async {
    controlPort.send(null);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await subscription.cancel();
    receivePort.close();
    clock.stop();
    final summary = _PulseSummary(
      intervalMicros: 16000,
      pulseCount: readPulseCount(),
      maximumGapMicros: readMaximumGapMicros(),
    );
    lastSummary = summary;
    return summary;
  }
}

class _PulseSummary {
  const _PulseSummary({
    required this.intervalMicros,
    required this.pulseCount,
    required this.maximumGapMicros,
  });

  final int intervalMicros;
  final int pulseCount;
  final int maximumGapMicros;

  Map<String, Object?> toJson() => <String, Object?>{
    'intervalMicros': intervalMicros,
    'pulseCount': pulseCount,
    'maximumGapMicros': maximumGapMicros,
    'gapsAbove500ms': maximumGapMicros > 500000 ? 1 : 0,
  };
}

void _pulseEmitter(SendPort output) {
  final control = ReceivePort();
  output.send(control.sendPort);
  final timer = Timer.periodic(
    const Duration(milliseconds: 16),
    (_) => output.send(null),
  );
  control.first.whenComplete(timer.cancel);
}
