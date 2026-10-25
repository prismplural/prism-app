import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';
import 'pk_service_peer_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureValues = <String, String?>{};
  var rustInitialized = false;
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = call.arguments['key'] as String?;
            if (call.method == 'write') {
              secureValues[key!] = call.arguments['value'] as String?;
            } else if (call.method == 'read') {
              return secureValues[key];
            } else if (call.method == 'delete') {
              secureValues.remove(key);
            }
            return null;
          },
        );
    if (e2eSkip() == null) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(resolveFfiLib()),
      );
      rustInitialized = true;
    }
  });
  tearDownAll(() {
    if (rustInitialized) RustLib.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  test(
    'independent PK imports converge fronts without losing local identity or emitting Unknown repair',
    skip: e2eSkip(),
    timeout: const Timeout(Duration(minutes: 5)),
    () async {
      final relay = await spawnRelay();
      final dir = await Directory.systemTemp.createTemp('pk-service-peer-');
      E2EDevice? aDevice;
      E2EDevice? bDevice;
      PkServicePeer? a;
      PkServicePeer? b;
      const pkMember = PKMember(
        id: 'abcde',
        uuid: '11111111-2222-3333-4444-555555555555',
        name: 'Shared member',
      );
      final switches = [
        PKSwitch(
          id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          timestamp: DateTime.utc(2026, 9, 1, 12),
          members: const ['abcde'],
        ),
      ];
      try {
        aDevice = await createDevice(relay);
        bDevice = await pairNewDevice(relay, aDevice);
        a = await PkServicePeer.open(
          aDevice,
          dir,
          'a',
          SyntheticPluralKitClient(members: [pkMember], switches: switches),
        );
        b = await PkServicePeer.open(
          bDevice,
          dir,
          'b',
          SyntheticPluralKitClient(members: [pkMember], switches: switches),
        );
        await a.connectAndImport();
        await b.connectAndImport();
        final aMember = (await a.liveMembers()).single;
        final bMember = (await b.liveMembers()).single;
        expect(aMember.id, isNot(bMember.id));
        expect(aMember.pluralkitUuid, pkMember.uuid);
        expect(bMember.pluralkitUuid, pkMember.uuid);

        for (var i = 0; i < 3; i++) {
          await a.syncAndApply();
          await b.syncAndApply();
        }
        final aFronts = await a.sessions();
        final bFronts = await b.sessions();
        expect(aFronts, hasLength(1));
        expect(bFronts, hasLength(1));
        expect(aFronts.single.id, bFronts.single.id);
        expect(aFronts.single.endTime, isNull);
        expect(bFronts.single.endTime, isNull);
        expect(aFronts.every((f) => f.memberId == aMember.id), isTrue);
        expect(bFronts.every((f) => f.memberId == bMember.id), isTrue);
        expect(
          (await a.runRepair()).where((e) => e['table'] == 'fronting_sessions'),
          isEmpty,
        );
        expect(
          (await b.runRepair()).where((e) => e['table'] == 'fronting_sessions'),
          isEmpty,
        );

        final editedId = aFronts.first.id;
        await a.activate();
        await a.fronts.updateSession(
          aFronts.first.copyWith(notes: 'local peer edit'),
        );
        await a.outbox.drain(a.device.handle);
        for (var i = 0; i < 2; i++) {
          await a.syncAndApply();
          await b.syncAndApply();
        }
        final editedOnB = (await b.sessions()).singleWhere(
          (front) => front.id == editedId,
        );
        expect(editedOnB.notes, 'local peer edit');
        expect(editedOnB.memberId, bMember.id);

        final switchOutAt = DateTime.utc(2026, 9, 1, 14);
        b.client.current = PKSwitch(
          id: '99999999-8888-7777-6666-555555555555',
          timestamp: switchOutAt,
          members: const [],
        );
        await b.pollAndDrain();
        for (var i = 0; i < 3; i++) {
          await b.syncAndApply();
          await a.syncAndApply();
        }
        expect(
          (await a.sessions()).every((f) => f.memberId == aMember.id),
          isTrue,
        );
        expect(
          (await b.sessions()).every((f) => f.memberId == bMember.id),
          isTrue,
        );
        final afterPollA = await a.sessions();
        final afterPollB = await b.sessions();
        expect(afterPollA, hasLength(1));
        expect(afterPollB, hasLength(1));
        expect(afterPollA.single.id, editedId);
        expect(afterPollB.single.id, editedId);
        expect(afterPollA.single.notes, 'local peer edit');
        expect(afterPollB.single.notes, 'local peer edit');
        expect(afterPollA.single.endTime?.toUtc(), switchOutAt);
        expect(afterPollB.single.endTime?.toUtc(), switchOutAt);
        expect(b.client.calls, contains('getCurrentFronters'));
        expect(a.client.deletedMembers, isEmpty);
        expect(b.client.deletedMembers, isEmpty);
        expect(a.client.deletedSwitches, isEmpty);
        expect(b.client.deletedSwitches, isEmpty);
        expect(a.client.createdSwitchMembers, isEmpty);
        expect(b.client.createdSwitchMembers, isEmpty);
        expect(
          (await a.runRepair()).where((e) => e['table'] == 'fronting_sessions'),
          isEmpty,
        );
        expect(
          (await b.runRepair()).where((e) => e['table'] == 'fronting_sessions'),
          isEmpty,
        );
        await a.syncAndApply();
        await b.syncAndApply();
        final afterRepairA = await a.sessions();
        final afterRepairB = await b.sessions();
        expect(afterRepairA, hasLength(1));
        expect(afterRepairB, hasLength(1));
        expect(afterRepairA.single.id, editedId);
        expect(afterRepairB.single.id, editedId);
        expect(afterRepairA.single.memberId, aMember.id);
        expect(afterRepairB.single.memberId, bMember.id);
        expect(afterRepairA.single.notes, 'local peer edit');
        expect(afterRepairB.single.notes, 'local peer edit');
        expect(afterRepairA.single.endTime?.toUtc(), switchOutAt);
        expect(afterRepairB.single.endTime?.toUtc(), switchOutAt);

        await b.activate();
        await b.fronts.deleteSession(editedId);
        await b.outbox.drain(b.device.handle);
        for (var i = 0; i < 2; i++) {
          await b.syncAndApply();
          await a.syncAndApply();
        }
        expect(
          (await a.sessions()).where((front) => front.id == editedId),
          isEmpty,
        );
        expect(
          (await b.sessions()).where((front) => front.id == editedId),
          isEmpty,
        );
        expect(
          (await a.runRepair()).where((e) => e['table'] == 'fronting_sessions'),
          isEmpty,
        );
        expect(await a.quarantine.count(), 0);
        expect(await b.quarantine.count(), 0);
      } finally {
        syncCurrentHandle.value = null;
        syncCredentialsPersisted.value = false;
        await a?.close();
        await b?.close();
        aDevice?.dispose();
        bDevice?.dispose();
        relay.stop();
        await dir.delete(recursive: true);
      }
    },
  );

  for (final direction in [
    PkSyncDirection.pullOnly,
    PkSyncDirection.bidirectional,
  ]) {
    test(
      'historical PK replay preserves offline edits and tombstones on two peers '
      '(${direction.name})',
      skip: e2eSkip(),
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        final relay = await spawnRelay();
        final dir = await Directory.systemTemp.createTemp('pk-history-peer-');
        E2EDevice? aDevice;
        E2EDevice? bDevice;
        PkServicePeer? a;
        PkServicePeer? b;
        const members = [
          PKMember(id: 'old-a', uuid: 'member-uuid-a', name: 'Historical A'),
          PKMember(id: 'old-b', uuid: 'member-uuid-b', name: 'Historical B'),
          PKMember(id: 'now-c', uuid: 'member-uuid-c', name: 'Current C'),
        ];
        final history = [
          for (var i = 0; i < members.length; i++)
            PKSwitch(
              id: '00000000-0000-0000-0000-00000000000${i + 1}',
              timestamp: DateTime.utc(2026, 1, i + 1, 12),
              members: [members[i].id],
            ),
        ];
        try {
          aDevice = await createDevice(relay);
          bDevice = await pairNewDevice(relay, aDevice);
          a = await PkServicePeer.open(
            aDevice,
            dir,
            'a',
            SyntheticPluralKitClient(members: members, switches: history),
          );
          b = await PkServicePeer.open(
            bDevice,
            dir,
            'b',
            SyntheticPluralKitClient(members: members, switches: history),
          );
          a.client.current = history.last;
          b.client.current = history.last;
          await a.connectAndImport();
          await b.connectAndImport();
          for (var i = 0; i < 3; i++) {
            await a.syncAndApply();
            await b.syncAndApply();
          }
          final original = await a.fronts.getAllSessions();
          expect(original, hasLength(3));
          final oldA = original.singleWhere(
            (s) => s.pluralkitUuid == history.first.id,
          );
          final oldB = original.singleWhere(
            (s) => s.pluralkitUuid == history[1].id,
          );
          final currentId = original
              .singleWhere((s) => s.pluralkitUuid == history.last.id)
              .id;
          // Device A edits while disconnected from B; B deletes another
          // historical session. Neither mutation should become a fresh front.
          await a.activate();
          await a.fronts.updateSession(oldA.copyWith(notes: 'offline note'));
          await a.outbox.drain(a.device.handle);
          await b.activate();
          await b.fronts.deleteSession(oldB.id);
          await b.outbox.drain(b.device.handle);
          for (var i = 0; i < 3; i++) {
            await a.syncAndApply();
            await b.syncAndApply();
          }

          // Boundary checkpoint, BEFORE any cursor rewind: a peer delete
          // reaches the receiver as `is_delete` and its consumer row is
          // HARD-deleted (prism_sync_providers.dart:4954 ->
          // drift_sync_adapter.dart `hardDelete`), while the deleting device
          // keeps its soft tombstone row
          // (drift_fronting_session_repository.dart:224-245). The absorbing
          // tombstone therefore survives only in the RECEIVER's engine, which
          // is exactly why every Drift-row-based PK guard is blind there.
          expect(
            await a.fronts.getSessionById(oldB.id),
            isNull,
            reason:
                'receiver must have hard-deleted the peer-deleted row: a '
                'present row here falsifies the hardDelete boundary and moves '
                'the defect to delete push/relay instead of the PK sweep',
          );
          final bRowBeforeReplay = await b.fronts.getSessionById(oldB.id);
          expect(
            bRowBeforeReplay,
            isNotNull,
            reason: 'the deleting device keeps its soft tombstone row',
          );
          expect(
            bRowBeforeReplay!.isDeleted,
            isTrue,
            reason: 'the deleting device must still hold a tombstone',
          );
          expect(
            await a.engineTombstoned(oldB.id),
            isTrue,
            reason:
                'the receiver engine must hold the absorbing tombstone '
                'even though its consumer row is gone',
          );
          expect(
            await b.engineTombstoned(oldB.id),
            isTrue,
            reason: 'the author engine holds the tombstone it emitted',
          );

          for (final peer in [a, b]) {
            await peer.activate();
            // PK cursors are device-local. Rewind only the cursor to reproduce
            // overlapping replay after peer history has already arrived.
            await peer.db.pluralKitSyncDao.upsertSyncState(
              const PluralKitSyncStateCompanion(
                id: Value('pk_config'),
                switchCursorTimestamp: Value(null),
                switchCursorId: Value(null),
              ),
            );
            await peer.service.importSwitchesAfterLink();
            await peer.service.importSwitchesAfterLink();
            await peer.service.syncLiveFrontersOnly(direction: direction);
            await peer.outbox.drain(peer.device.handle);
          }
          for (var i = 0; i < 3; i++) {
            await a.syncAndApply();
            await b.syncAndApply();
          }

          // Role-aware tombstone checkpoint AFTER the rewind replay. The
          // engine must still say tombstoned on BOTH peers; a live receiver
          // row with a tombstoned receiver engine is an in-place revival of a
          // burned deterministic id, which can never propagate (the create's
          // `is_deleted=false` is stripped by
          // client.rs::without_phantom_undelete and rejected by the merge
          // tombstone gate on every peer).
          expect(
            await a.engineTombstoned(oldB.id),
            isTrue,
            reason:
                'replaying history must not un-tombstone the receiver '
                'engine',
          );
          expect(
            await b.engineTombstoned(oldB.id),
            isTrue,
            reason: 'replaying history must not un-tombstone the author engine',
          );
          final bRowAfterReplay = await b.fronts.getSessionById(oldB.id);
          expect(
            bRowAfterReplay,
            isNotNull,
            reason: 'the deleting device keeps its tombstone row',
          );
          expect(
            bRowAfterReplay!.isDeleted,
            isTrue,
            reason: 'the deleting device stays tombstoned through the replay',
          );
          expect(
            await a.fronts.getSessionById(oldB.id),
            isNull,
            reason:
                'RED until the burned-id guard lands: the receiver must '
                'not revive an engine-tombstoned deterministic PK session id',
          );

          for (final peer in [a, b]) {
            final sessions = await peer.fronts.getAllSessions();
            expect(sessions, hasLength(2));
            expect(
              sessions.singleWhere((s) => s.id == oldA.id).notes,
              'offline note',
            );
            expect(
              sessions.singleWhere((s) => s.id == oldA.id).endTime?.toUtc(),
              history[1].timestamp,
            );
            // The tombstone is asserted role-aware above: the receiver's
            // consumer row is hard-deleted (absent), the deleting device keeps
            // a soft tombstone. A single Drift-row expectation cannot hold for
            // both roles.
            expect(sessions.where((s) => s.endTime == null).map((s) => s.id), [
              currentId,
            ]);
            expect(peer.client.createdSwitchMembers, isEmpty);
            expect(peer.client.deletedSwitches, isEmpty);
            expect(peer.client.deletedMembers, isEmpty);
            expect(await peer.quarantine.count(), 0);
          }
        } finally {
          syncCurrentHandle.value = null;
          syncCredentialsPersisted.value = false;
          await a?.close();
          await b?.close();
          aDevice?.dispose();
          bDevice?.dispose();
          relay.stop();
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
