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

/// Mirror of the Rust 90d auto-revoke cleanup pass: age a device
/// `days` into the past, flip it to `revoked`, and flag the group `needs_rekey`
/// — exactly the relay-side state that used to deadlock standalone rekey AND
/// new-device pairing forever. The relay must be stopped before calling.
void ageOfflineAndAutoRevoke(String dbPath, String syncId, String deviceId, {int days = 91}) {
  final db = sqlite3.open(dbPath);
  try {
    final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - days * _secsPerDay;
    db.execute(
      "UPDATE devices SET last_seen_at = ?, status = 'revoked', revoked_at = ? "
      'WHERE sync_id = ? AND device_id = ?',
      [past, past, syncId, deviceId],
    );
    expect(db.updatedRows, 1, reason: 'should auto-revoke exactly one device row');
    db.execute(
      'UPDATE sync_groups SET needs_rekey = 1 WHERE sync_id = ?',
      [syncId],
    );
    expect(db.updatedRows, 1, reason: 'should flag exactly one group needs_rekey');
  } finally {
    db.close();
  }
}

/// Read a group's `needs_rekey` flag (0/1) from the relay sqlite.
int groupNeedsRekey(String dbPath, String syncId) {
  final db = sqlite3.open(dbPath);
  try {
    final rows = db.select('SELECT needs_rekey FROM sync_groups WHERE sync_id = ?', [syncId]);
    return rows.isEmpty ? -1 : rows.first['needs_rekey'] as int;
  } finally {
    db.close();
  }
}

/// Read a group's `current_epoch` from the relay sqlite.
int groupEpoch(String dbPath, String syncId) {
  final db = sqlite3.open(dbPath);
  try {
    final rows = db.select('SELECT current_epoch FROM sync_groups WHERE sync_id = ?', [syncId]);
    return rows.isEmpty ? -1 : rows.first['current_epoch'] as int;
  } finally {
    db.close();
  }
}

/// Count rekey artifacts stored for a target device at a given epoch.
int rekeyArtifactCount(String dbPath, String syncId, int epoch, String deviceId) {
  final db = sqlite3.open(dbPath);
  try {
    final rows = db.select(
      'SELECT COUNT(*) AS n FROM rekey_artifacts '
      'WHERE sync_id = ? AND epoch = ? AND target_device_id = ?',
      [syncId, epoch, deviceId],
    );
    return rows.first['n'] as int;
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

  test(
    'F29: pairing a new device succeeds after a 90d auto-revoke left the group '
    'needs_rekey (was a permanent deadlock)',
    skip: e2eSkip(),
    () async {
      final port = await findFreePort();
      final dbDir = Directory.systemTemp.createTempSync('e2e_relay_f29');
      final dbPath = '${dbDir.path}/relay.db';

      var relay = await spawnRelay(port: port, dbPath: dbPath);
      E2EDevice? a;
      E2EDevice? b;
      E2EDevice? c;
      try {
        a = await createDevice(relay);
        b = await pairNewDevice(relay, a);
        final bCreds = await credsOf(b);

        // B abandons the group: stop the relay, mirror the 90d auto-revoke
        // (B -> revoked, group flagged needs_rekey, no epoch bump), restart.
        relay.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final epochBefore = groupEpoch(dbPath, a.syncId);
        ageOfflineAndAutoRevoke(dbPath, a.syncId, bCreds.deviceId);
        expect(deviceStatus(dbPath, a.syncId, bCreds.deviceId), 'revoked');
        expect(groupNeedsRekey(dbPath, a.syncId), 1, reason: 'group owes a forced rekey');

        relay = await spawnRelay(port: port, dbPath: dbPath);

        // Pair a NEW device C. complete_bootstrap_initiator runs the standalone
        // post_prepared_rekey that the stuck needs_rekey flag used to 409
        // forever. After the cleanup it must succeed.
        c = await pairNewDevice(relay, a);
        final cCreds = await credsOf(c);

        // Stop the relay to read its sqlite consistently.
        relay.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // The flag cleared and the epoch advanced past the pre-pairing value.
        expect(
          groupNeedsRekey(dbPath, a.syncId),
          0,
          reason: 'pairing rekey must clear needs_rekey',
        );
        final epochAfter = groupEpoch(dbPath, a.syncId);
        expect(
          epochAfter,
          greaterThan(epochBefore),
          reason: 'pairing rekey advanced the epoch',
        );

        // C is active; B stays revoked with NO artifact for the new epoch (the
        // auto-revoked device never receives a post-revocation epoch key).
        expect(deviceStatus(dbPath, a.syncId, cCreds.deviceId), 'active');
        expect(deviceStatus(dbPath, a.syncId, bCreds.deviceId), 'revoked');
        expect(
          rekeyArtifactCount(dbPath, a.syncId, epochAfter, bCreds.deviceId),
          0,
          reason: 'revoked B must have no wrapped key at the post-pairing epoch',
        );
      } finally {
        c?.dispose();
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
