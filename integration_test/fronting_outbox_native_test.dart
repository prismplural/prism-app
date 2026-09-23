import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

const _relay = String.fromEnvironment(
  'PRISM_NATIVE_RELAY',
  defaultValue: 'http://localhost:8080',
);
const _password = 'local-integration-fixture';
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Peer {
  _Peer(this.handle, this.db);
  final ffi.PrismSyncHandle handle;
  final AppDatabase db;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  tearDownAll(RustLib.dispose);

  test(
    'real native front outbox converges in both directions without restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prism-native-outbox-',
      );
      final peers = <_Peer>[];
      try {
        for (final label in ['a', 'b']) {
          final handle = await ffi.createPrismSync(
            relayUrl: _relay,
            dbPath: '${directory.path}/$label-engine.sqlite',
            allowInsecure: true,
            schemaJson: prismSyncSchema,
          );
          final db = AppDatabase(
            NativeDatabase.createInBackground(
              File('${directory.path}/$label-app.sqlite'),
            ),
          );
          peers.add(_Peer(handle, db));
        }
        await _pair(peers[0].handle, peers[1].handle);
        for (final peer in peers) {
          peer.db.tombstoneGate = TombstoneGate.forHandle(peer.handle);
        }
        await _exercise('a-to-b', peers[0], peers[1]);
        await _exercise('b-to-a', peers[1], peers[0]);
        debugPrint(
          'NATIVE_OUTBOX_PASS bidirectional member create/delete and front start/end/delete',
        );
      } finally {
        debugDisposeOutboxDrainForTesting();
        syncCredentialsPersisted.value = false;
        syncCurrentHandle.value = null;
        for (final peer in peers) {
          peer.db.tombstoneGate = null;
          peer.handle.dispose();
          await peer.db.close();
        }
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _pair(
  ffi.PrismSyncHandle initiator,
  ffi.PrismSyncHandle joiner,
) async {
  await ffi.createSyncGroup(
    handle: initiator,
    password: utf8.encode(_password),
    relayUrl: _relay,
    mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
  );
  await ffi.configureEngine(handle: initiator);
  await ffi.setAutoSync(
    handle: initiator,
    enabled: false,
    debounceMs: BigInt.from(500),
    retryDelayMs: BigInt.from(1000),
    maxRetries: 3,
  );
  final token =
      jsonDecode(await ffi.startJoinerCeremony(handle: joiner)) as Map;
  final started =
      jsonDecode(
            await ffi.startInitiatorCeremony(
              handle: initiator,
              tokenBytes: (token['token_bytes'] as List).cast<int>(),
            ),
          )
          as Map;
  final sas = jsonDecode(await ffi.getJoinerSas(handle: joiner)) as Map;
  expect(sas['sas_word_list'], started['sas_word_list']);
  await ffi.uploadPairingSnapshot(
    handle: initiator,
    ttlSecs: BigInt.from(600),
    forDeviceId: started['joiner_device_id'] as String,
  );
  await Future.wait([
    ffi.completeJoinerCeremony(
      handle: joiner,
      password: utf8.encode(_password),
    ),
    ffi.completeInitiatorCeremony(
      handle: initiator,
      password: utf8.encode(_password),
      mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
    ),
  ]).timeout(const Duration(minutes: 2));
  await ffi.configureEngine(handle: joiner);
  await ffi.setAutoSync(
    handle: joiner,
    enabled: false,
    debounceMs: BigInt.from(500),
    retryDelayMs: BigInt.from(1000),
    maxRetries: 3,
  );
  await ffi.bootstrapFromSnapshot(handle: joiner);
  await ffi.acknowledgeSnapshotApplied(handle: joiner);
  await _checkedSync(initiator);
  await _checkedSync(joiner);
  debugPrint('NATIVE_OUTBOX paired two isolated native handles');
}

Future<void> _checkedSync(ffi.PrismSyncHandle handle) async {
  final result = jsonDecode(await ffi.syncNow(handle: handle)) as Map;
  expect(
    result['error'],
    anyOf(isNull, ''),
    reason: 'native sync must not return a soft error',
  );
}

Future<dynamic> _field(
  _Peer peer,
  String table,
  String id,
  String field,
) async {
  final raw = await ffi.readFieldValue(
    handle: peer.handle,
    table: table,
    entityId: id,
    field: field,
  );
  return raw == null ? null : jsonDecode(raw);
}

Future<void> _waitFor(Future<bool> Function() predicate, String stage) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('native outbox did not reach $stage');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _transfer(String stage, _Peer sender, _Peer receiver) async {
  final before = jsonDecode(await ffi.status(handle: sender.handle)) as Map;
  expect(
    (before['pending_ops'] as num).toInt(),
    greaterThan(0),
    reason: '$stage must enter real native pending storage',
  );
  await syncNowAfterOutboxDrain(
    db: sender.db,
    handle: sender.handle,
    reconnectWebsocket: false,
  ).timeout(const Duration(seconds: 30));
  expect(await sender.db.syncOutboxDao.count(), 0);
  final after = jsonDecode(await ffi.status(handle: sender.handle)) as Map;
  expect(
    (after['pending_ops'] as num).toInt(),
    0,
    reason: '$stage manual sync must push all native operations',
  );
  await _checkedSync(receiver.handle);
  final quarantine = SyncQuarantineService(receiver.db.syncQuarantineDao);
  await drainRemoteDeliveries(
    receiver.handle,
    db: receiver.db,
    syncAdapter: buildSyncAdapterWithCompletion(
      receiver.db,
      quarantine: quarantine,
    ),
    quarantine: quarantine,
    strict: true,
  );
  expect(await quarantine.count(), 0);
  debugPrint('NATIVE_OUTBOX $stage pushed and projected');
}

Future<void> _exercise(String label, _Peer sender, _Peer receiver) async {
  debugDisposeOutboxDrainForTesting();
  syncCredentialsPersisted.value = true;
  syncCurrentHandle.value = sender.handle;
  await triggerOutboxDrain(sender.db, sender.handle);
  final members = DriftMemberRepository(sender.db.membersDao, sender.handle);
  final fronts = DriftFrontingSessionRepository(
    sender.db.frontingSessionsDao,
    sender.handle,
  );
  final service = FrontingMutationService(
    repository: fronts,
    memberRepository: members,
    lifecycle: SessionLifecycleService(memberRepository: members),
    mutationRunner: MutationRunner.forDatabase(
      sender.db,
      onCommitted: () =>
          unawaited(triggerInstalledOutboxDrain(syncCurrentHandle.value)),
    ),
  );
  final memberId = '$label-member';
  final startTime = label == 'a-to-b'
      ? DateTime.utc(2026, 1, 1, 12)
      : DateTime.utc(2026, 1, 2, 12);
  final endTime = startTime.add(const Duration(minutes: 1));
  await members.createMember(
    Member(
      id: memberId,
      name: 'Native fixture $label',
      createdAt: DateTime.now(),
    ),
  );
  await _waitFor(
    () async =>
        await _field(sender, 'members', memberId, 'name') ==
        'Native fixture $label',
    '$label member emission',
  );
  await _transfer('$label member create', sender, receiver);
  expect(
    (await receiver.db.membersDao.getMemberById(memberId))?.name,
    'Native fixture $label',
  );

  final started = await service.startFronting([memberId], startTime: startTime);
  expect(started.isSuccess, isTrue, reason: '${started.failureOrNull}');
  final frontId = started.dataOrNull!.sessions.single.id;
  await _waitFor(
    () async =>
        await _field(sender, 'fronting_sessions', frontId, 'member_id') ==
        memberId,
    '$label front create emission',
  );
  await _transfer('$label front start', sender, receiver);
  final received = await receiver.db.frontingSessionsDao.getSessionById(
    frontId,
  );
  expect(received?.memberId, memberId);
  expect(received?.endTime, isNull);
  expect(received?.isDeleted, false);

  final ended = await service.removeCoFronter(memberId, endTime: endTime);
  expect(ended.isSuccess, isTrue, reason: '${ended.failureOrNull}');
  await _waitFor(
    () async =>
        await _field(sender, 'fronting_sessions', frontId, 'end_time') != null,
    '$label front end emission',
  );
  await _transfer('$label front end', sender, receiver);
  expect(
    (await receiver.db.frontingSessionsDao.getSessionById(frontId))?.endTime,
    isNotNull,
  );

  final fillerId = deriveGapFillerSessionId(startTime, endTime);
  final existingFiller = await sender.db.frontingSessionsDao.getSessionById(
    fillerId,
  );
  expect(
    existingFiller,
    isNull,
    reason: '$label uses a distinct gap-filler interval',
  );
  debugPrint(
    'NATIVE_OUTBOX $label delete interval=${startTime.toIso8601String()}..${endTime.toIso8601String()} existingFiller=false',
  );
  final deleted = await service.executeDeleteOption(
    sessionId: frontId,
    option: DeleteOption.delete,
    allSessions: await fronts.getAllSessions(),
  );
  expect(deleted.isSuccess, isTrue, reason: '${deleted.failureOrNull}');
  await _waitFor(
    () async =>
        await _field(sender, 'fronting_sessions', frontId, 'is_deleted') ==
        true,
    '$label front delete emission',
  );
  await _transfer('$label front delete', sender, receiver);
  expect(
    (await receiver.db.frontingSessionsDao.getSessionById(
          frontId,
        ))?.isDeleted ??
        true,
    isTrue,
  );

  await members.deleteMember(memberId);
  await _waitFor(
    () async => await _field(sender, 'members', memberId, 'is_deleted') == true,
    '$label member delete emission',
  );
  await _transfer('$label member delete', sender, receiver);
  expect(
    (await receiver.db.membersDao.getMemberById(memberId))?.isDeleted ?? true,
    isTrue,
  );
}
