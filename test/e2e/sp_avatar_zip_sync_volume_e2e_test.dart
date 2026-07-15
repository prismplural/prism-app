import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_outbox_drainer.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../tool/generate_sp_avatar_zip_benchmark.dart';
import 'e2e_fixture.dart';
import 'e2e_support.dart';

const _watchdog = Duration(minutes: 15);
const _fixtureSeed = 0x51a2cafe;
const _defaultAvatarCount = 5000;
const _countEnvironmentKey = 'SP_AVATAR_SYNC_E2E_COUNT';
const _artifactDirectoryEnvironmentKey = 'SP_AVATAR_SYNC_E2E_ARTIFACT_DIR';

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });

  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'S1 online import drains and converges at avatar ZIP sync volume',
    skip: e2eSkip(),
    () => _runSyncVolumeScenario(offlineDuringImport: false),
    timeout: const Timeout(_watchdog),
  );

  test(
    'S2 offline import remains durable then drains and converges',
    skip: e2eSkip(),
    () => _runSyncVolumeScenario(offlineDuringImport: true),
    timeout: const Timeout(_watchdog),
  );
}

Future<void> _runSyncVolumeScenario({required bool offlineDuringImport}) async {
  final count = _configuredAvatarCount();
  final gate = offlineDuringImport ? 'S2-offline-recovery' : 'S1-online';
  final tempDir = await Directory.systemTemp.createTemp(
    'sp-avatar-sync-volume-',
  );
  final port = await findFreePort();
  final relayDbPath = '${tempDir.path}/relay.db';
  var relay = await spawnRelay(port: port, dbPath: relayDbPath);
  E2EDevice? deviceA;
  E2EDevice? deviceB;
  _AppDeviceBridge? bridgeA;
  _AppDeviceBridge? bridgeB;
  final previousCredentialsPersisted = syncCredentialsPersisted.value;
  final previousCurrentHandle = syncCurrentHandle.value;
  final rss = _RssSampler()..start();

  try {
    deviceA = await createDevice(relay);
    deviceB = await pairNewDevice(relay, deviceA);
    bridgeA = await _AppDeviceBridge.open(
      device: deviceA,
      path: '${tempDir.path}/device-a.sqlite',
    );
    bridgeB = await _AppDeviceBridge.open(
      device: deviceB,
      path: '${tempDir.path}/device-b.sqlite',
    );
    await Future.wait([
      bridgeA.seedMembers(count, includeSpMappings: true),
      bridgeB.seedMembers(count, includeSpMappings: false),
    ]);

    final fixture = await generateSpAvatarZipBenchmark(
      SpAvatarBenchmarkRequest(
        profile: SpAvatarBenchmarkProfile.scaleSmall,
        count: count,
        seed: _fixtureSeed,
        outputPath: '${tempDir.path}/scale-small-$count.zip',
        appCommit: 'sp-avatar-zip-sync-volume-e2e',
      ),
    );

    syncCredentialsPersisted.value = true;
    syncCurrentHandle.value = deviceA.handle;
    // Hold dispatch until the terminal outbox volume is measured.
    SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
      db: bridgeA.db,
      drainTrigger: (_) async {},
    );

    if (offlineDuringImport) relay.stop();

    final beforeImportBytes = await bridgeA.allocatedDatabaseBytes();
    final importWatch = Stopwatch()..start();
    final importResult = await SpAvatarZipImporter().importZipFile(
      filePath: fixture.zipPath,
      memberRepo: bridgeA.memberRepository,
      avatarBatchWriter: bridgeA.memberRepository,
      spImportDao: bridgeA.db.spImportDao,
    );
    importWatch.stop();

    expect(importResult.completion, SpAvatarZipImportCompletion.complete);
    expect(importResult.memberAvatarsUpdated, count);
    expect(importResult.memberAvatarsUnchanged, 0);
    expect(importResult.memberIdsMissingOrDeleted, isEmpty);
    expect(importResult.warnings, isEmpty);

    final sourceHashes = await bridgeA.avatarHashes();
    expect(sourceHashes, hasLength(count));
    final normalizedRawBytes = await bridgeA.totalAvatarBytes();
    final outbox = await bridgeA.outboxSnapshot();
    final afterImportBytes = await bridgeA.allocatedDatabaseBytes();
    expect(outbox.rowCount, count);
    expect(outbox.updateCount, count);
    expect(outbox.avatarPayloadRawBytes, normalizedRawBytes);
    expect(outbox.quarantinedRows, 0);

    final terminalPending = await _rustPendingOps(deviceA);
    expect(
      terminalPending,
      0,
      reason: 'held app outbox must not have reached Rust before measurement',
    );

    if (offlineDuringImport) {
      relay = await spawnRelay(port: port, dbPath: relayDbPath);
    }

    final drainSamples = <int>[outbox.rowCount];
    final drainWatch = Stopwatch()..start();
    final drainPoll = Timer.periodic(const Duration(milliseconds: 25), (_) {
      unawaited(
        bridgeA!.db.syncOutboxDao.count().then((value) {
          if (drainSamples.last != value) drainSamples.add(value);
        }),
      );
    });
    try {
      await bridgeA.outboxDrainer.drain(deviceA.handle);
    } finally {
      drainPoll.cancel();
    }
    drainSamples.add(await bridgeA.db.syncOutboxDao.count());
    drainWatch.stop();
    expect(drainSamples.last, 0);
    expect(_isMonotonicNonIncreasing(drainSamples), isTrue);

    final pendingAfterOutboxDrain = await _rustPendingOps(deviceA);
    expect(pendingAfterOutboxDrain, count);

    final syncWatch = Stopwatch()..start();
    final pendingSamples = <int>[pendingAfterOutboxDrain];
    var peakRelay = _relaySnapshot(relayDbPath, deviceA.syncId);
    var appliedOnB = 0;
    var cycles = 0;
    while (true) {
      cycles++;
      final aResult = await deviceA.sync();
      expect(aResult['error'], isNull, reason: 'device A cycle $cycles');
      peakRelay = peakRelay.max(_relaySnapshot(relayDbPath, deviceA.syncId));

      final bResult = await deviceB.sync();
      expect(bResult['error'], isNull, reason: 'device B cycle $cycles');
      final drain = await drainRemoteDeliveries(
        deviceB.handle,
        db: bridgeB.db,
        syncAdapter: bridgeB.syncAdapter,
        quarantine: bridgeB.quarantine,
        strict: true,
      );
      appliedOnB += drain.rowsApplied;

      final pending = await _rustPendingOps(deviceA);
      pendingSamples.add(pending);
      expect(
        pending,
        lessThanOrEqualTo(pendingSamples[pendingSamples.length - 2]),
        reason: 'Rust pending ops must drain monotonically',
      );
      if (pending == 0 && await bridgeB.avatarCount() == count) break;
      expect(cycles, lessThan(1000), reason: 'sync made no terminal progress');
    }
    syncWatch.stop();

    final peerHashes = await bridgeB.avatarHashes();
    expect(peerHashes, sourceHashes);
    expect(await bridgeA.db.syncOutboxDao.count(), 0);
    expect(await bridgeA.db.syncQuarantineDao.count(), 0);
    expect(await bridgeB.db.syncQuarantineDao.count(), 0);
    expect(await _rustPendingOps(deviceA), 0);
    expect(await _rustPendingOps(deviceB), 0);
    expect(
      (await ffi.quarantinedBatchCount(handle: deviceA.handle)).toInt(),
      0,
    );
    expect(
      (await ffi.quarantinedBatchCount(handle: deviceB.handle)).toInt(),
      0,
    );
    expect(
      (await ffi.quarantinedPullBatchCount(handle: deviceA.handle)).toInt(),
      0,
    );
    expect(
      (await ffi.quarantinedPullBatchCount(handle: deviceB.handle)).toInt(),
      0,
    );

    rss.stop();
    final report = <String, Object?>{
      'gate': gate,
      'fixture': fixture.manifest,
      'avatarCount': count,
      'changedMemberCount': importResult.memberAvatarsUpdated,
      'normalizedRawAvatarBytes': normalizedRawBytes,
      'generatedSyncOpCount': outbox.rowCount,
      'fieldsJsonBytes': outbox.fieldsJsonBytes,
      'outboxAvatarPayloadRawBytes': outbox.avatarPayloadRawBytes,
      'outboxEstimatedStorageBytes': outbox.estimatedStorageBytes,
      'peakOutboxRows': outbox.rowCount,
      'appDatabaseAllocatedBytesBefore': beforeImportBytes,
      'appDatabaseAllocatedBytesAtTerminal': afterImportBytes,
      'appDatabaseAllocatedDeltaBytes': afterImportBytes - beforeImportBytes,
      'outboxDrainSamples': drainSamples,
      'rustPendingOpSamples': pendingSamples,
      'rustPendingOpsAtOfflineTerminal': terminalPending,
      'rustPendingOpsAfterOutboxDrain': pendingAfterOutboxDrain,
      'rustPushQuarantineCount': 0,
      'rustPullQuarantineCount': 0,
      'driftQuarantineCount': 0,
      'relayPeakBatchCount': peakRelay.batchCount,
      'relayPeakBatchBytes': peakRelay.batchBytes,
      'relayPeakStorageBytes': peakRelay.storageBytes,
      'peerRowsApplied': appliedOnB,
      'syncCycles': cycles,
      'importDurationMs': importWatch.elapsedMilliseconds,
      'outboxDrainDurationMs': drainWatch.elapsedMilliseconds,
      'syncAndPeerApplyDurationMs': syncWatch.elapsedMilliseconds,
      'hostRssBaselineBytes': rss.baselineBytes,
      'hostRssPeakBytes': rss.peakBytes,
      'hostRssPeakDeltaBytes': rss.peakBytes - rss.baselineBytes,
      'hashAlgorithm': 'sha256',
      'exactHashCount': peerHashes.length,
      'watchdogSeconds': _watchdog.inSeconds,
    };
    await _emitReport(gate, report);
  } finally {
    rss.stop();
    SyncRecordMixin.debugInstallOutboxRuntimeForTesting();
    debugDisposeOutboxDrainForTesting();
    syncCredentialsPersisted.value = previousCredentialsPersisted;
    syncCurrentHandle.value = previousCurrentHandle;
    await bridgeA?.close();
    await bridgeB?.close();
    deviceA?.dispose();
    deviceB?.dispose();
    relay.stop();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Keep the primary gate failure if a test process still owns a temp file.
    }
  }
}

