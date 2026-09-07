import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
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

        // A later real ongoing PK poll switches out all fronters.
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
}
