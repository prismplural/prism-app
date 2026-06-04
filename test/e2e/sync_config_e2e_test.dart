// Phase 1 of the end-to-end FFI harness: a brand-new device configures sync
// against a REAL relay (spawned on localhost) by driving the REAL Rust FFI from
// Dart — createPrismSync -> createSyncGroup (registers + unlocks) ->
// configureEngine -> sync_now — and a sync cycle completes cleanly.
//
// This crosses the full Dart -> FFI -> Rust core -> wire -> relay seam with no
// mocks. Phase 2 builds on it to assert delete coalescing on the wire.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

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

  test('a fresh device configures sync against a real relay and runs a clean sync_now',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    ffi.PrismSyncHandle? handle;
    try {
      // 1. Open the engine/DB (in-memory) pointed at the localhost relay.
      handle = await ffi.createPrismSync(
        relayUrl: relay.baseUrl,
        dbPath: ':memory:',
        allowInsecure: true, // http:// localhost
        schemaJson: prismSyncSchema,
      );

      // 2. Create a brand-new sync group: this does live relay I/O (nonce +
      //    device registration) and unlocks the handle with the derived key.
      final invite = await ffi.createSyncGroup(
        handle: handle,
        password: utf8.encode('e2e-test-pin-9281'),
        relayUrl: relay.baseUrl,
        mnemonic: null, // auto-generate the recovery phrase
      );
      expect(invite, contains('sync_id'), reason: 'createSyncGroup returns {sync_id, relay_url}');

      // 3. Wire the relay into the engine — required before sync_now.
      await ffi.configureEngine(handle: handle);

      // 4. Run a real sync cycle against the spawned relay. A fresh group has
      //    nothing to exchange, but the pull+push round-trip must succeed.
      final resultJson = await ffi.syncNow(handle: handle);
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      expect(
        result['error'],
        isNull,
        reason: 'sync_now against the real relay should succeed: $resultJson',
      );
    } finally {
      handle?.dispose();
      relay.stop();
    }
  });

  test('bulk delete coalesces into ONE pushed batch through the real FFI',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    ffi.PrismSyncHandle? handle;
    try {
      handle = await ffi.createPrismSync(
        relayUrl: relay.baseUrl,
        dbPath: ':memory:',
        allowInsecure: true,
        schemaJson: prismSyncSchema,
      );
      await ffi.createSyncGroup(
        handle: handle,
        password: utf8.encode('e2e-test-pin-9281'),
        relayUrl: relay.baseUrl,
        mnemonic: null,
      );
      await ffi.configureEngine(handle: handle);

      // Control: three SINGLE deletes are three separate batches on the wire.
      for (final id in ['c1', 'c2', 'c3']) {
        await ffi.recordDelete(handle: handle, table: 'members', entityId: id);
      }
      final control = jsonDecode(await ffi.syncNow(handle: handle)) as Map<String, dynamic>;
      expect(control['error'], isNull, reason: 'control sync_now: $control');
      expect(control['pushed'], 3, reason: 'three single deletes => three pushed batches');

      // The payoff: five bulk deletes coalesce into ONE pushed batch — proven
      // through the whole Dart -> FFI -> core -> wire -> relay path.
      await ffi.recordDeleteMulti(
        handle: handle,
        table: 'members',
        entityIds: ['b1', 'b2', 'b3', 'b4', 'b5'],
      );
      final bulk = jsonDecode(await ffi.syncNow(handle: handle)) as Map<String, dynamic>;
      expect(bulk['error'], isNull, reason: 'bulk sync_now: $bulk');
      expect(
        bulk['pushed'],
        1,
        reason: 'five bulk deletes must coalesce into ONE batch on the wire (was: $bulk)',
      );
    } finally {
      handle?.dispose();
      relay.stop();
    }
  });
}