int _configuredAvatarCount() {
  final raw = Platform.environment[_countEnvironmentKey];
  if (raw == null || raw.trim().isEmpty) return _defaultAvatarCount;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) {
    throw StateError('$_countEnvironmentKey must be a positive integer');
  }
  return parsed;
}

final class _AppDeviceBridge {
  _AppDeviceBridge._({
    required this.device,
    required this.db,
    required this.memberRepository,
    required this.outboxDrainer,
    required this.syncAdapter,
    required this.quarantine,
  });

  final E2EDevice device;
  final database.AppDatabase db;
  final DriftMemberRepository memberRepository;
  final SyncOutboxDrainer outboxDrainer;
  final SyncAdapterWithCompletion syncAdapter;
  final SyncQuarantineService quarantine;

  static Future<_AppDeviceBridge> open({
    required E2EDevice device,
    required String path,
  }) async {
    final db = database.AppDatabase(NativeDatabase(File(path)));
    return _AppDeviceBridge._(
      device: device,
      db: db,
      memberRepository: DriftMemberRepository(db.membersDao, device.handle),
      outboxDrainer: SyncOutboxDrainer(db),
      syncAdapter: buildSyncAdapterWithCompletion(db),
      quarantine: SyncQuarantineService(db.syncQuarantineDao),
    );
  }

