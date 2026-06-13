// Real-engine e2e for the R6 tombstone-revive detector (real FFI + relay, no
// mocks). The unit tests fake `readFieldValue`; this pins the actual
// `read_field_value` JSON-encoding contract end-to-end — specifically that a
// boolean `is_deleted` field reads back as the UNQUOTED token `true`/`false`,
// which is exactly what `TombstoneGate.isTombstoned` compares against
// (`encoded.trim() != 'false'`). A drift in that encoding (e.g. quoting the
// boolean) would silently make every gate read live and break the whole
// absorbing-tombstone-revive family without any unit test noticing.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/core/sync/tombstone_revive_detector.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

const String _table = 'members';

// A create field map mirroring DriftMemberRepository.memberFields for the
// sentinel, including `is_deleted: false` exactly as the real create path does.
String _sentinelCreateFieldsJson() => jsonEncode({
      'name': 'Unknown',
      'emoji': '❔',
      'is_active': true,
      'is_deleted': false,
    });

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test('detector counts a real engine tombstone on the sentinel id; pins the '
      'unquoted-boolean read_field_value contract', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    final db = AppDatabase(NativeDatabase.memory());
    try {
      a = await createDevice(relay);

      // A creates the sentinel member, then soft-deletes it (the F21 precondition:
      // a previously-synced sentinel was deleted). The delete stamps
      // is_deleted=true in the engine's field_versions.
      await ffi.recordCreate(
        handle: a.handle,
        table: _table,
        entityId: unknownSentinelMemberId,
        fieldsJson: _sentinelCreateFieldsJson(),
      );
      await ffi.recordUpdate(
        handle: a.handle,
        table: _table,
        entityId: unknownSentinelMemberId,
        changedFieldsJson: '{"is_deleted":true}',
      );

      // Contract pin: the boolean reads back as the UNQUOTED token 'true',
      // which is what TombstoneGate compares against. (A quoted '"true"' would
      // still be !='false' and thus tombstoned, but a regression to a quoted
      // boolean would surface here.)
      expect(
        await ffi.readFieldValue(
          handle: a.handle,
          table: _table,
          entityId: unknownSentinelMemberId,
          field: 'is_deleted',
        ),
        'true',
        reason: 'the engine must encode a tombstone as the unquoted token true',
      );

      // Seed a LIVE Drift sentinel row — the diverged end state: alive locally,
      // tombstoned in the engine.
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: unknownSentinelMemberId,
              name: 'Unknown',
              createdAt: DateTime.utc(2026, 1, 1),
              isDeleted: const Value(false),
            ),
          );

      // The detector, over the REAL handle, must count the divergence.
      final detector = TombstoneRevivedRowsDetector(
        db,
        TombstoneGate.forHandle(a.handle),
      );
      final report = await detector.scan();
      expect(report.gateAvailable, isTrue);
      expect(report.sentinelMember.count, 1);
      expect(report.sentinelMember.entityIds, [unknownSentinelMemberId]);
      expect(report.totalDiverged, 1);
    } finally {
      await db.close();
      a?.dispose();
      relay.stop();
    }
  });

  test('detector reports no divergence when the engine id is live (control)',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    final db = AppDatabase(NativeDatabase.memory());
    try {
      a = await createDevice(relay);

      // A creates the sentinel and does NOT delete it — the id is live.
      await ffi.recordCreate(
        handle: a.handle,
        table: _table,
        entityId: unknownSentinelMemberId,
        fieldsJson: _sentinelCreateFieldsJson(),
      );

      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: unknownSentinelMemberId,
              name: 'Unknown',
              createdAt: DateTime.utc(2026, 1, 1),
              isDeleted: const Value(false),
            ),
          );

      final report = await TombstoneRevivedRowsDetector(
        db,
        TombstoneGate.forHandle(a.handle),
      ).scan();
      expect(report.gateAvailable, isTrue);
      expect(report.sentinelMember.count, 0);
      expect(report.totalDiverged, 0);
    } finally {
      await db.close();
      a?.dispose();
      relay.stop();
    }
  });
}
