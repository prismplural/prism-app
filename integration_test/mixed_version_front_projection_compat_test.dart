// Two-checkout, two-device compatibility harness. Build old_receiver from
// v0.14.0 and new_sender from the current checkout; running old_receiver on
// current code exercises a different drain and cannot reproduce the legacy bug.
// Both devices need the same fresh PRISM_COMPAT_RUN_ID (never reuse it), a relay
// at PRISM_COMPAT_RELAY, and an external JSON KV controller at
// PRISM_COMPAT_CONTROLLER. The controller accepts PUT/GET /kv/<run>/<key>,
// returns 404 for unset keys, and releases both ready devices by setting
// controller/start to {}. Select the role with PRISM_COMPAT_ROLE and optionally
// set PRISM_COMPAT_COMPLETE_REPAIR=true on both devices for full-record repair.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'support/mixed_version_compat_support.dart';

const _oldRole = 'old_receiver';
const _newRole = 'new_sender';
const _password = 'compat-pin-0140';
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _memberId = 'compat-member';
const _frontId = 'compat-ancient-front';
final _ancientStart = DateTime.utc(2025, 6, 6, 12);
final _authoritativeEnd = _ancientStart.add(const Duration(hours: 2));
final _originalEndOriginMs = DateTime.now()
    .subtract(const Duration(minutes: 10))
    .millisecondsSinceEpoch;

Map<String, dynamic> _memberFields() => <String, dynamic>{
  'name': 'Compatibility member',
  'created_at': _ancientStart.toIso8601String(),
  'is_active': true,
  'is_deleted': false,
};

Map<String, dynamic> _frontBaseFields() => <String, dynamic>{
  'member_id': _memberId,
  'start_time': _ancientStart.toIso8601String(),
  'session_type': 0,
  'is_health_kit_import': false,
  'is_deleted': false,
};

