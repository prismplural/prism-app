// Pull-to-head end-to-end. A single sync must drain the ENTIRE backlog to the
// relay head — across MULTIPLE pull pages — not stop after the first page. B
// pushes more than one pull page (pull_page_limit = 500) of batches with a
// sentinel as the newest op; A must see that sentinel after ONE sync. Guards
// Fix 1 (pull-to-head): a single-page pull would miss the tail. Read on the
// puller via the real FFI (read_field_value), not just sync counts.
//
// This is the coverage hole the negative-control surfaced: the incident test
// only pushes a few hundred ops, so an incoming message lands in the first page
// whether or not pull-to-head exists. This test forces a SECOND page.
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

/// Sync repeatedly until the device has pushed its whole local backlog (a cycle
/// that pushes nothing left). The push phase is cap-bounded per cycle, so a
/// large backlog needs several cycles.
Future<void> drainPush(E2EDevice d) async {
  for (var i = 0; i < 30; i++) {
    final r = await d.sync();
    if ((r['pushed'] as int? ?? 0) == 0) return;
  }
  fail('device did not drain its push backlog within 30 cycles');
}

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test('a single sync drains the whole backlog to head across pages (pull-to-head)',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // More than one pull page (500) of batches, so draining to head REQUIRES a
      // second page. Each recordCreate is its own batch (no coalescing).
      const pad = 600;
      for (var i = 0; i < pad; i++) {
        await ffi.recordCreate(
          handle: b.handle,
          table: 'members',
          entityId: 'pad-$i',
          fieldsJson: '{"name":"p$i"}',
        );
      }
      // The sentinel is the NEWEST op → highest server_seq → only reachable by
      // pulling past the first page.
      await ffi.recordCreate(
        handle: b.handle,
        table: 'members',
        entityId: 'pull-sentinel',
        fieldsJson: '{"name":"SENTINEL"}',
      );

      await drainPush(b); // B uploads the whole backlog (several cap-bounded cycles)

      // A pulls. Pull-to-head must reach the sentinel in ONE sync; a single-page
      // pull would stop at 500 and never see it.
      await a.sync();

      final sentinel = await ffi.readFieldValue(
        handle: a.handle,
        table: 'members',
        entityId: 'pull-sentinel',
        field: 'name',
      );
      expect(
        sentinel,
        equals('"SENTINEL"'),
        reason: 'A must drain past the first pull page to head in one sync '
            '(pull-to-head); a single-page pull misses the tail. got: $sentinel',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
