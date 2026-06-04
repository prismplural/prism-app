// Chaos end-to-end: a device recovers from a relay OUTAGE. The relay is killed
// mid-life and restarted on the same URL with the same (persistent) state; the
// device's next sync recovers on its own. Drives real Rust against a real
// relay process that is actually killed and restarted.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:io';

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

  test('a device recovers after the relay goes down and comes back up',
      skip: e2eSkip(), () async {
    // Fixed port + persistent file DB so the relay can come back on the SAME
    // URL with the SAME session/data after a kill.
    final port = await findFreePort();
    final dbDir = Directory.systemTemp.createTempSync('e2e_relay_db');
    final dbPath = '${dbDir.path}/relay.db';

    var relay = await spawnRelay(port: port, dbPath: dbPath);
    E2EDevice? a;
    try {
      a = await createDevice(relay);
      await a.sync(); // establish the session + base state on the relay

      // Queue a local change to flush after recovery.
      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'survives-outage',
        fieldsJson: '{"name":"x"}',
      );

      // The relay goes DOWN.
      relay.stop();

      // A sync during the outage fails with a retryable NETWORK error (a few
      // seconds, from the inner retry loop) — distinctly NOT a revocation.
      Object? outage;
      try {
        await a.sync();
      } catch (e) {
        outage = e;
      }
      expect(outage, isNotNull, reason: 'sync during the outage must fail');
      expect(
        outage.toString(),
        isNot(contains('device_revoked')),
        reason: 'outage is a network error, not revocation (was: $outage)',
      );

      // The relay comes back on the SAME port + DB file — A's session survives.
      relay = await spawnRelay(port: port, dbPath: dbPath);

      // A recovers on its own: a plain syncNow succeeds and flushes the change
      // it queued during the outage.
      final recovered = await a.sync().timeout(const Duration(seconds: 20));
      expect(recovered['error'], isNull, reason: 'A recovered after restart: $recovered');
      expect(
        recovered['pushed'],
        greaterThanOrEqualTo(1),
        reason: 'the change queued during the outage flushed after recovery: $recovered',
      );
    } finally {
      a?.dispose();
      relay.stop();
      try {
        dbDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
