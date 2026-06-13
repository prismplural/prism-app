import 'package:flutter/foundation.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';

/// Diagnostic-only detector for the absorbing-tombstone-revive-holes divergence.
///
/// Installs that triggered the revive holes before the ingress gates landed hold
/// a row alive in Drift while their OWN Rust `field_versions` record
/// `is_deleted=true` for that row's current entity id — and every peer holds a
/// permanent tombstone. Fixing the ingress paths stops NEW divergence but cannot
/// heal those already-split rows: edits to them are silently dropped fleet-wide.
///
/// This service only DETECTS and COUNTS that divergence. It performs **no**
/// repair, emits **no** ops, and never auto-runs — historical divergence is
/// owned by the planned reconciliation layer. The counts surface in the
/// release-gated diagnostics screen so a maintainer can see whether an install
/// is affected before the reconciliation work ships.
///
/// A row is "diverged" when it is LIVE in Drift but
/// `TombstoneGate.isTombstoned(table, currentEntityId)` is true: the engine's
/// merged state burned the id the row would emit/delete under, so the row is
/// invisible to peers. `currentEntityId` is computed exactly as the repository's
/// emit path computes it (generation-aware), so the detector and the live emit
/// path agree on which id is being targeted.
class TombstoneRevivedRowsDetector {
  TombstoneRevivedRowsDetector(
    this._db,
    this._gate, {
    bool engineConfigured = true,
  }) : _engineConfigured = engineConfigured;

  final AppDatabase _db;

  /// The tombstone gate over the live engine's `field_versions`, or `null` when
  /// no engine handle is wired (pre-pairing). A null gate reports nothing
  /// tombstoned, so [scan] returns an all-zero, `gateAvailable=false` report
  /// rather than a misleading "no divergence" result.
  final TombstoneGate? _gate;

  /// Whether the engine is actually CONFIGURED (has a `sync_id`), not merely
  /// constructed. The FFI `read_field_value` returns `null` for EVERY id when
  /// the engine is unconfigured, so a present-but-unconfigured handle would
  /// otherwise report an all-clean scan with `gateAvailable=true` — the exact
  /// false-negative the flag exists to prevent. When `false`, [scan] reports
  /// `gateAvailable=false` even though a gate object exists. The caller
  /// (provider) sources this from sync health; tests default it to `true`.
  final bool _engineConfigured;

  static const String _groupTable = 'member_groups';
  static const String _entryTable = 'member_group_entries';
  static const String _memberTable = 'members';

  /// Scan the deterministic-id surfaces and count the Drift-live rows whose
  /// current incarnation id is tombstoned in the engine. Read-only: no Drift
  /// write, no sync emission.
  Future<TombstoneRevivedRowsReport> scan() async {
    final gate = _gate;
    if (gate == null || !_engineConfigured) {
      // No engine to consult (no handle, or a handle whose engine has no
      // sync_id yet): every `read_field_value` would return null, so a scan
      // would falsely report zero divergence. Surface `gateAvailable=false`
      // instead.
      return const TombstoneRevivedRowsReport(
        gateAvailable: false,
        groups: TombstoneRevivedTableResult.empty,
        entries: TombstoneRevivedTableResult.empty,
        sentinelMember: TombstoneRevivedTableResult.empty,
      );
    }

    final groups = await _scanGroups(gate);
    final entries = await _scanEntries(gate);
    final sentinel = await _scanSentinelMember(gate);

    return TombstoneRevivedRowsReport(
      gateAvailable: true,
      groups: groups,
      entries: entries,
      sentinelMember: sentinel,
    );
  }

  /// member_groups rows that are LIVE in Drift, carry a `pluralkit_uuid`, and
  /// whose generation-aware canonical entity id is tombstoned.
  Future<TombstoneRevivedTableResult> _scanGroups(TombstoneGate gate) async {
    final rows = await _db.memberGroupsDao.getAllGroupsIncludingDeleted();
    final diverged = <String>[];
    for (final row in rows) {
      if (row.isDeleted) continue;
      final pkUuid = row.pluralkitUuid;
      if (pkUuid == null || pkUuid.isEmpty) continue;
      final entityId = deriveGroupIncarnationEntityId(pkUuid, row.syncGeneration);
      if (await gate.isTombstoned(_groupTable, entityId)) {
        diverged.add(entityId);
      }
    }
    return TombstoneRevivedTableResult(table: _groupTable, entityIds: diverged);
  }

