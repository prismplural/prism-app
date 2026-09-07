import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';
import 'pk_service_peer_fixture.dart';

void main() {
  setUpAll(() async {
    if (e2eSkip() == null) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(resolveFfiLib()),
      );
    }
  });
  tearDownAll(() {
    if (e2eSkip() == null) RustLib.dispose();
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
        PKSwitch(
          id: 'ffffffff-1111-2222-3333-444444444444',
          timestamp: DateTime.utc(2026, 9, 1, 13),
          members: const [],
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
        await a.importAll();
        await b.importAll();
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
        expect(aFronts, isNotEmpty);
        expect(bFronts, isNotEmpty);
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

        // A later real PK poll switches out all fronters; that close must sync
        // without rewriting either peer's stable member association.
        b.client.current = PKSwitch(
          id: '99999999-8888-7777-6666-555555555555',
          timestamp: DateTime.utc(2026, 9, 1, 14),
          members: const [],
        );
        await b.activate();
        await b.service.loadState();
        // One-time import deliberately does not connect ongoing sync, so use a
        // full import with the updated history as the production service path.
        b.client.switches = [...switches, b.client.current!];
        await b.importAll();
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
