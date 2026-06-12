// Level-1 end-to-end: a device that went STALE and whose session EXPIRED
// while offline recovers via the signed `/session/refresh` door, with its
// locally-committed-but-unpushed ops surviving — not stranded behind a false
// `device_revoked` lockout.
//
// This drives the REAL Rust FFI (`ServerRelay::refresh_session` + the
// retry-once-on-401 path) against a REAL spawned relay, then time-travels the
// relay's own sqlite to age the device past the stale floor and expire its
// session (the Dart mirror of the Rust device-lifecycle fixture: it opens the
// spawned relay's sqlite file and runs the same UPDATEs). A subsequent
// `syncNow` must recover and flush the stranded op (pushed > 0).
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

const int _secsPerDay = 86400;

/// Mirror of the Rust device-lifecycle fixture: open the spawned relay's sqlite
/// file (the relay must be stopped first to avoid write contention) and push a
/// device's `last_seen_at` `days` into the past while flipping it to `stale`,
/// then expire its session. This reproduces "offline > 30 days, marked stale,
/// session TTL elapsed" without waiting.
void ageStaleAndExpireSession(String dbPath, String syncId, String deviceId, {int days = 31}) {
  final db = sqlite3.open(dbPath);
  try {
    final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - days * _secsPerDay;
    db.execute(
      "UPDATE devices SET last_seen_at = ?, status = 'stale' "
      'WHERE sync_id = ? AND device_id = ?',
      [past, syncId, deviceId],
    );
    expect(db.updatedRows, 1, reason: 'should age exactly one device row');
    db.execute(
      'UPDATE device_sessions SET expires_at = ? WHERE sync_id = ? AND device_id = ?',
      [past, syncId, deviceId],
    );
    expect(db.updatedRows, 1, reason: 'should expire exactly one session row');
  } finally {
    db.close();
  }
}

/// Read a device's current `status` from the relay sqlite (relay must be
/// stopped).
String deviceStatus(String dbPath, String syncId, String deviceId) {
  final db = sqlite3.open(dbPath);
  try {
    final rows = db.select(
      'SELECT status FROM devices WHERE sync_id = ? AND device_id = ?',
      [syncId, deviceId],
    );
    return rows.isEmpty ? '<absent>' : rows.first['status'] as String;
  } finally {
    db.close();
  }
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

  test(
    'a stale device with an expired session refreshes and flushes its '
    'stranded ops',
    skip: e2eSkip(),
    () async {
      // Fixed port + persistent file DB so we can stop the relay, time-travel
      // its sqlite, and bring it back on the SAME URL/state.
      final port = await findFreePort();
      final dbDir = Directory.systemTemp.createTempSync('e2e_relay_lifecycle');
      final dbPath = '${dbDir.path}/relay.db';

      var relay = await spawnRelay(port: port, dbPath: dbPath);
      E2EDevice? a;
      E2EDevice? b;
      try {
        a = await createDevice(relay);
        b = await pairNewDevice(relay, a);
        final bCreds = await credsOf(b);

        // B commits a local change but does NOT push it yet (the stranded op).
        await ffi.recordCreate(
          handle: b.handle,
          table: 'members',
          entityId: 'stranded-by-stale',
          fieldsJson: '{"name":"survivor"}',
        );

        // Time-travel: B went offline > 30 days. Stop the relay, age + stale B
        // and expire its session in the relay sqlite, then bring the relay back.
        relay.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        ageStaleAndExpireSession(dbPath, b.syncId, bCreds.deviceId);
        expect(deviceStatus(dbPath, b.syncId, bCreds.deviceId), 'stale');

        relay = await spawnRelay(port: port, dbPath: dbPath);

        // B comes back. Its session is expired, so the first signed push 401s;
        // the transport refreshes the session (signed against B's stored keys),
        // reactivates B, and retries — the stranded op flushes.
        final result = await b.sync();
        expect(
          result['error'],
          isNull,
          reason: 'a stale device must recover, not hit a false device_revoked '
              '(was: ${result['error']})',
        );
        expect(
          (result['pushed'] as int?) ?? 0,
          greaterThan(0),
          reason: 'the stranded op must flush after session refresh',
        );

        // The relay reactivated B on the recovered request.
        expect(
          deviceStatus(dbPath, b.syncId, bCreds.deviceId),
          'active',
          reason: 'a refreshed/touched stale device returns to active',
        );

        // The op actually reached the relay: A pulls it.
        final aResult = await a.sync();
        expect(
          (aResult['merged'] as int?) ?? 0,
          greaterThan(0),
          reason: "B's stranded op must propagate to A after recovery",
        );
      } finally {
        b?.dispose();
        a?.dispose();
        relay.stop();
        try {
          dbDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    },
  );
}
