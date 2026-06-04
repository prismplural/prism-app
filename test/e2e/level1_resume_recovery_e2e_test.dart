// Level-1 end-to-end: drive the REAL Dart resume orchestration
// (`runResumeSyncNudge` from prism-app's prism_sync_providers.dart) over the
// REAL Rust FFI seams (`ffi.onResume`, `ffi.configureEngine`,
// `ffi.takeLastPanic`) against a REAL spawned relay. No fakes for the engine.
//
// Goal: reproduce-or-exonerate the field bug where a device "drops sync"
// (health flips to `disconnected` / "Relay not configured" / "Image expired")
// on a transient/ambiguous failure. The nudge's documented invariant is that a
// failed resume NEVER goes destructive — it marks transient `reconnecting`,
// reconfigures the relay, retries once, and either recovers to `healthy` or
// stays `reconnecting` (never `disconnected`). These tests exercise that exact
// decision logic against the live engine rather than a pure fake.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

/// The same all-zero-entropy BIP39 phrase the shared fixtures use. Needed for
/// `createSyncGroup`.
const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Create a device handle that has a sync group but whose engine has NOT been
/// configured. This mirrors `createDevice` in e2e_fixture.dart MINUS the
/// `configureEngine` step, so the very next `ffi.onResume` throws
/// "sync not configured" — the closest faithful analogue of the field
/// "Relay not configured" state. Returns the raw handle (caller disposes).
Future<ffi.PrismSyncHandle> _createUnconfiguredHandle(TestRelay relay) async {
  final handle = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: ':memory:',
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  final pw = utf8.encode('e2e-pin-0000');
  final mnemonic = utf8.encode(_testMnemonic);
  await ffi.createSyncGroup(
    handle: handle,
    password: pw,
    relayUrl: relay.baseUrl,
    mnemonic: Uint8List.fromList(mnemonic),
  );
  // NB: intentionally NOT calling ffi.configureEngine(handle: handle) here.
  return handle;
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

  // -------------------------------------------------------------------------
  // Case 1 — "Relay not configured" recovery (most faithful to the field bug).
  //
  // A real handle whose engine was never configured throws on the first
  // onResume. The nudge must NOT go destructive: it logs the failure, marks
  // `reconnecting`, runs the REAL `ffi.configureEngine`, retries onResume, and
  // recovers to `healthy`.
  // -------------------------------------------------------------------------
  test('resume nudge recovers an unconfigured engine to healthy (real FFI)',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    ffi.PrismSyncHandle? handle;
    try {
      handle = await _createUnconfiguredHandle(relay);
      final h = handle;

      var health = SyncHealthState.healthy;
      final logs = <String>[];
      var triggered = 0;

      await runResumeSyncNudge(
        onResume: () => ffi.onResume(handle: h),
        configureEngine: () => ffi.configureEngine(handle: h),
        triggerSync: () => triggered++,
        takeLastPanic: ffi.takeLastPanic,
        readHealth: () => health,
        setHealth: (s) => health = s,
        log: logs.add,
      );

      // Recovered: the retry-after-reconfigure path put us back to healthy.
      expect(
        health,
        equals(SyncHealthState.healthy),
        reason:
            'an unconfigured engine must recover via configureEngine + retry, '
            'never go destructive (health=$health, logs=$logs)',
      );
      // The first attempt genuinely failed before recovery (proves we didn't
      // just no-op our way to "healthy").
      expect(
        logs,
        isNotEmpty,
        reason: 'the first onResume must have failed and been logged',
      );
      expect(
        logs.first.toLowerCase(),
        contains('configured'),
        reason:
            'the captured first-attempt failure should mention the engine not '
            'being configured (was: ${logs.first})',
      );
      // markHealthy() ran, so a sync was kicked.
      expect(triggered, greaterThan(0), reason: 'recovery kicks a sync');
    } finally {
      handle?.dispose();
      relay.stop();
    }
  });

  // -------------------------------------------------------------------------
  // Case 2 — outage then restore.
  //
  // A configured, synced device. Kill the relay, run the nudge: it must NOT go
  // destructive (stays healthy or transient reconnecting — NEVER disconnected).
  // Restart the relay on the same URL+DB, run the nudge again: recover to
  // healthy.
  // -------------------------------------------------------------------------
  test('resume nudge survives a relay outage and recovers on restore',
      skip: e2eSkip(), () async {
    final port = await findFreePort();
    final dbPath = '${Directory.systemTemp.path}/'
        'e2e_resume_outage_${DateTime.now().microsecondsSinceEpoch}.db';

    var relay = await spawnRelay(port: port, dbPath: dbPath);
    E2EDevice? a;
    try {
      a = await createDevice(relay);
      await a.sync();
      final dev = a;

      var health = SyncHealthState.healthy;
      final logs = <String>[];

      // --- Outage: relay down, nudge must stay non-destructive. ---
      relay.stop();
      // Wait until the relay is ACTUALLY unreachable (not just sent a kill) so
      // onResume fails deterministically instead of racing a still-closing
      // socket — the source of load-dependent flakiness.
      await _awaitRelayDown(relay.baseUrl);

      await runResumeSyncNudge(
        onResume: () => ffi.onResume(handle: dev.handle),
        configureEngine: () => ffi.configureEngine(handle: dev.handle),
        triggerSync: () {},
        takeLastPanic: ffi.takeLastPanic,
        readHealth: () => health,
        setHealth: (s) => health = s,
        log: logs.add,
      );

      expect(
        health,
        isNot(equals(SyncHealthState.disconnected)),
        reason:
            'a relay outage must NEVER push health to disconnected '
            '(health=$health, logs=$logs)',
      );
      expect(
        health,
        anyOf(
          equals(SyncHealthState.healthy),
          equals(SyncHealthState.reconnecting),
        ),
        reason: 'outage leaves health healthy or transient reconnecting',
      );

      // --- Restore: same port + DB, nudge recovers to healthy. ---
      relay = await spawnRelay(port: port, dbPath: dbPath);
      await runResumeSyncNudge(
        onResume: () => ffi.onResume(handle: dev.handle),
        configureEngine: () => ffi.configureEngine(handle: dev.handle),
        triggerSync: () {},
        takeLastPanic: ffi.takeLastPanic,
        readHealth: () => health,
        setHealth: (s) => health = s,
        log: logs.add,
      );

      expect(
        health,
        equals(SyncHealthState.healthy),
        reason:
            'once the relay is back, the nudge must recover to healthy '
            '(health=$health, logs=$logs)',
      );
    } finally {
      a?.dispose();
      relay.stop();
    }
  });

  // -------------------------------------------------------------------------
  // TEETH CHECK — proves the test distinguishes real recovery from a stuck
  // failure. Here `configureEngine` is a no-op, so the retry after reconfigure
  // re-runs the SAME failing onResume (relay down). The nudge must end in
  // `reconnecting`, NOT healthy. If this somehow went green, the case-1/case-2
  // "healthy" assertions would be tautological.
  // -------------------------------------------------------------------------
  test('teeth: no-op reconfigure + persistent failure stays reconnecting',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    try {
      a = await createDevice(relay);
      final dev = a;
      // Kill the relay so onResume keeps failing, and make configureEngine a
      // no-op so the retry can't actually fix anything.
      relay.stop();
      await _awaitRelayDown(relay.baseUrl);

      var health = SyncHealthState.healthy;
      final logs = <String>[];

      await runResumeSyncNudge(
        onResume: () => ffi.onResume(handle: dev.handle),
        configureEngine: () async {}, // no-op: cannot recover
        triggerSync: () {},
        takeLastPanic: ffi.takeLastPanic,
        readHealth: () => health,
        setHealth: (s) => health = s,
        log: logs.add,
      );

      expect(
        health,
        equals(SyncHealthState.reconnecting),
        reason:
            'a persistent failure with a no-op reconfigure must land in '
            'reconnecting — NOT healthy, NOT disconnected (health=$health, '
            'logs=$logs)',
      );
      expect(
        health,
        isNot(equals(SyncHealthState.healthy)),
        reason: 'must not falsely report healthy when nothing recovered',
      );
      // Both attempts failed → two failure log lines.
      expect(
        logs.length,
        greaterThanOrEqualTo(2),
        reason: 'both the initial and the retry onResume should have failed',
      );
    } finally {
      a?.dispose();
      relay.stop();
    }
  });
}

/// Wait until the relay at [baseUrl] is actually unreachable. A `stop()` sends a
/// kill, but the OS may take a beat to release the socket; poll `/health` until
/// the connection fails, so a subsequent FFI network call fails deterministically
/// instead of racing a still-closing socket (load-independent).
Future<void> _awaitRelayDown(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(timeout);
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final req = await client
            .getUrl(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(milliseconds: 300));
        final resp = await req.close();
        await resp.drain<void>();
        // Still serving — wait and retry.
      } catch (_) {
        return; // Connection failed → relay is down.
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  } finally {
    client.close(force: true);
  }
}