Map<String, dynamic> _completeFrontFields() => <String, dynamic>{
  ..._frontBaseFields(),
  'end_time': _authoritativeEnd.toIso8601String(),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);
  tearDownAll(RustLib.dispose);

  test(
    'real mixed-version front projection and repair compatibility',
    () async {
      expect(
        <String>{_oldRole, _newRole},
        contains(compatRole),
        reason: 'pass --dart-define=PRISM_COMPAT_ROLE=old_receiver|new_sender',
      );

      expect(
        compatRunId.trim(),
        isNotEmpty,
        reason: 'pass a fresh --dart-define=PRISM_COMPAT_RUN_ID for both devices',
      );

      final controller = CompatController();
      ffi.PrismSyncHandle? handle;
      File? engineDbFile;
      AppDatabase? consumerDb;
      try {
        await controller.put('$compatRole/runtime-ready', <String, dynamic>{
          'role': compatRole,
          'platform': Platform.operatingSystem,
        });
        await controller.waitFor(
          'controller/start',
          timeout: const Duration(minutes: 10),
        );

        final created = await _createHandle(compatRole);
        handle = created.handle;
        engineDbFile = created.dbFile;
        if (compatRole == _oldRole) {
          consumerDb = AppDatabase(NativeDatabase.memory());
          await _runOldReceiver(controller, handle, consumerDb);
        } else {
          await _runNewSender(controller, handle);
        }
        await controller.evidence('complete', <String, dynamic>{
          'passed': true,
        });
      } finally {
        await consumerDb?.close();
        handle?.dispose();
        if (engineDbFile != null) await _deleteEngineDb(engineDbFile);
        controller.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<({ffi.PrismSyncHandle handle, File dbFile})> _createHandle(
  String role,
) async {
  final safeRun = compatRunId.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
  final dbFile = File(
    '${Directory.systemTemp.path}/prism-$safeRun-$role.sqlite3',
  );
  if (await dbFile.exists()) await dbFile.delete();
  final handle = await ffi.createPrismSync(
    relayUrl: compatRelayUrl,
    dbPath: dbFile.path,
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  return (handle: handle, dbFile: dbFile);
}

Future<void> _deleteEngineDb(File dbFile) async {
  for (final suffix in <String>['', '-wal', '-shm']) {
    final file = File('${dbFile.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

Future<Map<String, dynamic>> _sync(ffi.PrismSyncHandle handle) async {
  final result = (jsonDecode(await ffi.syncNow(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(result['error'], anyOf(isNull, ''));
  return result;
}

Future<void> _pairOld(
  CompatController controller,
  ffi.PrismSyncHandle handle,
) async {
  final created =
      (jsonDecode(
                await ffi.createSyncGroup(
                  handle: handle,
                  password: utf8.encode(_password),
                  relayUrl: compatRelayUrl,
                  mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
                ),
              )
              as Map)
          .cast<String, dynamic>();
  await ffi.configureEngine(handle: handle);
  await controller.put('old/group-ready', <String, dynamic>{'ready': true});

  final token = await controller.waitFor('new/joiner-token');
  final init =
      (jsonDecode(
                await ffi.startInitiatorCeremony(
                  handle: handle,
                  tokenBytes: (token['token_bytes'] as List).cast<int>(),
                ),
              )
              as Map)
          .cast<String, dynamic>();
  await controller.put('old/init-ready', <String, dynamic>{
    'sas_words': init['sas_word_list'],
    'joiner_device_id': init['joiner_device_id'],
  });
  await controller.waitFor('new/sas-ok');
  await ffi.uploadPairingSnapshot(
    handle: handle,
    ttlSecs: BigInt.from(86400),
    forDeviceId: init['joiner_device_id'] as String,
  );
  await controller.put('old/snapshot-uploaded', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('new/complete-started');
  await controller.put('old/complete-started', <String, dynamic>{
    'ready': true,
  });
  await ffi.completeInitiatorCeremony(
    handle: handle,
    password: utf8.encode(_password),
    mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
  );
  await controller.put('old/pair-complete', <String, dynamic>{
    'sync_id_matches': created['sync_id'] is String,
  });
  await controller.waitFor('new/bootstrap-complete');
  await _sync(handle);
  await controller.put('old/settled', <String, dynamic>{'ready': true});
  await controller.waitFor('new/settled');
  await _sync(handle);
}

Future<void> _pairNew(
  CompatController controller,
  ffi.PrismSyncHandle handle,
) async {
  await controller.waitFor('old/group-ready');
  final joiner =
      (jsonDecode(await ffi.startJoinerCeremony(handle: handle)) as Map)
          .cast<String, dynamic>();
  await controller.put('new/joiner-token', <String, dynamic>{
    'token_bytes': joiner['token_bytes'],
  });
  final expected = await controller.waitFor('old/init-ready');
  final actual = (jsonDecode(await ffi.getJoinerSas(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(actual['sas_word_list'], expected['sas_words']);
  await controller.put('new/sas-ok', <String, dynamic>{'matched': true});
  await controller.waitFor('old/snapshot-uploaded');
  await controller.put('new/complete-started', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('old/complete-started');
  await ffi.completeJoinerCeremony(
    handle: handle,
    password: utf8.encode(_password),
  );
  await ffi.configureEngine(handle: handle);
  final restored = await ffi.bootstrapFromSnapshot(handle: handle);
  await ffi.acknowledgeSnapshotApplied(handle: handle);
  await controller.put('new/bootstrap-complete', <String, dynamic>{
    'restored_count': restored.toString(),
  });
  await controller.waitFor('old/settled');
  await _sync(handle);
  await controller.put('new/settled', <String, dynamic>{'ready': true});
}

Future<DrainResult> _syncAndDrainOld(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
  SyncAdapterWithCompletion adapter,
  SyncQuarantineService quarantine,
) async {
  await _sync(handle);
  return drainRemoteDeliveries(
    handle,
    db: db,
    syncAdapter: adapter,
    quarantine: quarantine,
    strict: true,
  );
}

Future<int> _journalCount(ffi.PrismSyncHandle handle) async {
  final chunk =
      (jsonDecode(await ffi.takeUndeliveredChanges(handle: handle, limit: 1000))
              as Map)
          .cast<String, dynamic>();
  return (chunk['deliveries'] as List? ?? const []).length;
}

Future<void> _runOldReceiver(
  CompatController controller,
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) async {
  await _pairOld(controller, handle);
  final adapter = buildSyncAdapterWithCompletion(db);
  final quarantine = SyncQuarantineService(db.syncQuarantineDao);

  await controller.waitFor('new/member-pushed');
  await _syncAndDrainOld(handle, db, adapter, quarantine);
  await controller.put('old/member-observed', <String, dynamic>{'ready': true});

  await controller.waitFor('new/end-pushed');
  final endDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  final endWinner = await ffi.readFieldValue(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    field: 'end_time',
  );
  expect(endWinner, jsonEncode(_authoritativeEnd.toIso8601String()));
  expect(await db.select(db.frontingSessions).get(), isEmpty);
  expect(await _journalCount(handle), 0);
  await controller.evidence('sparse-end-acked', <String, dynamic>{
    'engine_end_correct': true,
    'consumer_row_absent': true,
    'rows_applied': endDrain.rowsApplied,
    'journal_empty': true,
  });
  await controller.put('old/end-observed', <String, dynamic>{'ready': true});

  await controller.waitFor('new/base-pushed');
  final baseDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  var row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime, isNull);
  expect(
    (await db.frontingSessionsDao.getActiveSessions()).map((item) => item.id),
    contains(_frontId),
  );
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    jsonEncode(_authoritativeEnd.toIso8601String()),
  );
  await controller.evidence('red-projection', <String, dynamic>{
    'engine_end_correct': true,
    'consumer_end_missing': true,
    'consumer_active': true,
    'rows_applied': baseDrain.rowsApplied,
    'journal_empty': await _journalCount(handle) == 0,
  });
  await controller.put('old/red-observed', <String, dynamic>{'ready': true});

  await controller.waitFor('new/agreement-replay-pushed');
  final replayDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime, isNull);
  expect(replayDrain.rowsApplied, 0);
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    jsonEncode(_authoritativeEnd.toIso8601String()),
  );
  await controller.evidence('agreement-replay', <String, dynamic>{
    'consumer_still_wrong': true,
    'rows_applied': replayDrain.rowsApplied,
    'journal_empty': await _journalCount(handle) == 0,
  });
  await controller.put('old/agreement-replay-observed', <String, dynamic>{
    'ready': true,
  });

  await controller.waitFor('new/fresh-end-pushed');
  final repairDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime?.toUtc(), _authoritativeEnd);
  expect(
    (await db.frontingSessionsDao.getActiveSessions()).map((item) => item.id),
    isNot(contains(_frontId)),
  );
  await controller.evidence('manual-fresh-end-repair', <String, dynamic>{
    'repair_mode': compatCompleteRepair ? 'complete_record' : 'end_only',
    'consumer_end_repaired': true,
    'consumer_inactive': true,
    'rows_applied': repairDrain.rowsApplied,
  });
  await controller.put('old/fresh-end-observed', <String, dynamic>{
    'ready': true,
  });

  final repository = DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    handle,
  );
  final current = await repository.getSessionById(_frontId);
  expect(current, isNotNull);
  final captured = <CapturedSyncOp>[];
  await SyncRecordMixin.suppressAndCapture(
    () => repository.updateSession(current!.copyWith(endTime: null)),
    captured.add,
  );
  expect(captured, hasLength(1));
  expect(captured.single.opType, SyncRecordOpType.update);
  expect(captured.single.fields, <String, dynamic>{'end_time': null});
  await ffi.recordUpdate(
    handle: handle,
    table: captured.single.table,
    entityId: captured.single.entityId,
    changedFieldsJson: jsonEncode(captured.single.fields),
  );
  row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime, isNull);
  expect(
    (await db.frontingSessionsDao.getActiveSessions()).map((item) => item.id),
    contains(_frontId),
  );
  final openPush = await _sync(handle);
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    'null',
  );
  await controller.put('old/open-pushed', <String, dynamic>{
    'pushed': syncCount(openPush, 'pushed'),
  });

  await controller.waitFor('new/stale-end-pushed');
  final staleDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  expect(staleDrain.rowsApplied, 0);
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    'null',
  );
  row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime, isNull);
  expect(
    (await db.frontingSessionsDao.getActiveSessions()).map((item) => item.id),
    contains(_frontId),
  );
  await controller.evidence('stale-end-control', <String, dynamic>{
    'authoritative_open_preserved': true,
    'rows_applied': staleDrain.rowsApplied,
  });
  await controller.put('old/stale-end-observed', <String, dynamic>{
    'ready': true,
  });

  await controller.waitFor('new/unsafe-fresh-end-pushed');
  final unsafeDrain = await _syncAndDrainOld(handle, db, adapter, quarantine);
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    jsonEncode(_authoritativeEnd.toIso8601String()),
  );
  row = await (db.select(
    db.frontingSessions,
  )..where((candidate) => candidate.id.equals(_frontId))).getSingle();
  expect(row.endTime?.toUtc(), _authoritativeEnd);
  expect(
    (await db.frontingSessionsDao.getActiveSessions()).map((item) => item.id),
    isNot(contains(_frontId)),
  );
  await controller.evidence('fresh-end-conflict', <String, dynamic>{
    'authoritative_open_clobbered': true,
    'rows_applied': unsafeDrain.rowsApplied,
  });
  await controller.put('old/unsafe-fresh-end-observed', <String, dynamic>{
    'ready': true,
  });
}

Future<void> _runNewSender(
  CompatController controller,
  ffi.PrismSyncHandle handle,
) async {
  await _pairNew(controller, handle);

  await ffi.recordCreate(
    handle: handle,
    table: 'members',
    entityId: _memberId,
    fieldsJson: jsonEncode(_memberFields()),
  );
  await _sync(handle);
  await controller.put('new/member-pushed', <String, dynamic>{'ready': true});
  await controller.waitFor('old/member-observed');

  await ffi.recordUpdateAt(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    changedFieldsJson: jsonEncode(<String, dynamic>{
      'end_time': _authoritativeEnd.toIso8601String(),
    }),
    originTimestampMs: _originalEndOriginMs,
  );
  await _sync(handle);
  await controller.put('new/end-pushed', <String, dynamic>{'ready': true});
  await controller.waitFor('old/end-observed');

  await ffi.recordCreate(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    fieldsJson: jsonEncode(_frontBaseFields()),
  );
  await _sync(handle);
  await controller.put('new/base-pushed', <String, dynamic>{'ready': true});
  await controller.waitFor('old/red-observed');

  await ffi.recordReconcile(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    fieldsJson: jsonEncode(_completeFrontFields()),
    divergentFreshHlc: false,
  );
  final replay = await _sync(handle);
  expect(syncCount(replay, 'pushed'), 0);
  await controller.put('new/agreement-replay-pushed', <String, dynamic>{
    'pushed': syncCount(replay, 'pushed'),
  });
  await controller.waitFor('old/agreement-replay-observed');

  await ffi.recordUpdate(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    changedFieldsJson: jsonEncode(
      compatCompleteRepair
          ? _completeFrontFields()
          : <String, dynamic>{'end_time': _authoritativeEnd.toIso8601String()},
    ),
  );
  await _sync(handle);
  await controller.put('new/fresh-end-pushed', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('old/fresh-end-observed');

  await controller.waitFor('old/open-pushed');
  await _sync(handle);
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    'null',
  );
  await controller.evidence('open-conflict-observed', <String, dynamic>{
    'authoritative_open_observed': true,
  });

  await ffi.recordUpdateAt(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    changedFieldsJson: jsonEncode(<String, dynamic>{
      'end_time': _authoritativeEnd.toIso8601String(),
    }),
    originTimestampMs: _originalEndOriginMs,
  );
  final stale = await _sync(handle);
  expect(syncCount(stale, 'pushed'), greaterThan(0));
  expect(
    await ffi.readFieldValue(
      handle: handle,
      table: 'fronting_sessions',
      entityId: _frontId,
      field: 'end_time',
    ),
    'null',
  );
  await controller.put('new/stale-end-pushed', <String, dynamic>{
    'pushed': syncCount(stale, 'pushed'),
  });
  await controller.waitFor('old/stale-end-observed');

  await ffi.recordUpdate(
    handle: handle,
    table: 'fronting_sessions',
    entityId: _frontId,
    changedFieldsJson: jsonEncode(<String, dynamic>{
      'end_time': _authoritativeEnd.toIso8601String(),
    }),
  );
  await _sync(handle);
  await controller.put('new/unsafe-fresh-end-pushed', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('old/unsafe-fresh-end-observed');
}