  Future<void> seedMembers(int count, {required bool includeSpMappings}) async {
    await db.batch((batch) {
      for (var index = 0; index < count; index++) {
        batch.insert(
          db.members,
          database.MembersCompanion.insert(
            id: _memberId(index),
            name: 'Member $index',
            createdAt: DateTime.utc(2026, 7, 14),
          ),
        );
      }
    });
    if (!includeSpMappings) return;
    await db.spImportDao.upsertMappings([
      for (var index = 0; index < count; index++)
        database.SpIdMapTableCompanion(
          spId: Value(_spId(index)),
          entityType: const Value('member'),
          prismId: Value(_memberId(index)),
        ),
    ]);
  }

  Future<int> avatarCount() async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM members '
          'WHERE avatar_image_data IS NOT NULL',
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> totalAvatarBytes() async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(LENGTH(avatar_image_data)), 0) AS n '
          'FROM members WHERE avatar_image_data IS NOT NULL',
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<Map<String, String>> avatarHashes() async {
    final rows = await db
        .customSelect(
          'SELECT id, avatar_image_data FROM members '
          'WHERE avatar_image_data IS NOT NULL ORDER BY id',
        )
        .get();
    return <String, String>{
      for (final row in rows)
        row.read<String>('id'): sha256
            .convert(row.read<Uint8List>('avatar_image_data'))
            .toString(),
    };
  }

  Future<_OutboxSnapshot> outboxSnapshot() async {
    final rows = await db.syncOutboxDao.allInIdOrder();
    var fieldsJsonBytes = 0;
    var avatarPayloadRawBytes = 0;
    var estimatedStorageBytes = 0;
    var updateCount = 0;
    var quarantinedRows = 0;
    for (final row in rows) {
      fieldsJsonBytes += utf8.encode(row.fieldsJson).length;
      estimatedStorageBytes +=
          utf8.encode(row.entityTable).length +
          utf8.encode(row.entityId).length +
          utf8.encode(row.opType).length +
          utf8.encode(row.fieldsJson).length +
          (4 * 8) +
          1;
      if (row.opType == 'update') updateCount++;
      if (row.quarantined) quarantinedRows++;
      final fields = jsonDecode(row.fieldsJson) as Map<String, dynamic>;
      expect(fields.keys, ['avatar_image_data']);
      avatarPayloadRawBytes += base64Decode(
        fields['avatar_image_data'] as String,
      ).length;
    }
    return _OutboxSnapshot(
      rowCount: rows.length,
      updateCount: updateCount,
      fieldsJsonBytes: fieldsJsonBytes,
      avatarPayloadRawBytes: avatarPayloadRawBytes,
      estimatedStorageBytes: estimatedStorageBytes,
      quarantinedRows: quarantinedRows,
    );
  }

  Future<int> allocatedDatabaseBytes() async {
    final pageCount =
        (await db.customSelect('PRAGMA page_count').getSingle())
                .data
                .values
                .single
            as int;
    final pageSize =
        (await db.customSelect('PRAGMA page_size').getSingle())
                .data
                .values
                .single
            as int;
    return pageCount * pageSize;
  }

  Future<void> close() => db.close();
}

