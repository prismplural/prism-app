// Robustness / regression end-to-end tests, two real devices over a real relay.
// These lock in the fixes from the bulk-delete-flood investigation at the
// highest level: a device with a huge outbound backlog stays responsive to
// incoming changes, and the backlog drains on its own.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

// Mirrors DEFAULT_PUSH_BATCH_CAP in prism-sync-core (the per-cycle push cap).
const int _pushBatchCap = 256;

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test('a huge push backlog does NOT make a device deaf to incoming changes',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // A queues a large outbound backlog: more delete batches than the
      // per-cycle push cap, so a single cycle can't drain them.
      const floodCount = _pushBatchCap + 44; // 300
      for (var i = 0; i < floodCount; i++) {
        await ffi.recordDelete(handle: a.handle, table: 'members', entityId: 'flood-$i');
      }

      // Meanwhile B sends a message and gets it onto the relay.
      await ffi.recordCreate(
        handle: b.handle,
        table: 'members',
        entityId: 'msg-1',
        fieldsJson: '{"name":"ping"}',
      );
      final bPush = await b.sync();
      expect(bPush['pushed'], greaterThanOrEqualTo(1), reason: 'B pushes its message: $bPush');

      // A's first cycle after the flood: it can only PUSH a capped slice (Fix 2:
      // cap-push-per-cycle), but it PULLS first (Fix 1: pull-to-head before
      // push) — so it still RECEIVES B's message instead of going deaf behind
      // its own backlog. This is the exact regression we shipped fixes for.
      final aFirst = await a.sync();
      expect(aFirst['error'], isNull, reason: 'A sync: $aFirst');
      expect(aFirst['pushed'], _pushBatchCap, reason: 'push capped per cycle: $aFirst');
      expect(aFirst['push_incomplete'], isTrue, reason: 'A still has backlog: $aFirst');
      expect(
        aFirst['merged'],
        greaterThanOrEqualTo(1),
        reason: 'A stayed responsive — got B\'s message despite the backlog (was: $aFirst)',
      );

      // And the backlog drains on its own across the next cycle(s).
      var result = aFirst;
      var guard = 0;
      while (result['push_incomplete'] == true && guard++ < 6) {
        result = await a.sync();
        expect(result['error'], isNull, reason: 'drain cycle: $result');
      }
      expect(result['push_incomplete'], isFalse, reason: 'backlog fully drains: $result');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  test('records sync in BOTH directions between paired devices',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // A -> B
      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'from-a',
        fieldsJson: '{"name":"A"}',
      );
      await a.sync();
      final bGotA = await b.sync();
      expect(bGotA['merged'], greaterThanOrEqualTo(1), reason: 'B receives A\'s record: $bGotA');

      // B -> A
      await ffi.recordCreate(
        handle: b.handle,
        table: 'members',
        entityId: 'from-b',
        fieldsJson: '{"name":"B"}',
      );
      await b.sync();
      final aGotB = await a.sync();
      expect(aGotB['merged'], greaterThanOrEqualTo(1), reason: 'A receives B\'s record: $aGotB');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  test('A revokes B; B\'s next sync reports device_revoked, A keeps working',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      final aCreds = await credsOf(a);
      final bCreds = await credsOf(b);

      // A revokes B — rekeys the group and posts the revocation to the relay.
      await ffi.revokeDevice(
        handle: a.handle,
        syncId: a.syncId,
        deviceId: aCreds.deviceId,
        sessionToken: aCreds.sessionToken,
        targetDeviceId: bCreds.deviceId,
      );

      // B's next sync is rejected at the relay's auth layer — syncNow THROWS
      // (it does NOT return an error JSON), surfacing device_revoked.
      Object? caught;
      try {
        await b.sync();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'a revoked device must fail syncNow');
      expect(
        caught.toString(),
        contains('device_revoked'),
        reason: 'B should see device_revoked (was: $caught)',
      );

      // A — the surviving device — still syncs cleanly on the new epoch.
      final aAfter = await a.sync();
      expect(aAfter['error'], isNull, reason: 'A still works post-revoke: $aAfter');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
