// PK-review re-emission clobber repro (real FFI, real relay, no mocks).
//
// Root-cause repro: `emitGroupSyncState` used to re-broadcast the
// ENTIRE group row (and every entry row) with FRESH HLCs after a PK review was
// dismissed. Under value-blind per-field LWW that converts field-level merge
// into a whole-row stomp — a byte-identical-but-stale local value, carried on a
// newer emit-time HLC, beats a peer's genuinely-newer un-pulled edit on a field
// the re-emitting device never touched.
//
// The fix routes the re-emission through `record_reconcile` (what
// `emitGroupSyncState` now calls per field via `syncRecordReconcile`):
//   - a field whose local value already equals this device's field_versions
//     winner emits NOTHING (the load-bearing change),
//   - a genuinely-diverged suppressed-window edit emits at a fresh HLC,
//   - a never-synced field emits at the floor backfill HLC (write-if-absent),
//     which loses to every genuine edit — and to an absorbing tombstone.
//
// These tests drive the emission primitives directly (recordReconcile /
// recordBackfill), mirroring exactly what the repository emits per field, and
// exercise the real Rust merge engine across a spawned relay.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

const String _groupTable = 'member_groups';
const String _entryTable = 'member_group_entries';
const String _groupId = 'grp-pk-1';
const String _entryId = 'entry-pk-1';

/// The full group field map `emitGroupSyncState` would reconcile (mirrors
/// `_groupFields` — the synced column set). `name` is the value the device still
/// holds locally; `description` carries any suppressed-window local edit. The
/// reconcile compares each against the device's own `field_versions` winner.
String _groupFieldsJson({required String name, String description = 'desc'}) =>
    jsonEncode({
      'name': name,
      'description': description,
      'color_hex': '#ABCDEF',
      'group_type': 0,
      'pluralkit_uuid': 'pk-group-uuid-1',
      'is_deleted': false,
    });

String _entryFieldsJson() => jsonEncode({
      'group_id': _groupId,
      'member_id': 'member-1',
      'pk_group_uuid': 'pk-group-uuid-1',
      'pk_member_uuid': 'pk-member-uuid-1',
      'is_deleted': false,
    });

Future<String?> _field(E2EDevice d, String table, String entityId, String field) =>
    ffi.readFieldValue(handle: d.handle, table: table, entityId: entityId, field: field);

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Test 1 — THE BUG. B reconciles its stale group state during a PK-review
  // dismissal while A's concurrent rename is still un-pulled. The reconcile
  // must NOT clobber A's rename (it skips the value-equal `name` field on B),
  // while B's own diverged suppressed-window edit still propagates.
  // ──────────────────────────────────────────────────────────────────────
  test('emitGroupSyncState reconcile must NOT clobber a peer\'s un-pulled rename',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // 1. A creates the group; B receives the full row.
      await ffi.recordCreate(
        handle: a.handle,
        table: _groupTable,
        entityId: _groupId,
        fieldsJson: _groupFieldsJson(name: 'Old Name'),
      );
      await a.sync();
      await b.sync();
      expect(await _field(b, _groupTable, _groupId, 'name'), '"Old Name"',
          reason: 'B should have received the group');

      // 2. A renames the group to "New Name" (a per-field patch op at a fresh
      //    HLC) but B has NOT pulled it yet — this is the suppressed-window race.
      await ffi.recordUpdate(
        handle: a.handle,
        table: _groupTable,
        entityId: _groupId,
        changedFieldsJson: '{"name":"New Name"}',
      );
      await a.sync(); // A pushes; B intentionally does not pull yet.

      // 3. B edited a DIFFERENT field (`description`) locally DURING the
      //    suppressed window — a genuine deferred edit that, because the row was
      //    sync-suppressed, never reached `record_update`, so B's field_versions
      //    still holds the pre-suppression `description` winner ("desc"). When
      //    the PK review is dismissed, emitGroupSyncState reconciles B's CURRENT
      //    full row (name still "Old Name" since B never pulled A's rename;
      //    description carries B's suppressed-window edit). Reconcile compares
      //    each field to B's field_versions winner: `name` is value-equal → it
      //    is skipped (no stale "Old Name" op ever emitted), while `description`
      //    diverges → it emits at a fresh HLC as the genuine deferred edit.
      await ffi.recordReconcile(
        handle: b.handle,
        table: _groupTable,
        entityId: _groupId,
        fieldsJson: _groupFieldsJson(
          name: 'Old Name',
          description: 'B suppressed-window desc',
        ),
        divergentFreshHlc: true,
      );

      // 4. Settle both directions.
      await b.sync();
      await a.sync();
      await b.sync();
      await a.sync();

      // A's rename survives EVERYWHERE — the reconcile skipped the value-equal
      // `name` field on B, so no stale "Old Name" op was ever emitted.
      expect(await _field(a, _groupTable, _groupId, 'name'), '"New Name"',
          reason: 'A keeps its own rename');
      expect(await _field(b, _groupTable, _groupId, 'name'), '"New Name"',
          reason: 'CLOBBER BUG would resurrect "Old Name" on B via the reconcile; '
              'reconcile must skip the value-equal name field');

      // B's genuine suppressed-window edit on a different field still reaches A.
      expect(await _field(a, _groupTable, _groupId, 'description'),
          '"B suppressed-window desc"',
          reason: 'a diverged field still emits at a fresh HLC and propagates');
      expect(await _field(b, _groupTable, _groupId, 'description'),
          '"B suppressed-window desc"');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // ──────────────────────────────────────────────────────────────────────
  // Test 2 — entry re-emission establishes membership on a peer that lacks the
  // entry (floor backfill writes-if-absent), but does NOT resurrect a peer's
  // tombstoned entry (floor backfill loses to the absorbing tombstone).
  // ──────────────────────────────────────────────────────────────────────
  test('entry reconcile establishes a missing membership but never resurrects a tombstone',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // A reconciles a never-synced entry: every field is absent on both
      // devices, so it emits at the floor backfill HLC and establishes the
      // membership group-wide.
      await ffi.recordReconcile(
        handle: a.handle,
        table: _entryTable,
        entityId: _entryId,
        fieldsJson: _entryFieldsJson(),
        divergentFreshHlc: true,
      );
      await a.sync();
      await b.sync();
      expect(await _field(b, _entryTable, _entryId, 'member_id'), '"member-1"',
          reason: 'floor backfill establishes the membership on the peer lacking it');

      // B tombstones the entry (the absorbing delete).
      await ffi.recordDelete(handle: b.handle, table: _entryTable, entityId: _entryId);
      await b.sync();
      await a.sync();
      await b.sync();
      await a.sync();
      expect(await _field(a, _entryTable, _entryId, 'is_deleted'), 'true',
          reason: 'A converged on B\'s tombstone');

      // A re-runs the SAME reconcile (a later PK-review dismissal would do this).
      // Its fields now value-equal A's own field_versions OR are gated by the
      // tombstone; either way it cannot un-delete the entry on any device.
      await ffi.recordReconcile(
        handle: a.handle,
        table: _entryTable,
        entityId: _entryId,
        fieldsJson: _entryFieldsJson(),
        divergentFreshHlc: true,
      );
      await a.sync();
      await b.sync();
      await a.sync();
      await b.sync();

      expect(await _field(b, _entryTable, _entryId, 'is_deleted'), 'true',
          reason: 'RESURRECTION BUG: the re-emission must not revive a tombstoned entry');
      expect(await _field(a, _entryTable, _entryId, 'is_deleted'), 'true',
          reason: 'the re-emission must not un-delete locally either');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