final class _OutboxSnapshot {
  const _OutboxSnapshot({
    required this.rowCount,
    required this.updateCount,
    required this.fieldsJsonBytes,
    required this.avatarPayloadRawBytes,
    required this.estimatedStorageBytes,
    required this.quarantinedRows,
  });

  final int rowCount;
  final int updateCount;
  final int fieldsJsonBytes;
  final int avatarPayloadRawBytes;
  final int estimatedStorageBytes;
  final int quarantinedRows;
}

final class _RelaySnapshot {
  const _RelaySnapshot({
    required this.batchCount,
    required this.batchBytes,
    required this.storageBytes,
  });

  final int batchCount;
  final int batchBytes;
  final int storageBytes;

  _RelaySnapshot max(_RelaySnapshot other) => _RelaySnapshot(
    batchCount: batchCount > other.batchCount ? batchCount : other.batchCount,
    batchBytes: batchBytes > other.batchBytes ? batchBytes : other.batchBytes,
    storageBytes: storageBytes > other.storageBytes
        ? storageBytes
        : other.storageBytes,
  );
}

_RelaySnapshot _relaySnapshot(String dbPath, String syncId) {
  final db = sqlite.sqlite3.open(dbPath, mode: sqlite.OpenMode.readOnly);
  try {
    final row = db.select(
      'SELECT COUNT(*) AS c, COALESCE(SUM(LENGTH(data)), 0) AS n '
      'FROM batches WHERE sync_id = ?',
      [syncId],
    ).single;
    return _RelaySnapshot(
      batchCount: row['c'] as int,
      batchBytes: row['n'] as int,
      storageBytes: _fileBytes(dbPath) + _fileBytes('$dbPath-wal'),
    );
  } finally {
    db.close();
  }
}

int _fileBytes(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : 0;
}

Future<int> _rustPendingOps(E2EDevice device) async {
  final status =
      jsonDecode(await ffi.status(handle: device.handle))
          as Map<String, dynamic>;
  return (status['pending_ops'] as num?)?.toInt() ?? 0;
}

bool _isMonotonicNonIncreasing(List<int> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index] > values[index - 1]) return false;
  }
  return true;
}

String _memberId(int index) => 'prism-${index.toString().padLeft(8, '0')}';

String _spId(int index) {
  final seedHex = (_fixtureSeed & 0xffffffff).toRadixString(16).padLeft(8, '0');
  final indexHex = index.toRadixString(16).padLeft(16, '0');
  return '$seedHex$indexHex';
}

final class _RssSampler {
  int baselineBytes = 0;
  int peakBytes = 0;
  Timer? _timer;

  void start() {
    baselineBytes = ProcessInfo.currentRss;
    peakBytes = baselineBytes;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final current = ProcessInfo.currentRss;
      if (current > peakBytes) peakBytes = current;
    });
  }

  void stop() {
    final current = ProcessInfo.currentRss;
    if (current > peakBytes) peakBytes = current;
    _timer?.cancel();
    _timer = null;
  }
}

Future<void> _emitReport(String gate, Map<String, Object?> report) async {
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  // ignore: avoid_print
  print('[SP_AVATAR_SYNC_VOLUME_E2E]\n$encoded');

  final directory = Platform.environment[_artifactDirectoryEnvironmentKey];
  if (directory == null || directory.trim().isEmpty) return;
  final output = Directory(directory);
  await output.create(recursive: true);
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    ':',
    '-',
  );
  await File(
    '${output.path}/$gate-$timestamp.json',
  ).writeAsString('$encoded\n');
}
