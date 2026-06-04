// Cross-device end-to-end: two real handles, paired via the real ceremony,
// exchanging records through a real relay. No mocks anywhere.
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

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test('two devices pair, and a create on A propagates to B', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a); // asserts B joined A's group + SAS match

      // A creates a member and pushes it.
      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-conv-1',
        fieldsJson: '{"name":"Alice"}',
      );
      final aPush = await a.sync();
      expect(aPush['error'], isNull, reason: 'A push: $aPush');
      expect(aPush['pushed'], greaterThanOrEqualTo(1), reason: 'A should push the create');

      // B pulls it from the relay and merges it — cross-device delivery over
      // the real wire.
      final bPull = await b.sync();
      expect(bPull['error'], isNull, reason: 'B pull: $bPull');
      expect(
        bPull['merged'],
        greaterThanOrEqualTo(1),
        reason: 'B should pull + merge A\'s create (was: $bPull)',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  test('bulk delete coalesces on the wire AND converges across devices',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // A creates five members; B receives them.
      for (var i = 0; i < 5; i++) {
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: 'mb-$i',
          fieldsJson: '{"name":"M$i"}',
        );
      }
      await a.sync();
      final bCreates = await b.sync();
      expect(bCreates['merged'], greaterThanOrEqualTo(5), reason: 'B gets 5 creates: $bCreates');

      // A bulk-deletes all five — ONE coalesced batch on the wire (Fix 3)...
      await ffi.recordDeleteMulti(
        handle: a.handle,
        table: 'members',
        entityIds: ['mb-0', 'mb-1', 'mb-2', 'mb-3', 'mb-4'],
      );
      final aDelete = await a.sync();
      expect(aDelete['pushed'], 1, reason: 'five deletes => one pushed batch: $aDelete');

      // ...and B converges on all five tombstones from that single batch.
      final bDeletes = await b.sync();
      expect(
        bDeletes['merged'],
        greaterThanOrEqualTo(5),
        reason: 'B merges 5 tombstones from the one coalesced batch (was: $bDeletes)',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