  /// member_group_entries rows that are LIVE in Drift, resolve to a PK-backed
  /// entry entity id, and whose generation-aware id is tombstoned.
  ///
  /// The PK refs are resolved exactly as the repository emit path's
  /// `_entryEntityIdFromStoredEntry` does: the entry's own `pkGroupUuid` /
  /// `pkMemberUuid` when present, ELSE a fallback to the joined group's and
  /// member's `pluralkitUuid`. Legacy rows that lack entry-level refs but whose
  /// group/member are PK-linked emit (and can diverge) under the deterministic
  /// sha id, so the detector must see them too. Group/member uuids are
  /// pre-loaded into maps to keep the scan O(entries) rather than N+1.
  Future<TombstoneRevivedTableResult> _scanEntries(TombstoneGate gate) async {
    final groupUuidById = <String, String?>{
      for (final g in await _db.memberGroupsDao.getAllGroupsIncludingDeleted())
        g.id: g.pluralkitUuid,
    };
    final memberUuidById = <String, String?>{
      for (final m in await _db.membersDao.getAllMembersIncludingDeleted())
        m.id: m.pluralkitUuid,
    };

    final rows = await _db.memberGroupsDao.getAllEntriesIncludingDeleted();
    final diverged = <String>[];
    for (final row in rows) {
      if (row.isDeleted) continue;
      final pkGroupUuid = row.pkGroupUuid ?? groupUuidById[row.groupId];
      final pkMemberUuid = row.pkMemberUuid ?? memberUuidById[row.memberId];
      final entityId = deriveEntryIncarnationEntityId(
        pkGroupUuid,
        pkMemberUuid,
        row.syncGeneration,
      );
      // Non-PK edge (no deterministic id) — the row emits under its own opaque
      // id, which is never reused after a delete, so it can't be in this class.
      if (entityId == null) continue;
      if (await gate.isTombstoned(_entryTable, entityId)) {
        diverged.add(entityId);
      }
    }
    return TombstoneRevivedTableResult(table: _entryTable, entityIds: diverged);
  }

  /// The Unknown-sentinel member, which uses a deterministic UUIDv5 id and is
  /// re-created by orphan-rescue paths. Counted as diverged when the live row
  /// exists but the engine tombstones its id.
  Future<TombstoneRevivedTableResult> _scanSentinelMember(
    TombstoneGate gate,
  ) async {
    final row = await _db.membersDao.getMemberById(unknownSentinelMemberId);
    if (row == null || row.isDeleted) {
      return const TombstoneRevivedTableResult.named(_memberTable);
    }
    if (await gate.isTombstoned(_memberTable, unknownSentinelMemberId)) {
      return TombstoneRevivedTableResult(
        table: _memberTable,
        entityIds: [unknownSentinelMemberId],
      );
    }
    return const TombstoneRevivedTableResult.named(_memberTable);
  }
}

/// Per-table divergence count plus the affected entity ids.
@immutable
class TombstoneRevivedTableResult {
  const TombstoneRevivedTableResult({
    required this.table,
    required this.entityIds,
  });

  const TombstoneRevivedTableResult.named(this.table)
    : entityIds = const <String>[];

  static const TombstoneRevivedTableResult empty =
      TombstoneRevivedTableResult.named('');

  final String table;
  final List<String> entityIds;

  int get count => entityIds.length;
}

/// The full diagnostic result of one [TombstoneRevivedRowsDetector.scan].
@immutable
class TombstoneRevivedRowsReport {
  const TombstoneRevivedRowsReport({
    required this.gateAvailable,
    required this.groups,
    required this.entries,
    required this.sentinelMember,
  });

  /// `false` when no engine handle was wired, in which case the per-table counts
  /// are not meaningful (the gate cannot read `field_versions`).
  final bool gateAvailable;

  final TombstoneRevivedTableResult groups;
  final TombstoneRevivedTableResult entries;
  final TombstoneRevivedTableResult sentinelMember;

  /// Total diverged rows across all surfaces.
  int get totalDiverged =>
      groups.count + entries.count + sentinelMember.count;

  bool get hasDivergence => totalDiverged > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'gate_available': gateAvailable,
    'total_diverged': totalDiverged,
    'member_groups': groups.count,
    'member_group_entries': entries.count,
    'sentinel_member': sentinelMember.count,
    'member_groups_ids': groups.entityIds,
    'member_group_entries_ids': entries.entityIds,
    'sentinel_member_ids': sentinelMember.entityIds,
  };
}
