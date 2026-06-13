import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';

/// Reconciles [fields] for a single repaired entity against this device's
/// `field_versions`. Wired by the caller to `ffi.recordReconcile`
/// (`divergentFreshHlc: true`), so a value-equal field emits zero ops and only
/// a genuinely-divergent value goes out at a fresh HLC. See [drain] for why
/// reconcile rather than a blind `recordUpdate`.
typedef MigrationRepairRecordReconcile =
    Future<void> Function({
      required String table,
      required String entityId,
      required Map<String, dynamic> fields,
    });

class MigrationSyncRepairResult {
  const MigrationSyncRepairResult({
    this.repaired = 0,
    this.dropped = 0,
    this.skipped = 0,
    this.error,
  });

  /// Rows whose op was emitted and queue row deleted.
  final int repaired;

  /// Rows dropped without emitting (deleted/missing entity).
  final int dropped;

  /// Rows skipped-and-deleted (suppressed / PK-gated group).
  final int skipped;

  final String? error;

  bool get hasError => error != null;
}

/// Drains the `sync_migration_repairs` queue, emitting real CRDT ops for the
/// synced-field rewrites that the Drift `onUpgrade` chain performs in raw SQL.
///
/// For each queued repair it RE-READS the entity's CURRENT field values at
/// drain time (never a migration-time capture), encodes them via an explicit
/// per-`(table, field)` registry matching the repository emissions, and emits
/// via `record_reconcile(DivergentMode::FreshHlc)`. The drain must NOT
/// blind-`recordUpdate`: the one-time blanket backfill re-broadcasts the
/// CURRENT value of every group's `sort_state` (and every markdown member),
/// most of which are unchanged, so a fresh-HLC update would let this device's
/// stale-but-equal value win LWW group-wide and silently revert a peer's
/// un-pulled reorder (the same fresh-hlc-reemission-clobber class the durable
/// outbox path fixes). Reconcile compares each field against this device's own
/// `field_versions`: a value-equal field emits zero ops, only a genuinely
/// divergent migrated value goes out at a fresh HLC. A queue row is deleted
/// only on FFI success, so a failed emit is retried on the next healthy
/// catch-up. Rows for deleted/missing entities are dropped (tombstone
/// propagation owns those), and `member_groups` repairs respect
/// PK-gating/suppression (skip-and-delete for suppressed groups).
class MigrationSyncRepairService {
  const MigrationSyncRepairService({
    required AppDatabase db,
    required MigrationRepairRecordReconcile recordReconcile,
    TombstoneGate? tombstoneGate,
  }) : _db = db,
       _recordReconcile = recordReconcile,
       _tombstoneGate = tombstoneGate;

  final AppDatabase _db;
  final MigrationRepairRecordReconcile _recordReconcile;

  /// TombstoneGate consulted before emitting the Unknown-sentinel member
  /// create: a tombstoned sentinel id is a burned id under absorbing-delete
  /// semantics, so the create is skipped rather than written into it. Null when
  /// no engine is available (tests without a live handle) → treated as "not
  /// tombstoned", matching the legacy emit path.
  final TombstoneGate? _tombstoneGate;

  /// One-time blanket-backfill flag (APPROVED: member_groups.sort_state for all
  /// non-deleted groups, members.markdown_enabled for markdown_enabled=true
  /// members). Converges historical 0.9.x divergence for installs that ran the
  /// pre-flatten migrations before this code shipped.
  static const backfillFlagKey = 'sync.migration_repair_backfill_v1';

  static Future<bool> hasPending(AppDatabase db) async {
    if (!await _tableExists(db)) return false;
    final rows = await db
        .customSelect(
          'SELECT 1 FROM sync_migration_repairs LIMIT 1',
        )
        .get();
    return rows.isNotEmpty;
  }

  /// Whether the local-only `sync_migration_repairs` table is present. A
  /// dev/test DB stamped at the current schema by a different branch's
  /// numbering (from == to, so `onUpgrade` never ran) can lack it — the same
  /// limitation as the sibling `sync_op_outbox`. Guard here so a drain no-ops
  /// instead of failing on a missing table.
  static Future<bool> _tableExists(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT 1 FROM sqlite_master '
          'WHERE type = ? AND name = ? LIMIT 1',
          variables: [
            Variable.withString('table'),
            Variable.withString('sync_migration_repairs'),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<MigrationSyncRepairResult> drain() async {
    if (!await _tableExists(_db)) return const MigrationSyncRepairResult();
    try {
      final rows = await _db
          .customSelect(
            'SELECT table_name, entity_id, field_names_json, reason '
            'FROM sync_migration_repairs '
            'ORDER BY enqueued_at ASC, table_name ASC, entity_id ASC',
          )
          .get();

      var repaired = 0;
      var dropped = 0;
      var skipped = 0;

      for (final row in rows) {
        final table = row.read<String>('table_name');
        final entityId = row.read<String>('entity_id');
        final reason = row.read<String>('reason');
        final fieldNames =
            (jsonDecode(row.read<String>('field_names_json')) as List)
                .cast<String>();

        final disposition = await _resolve(table, entityId, fieldNames);
        switch (disposition.kind) {
          case _DispositionKind.emit:
            // FFI first; only delete the queue row once the engine accepted the
            // op. A throw here aborts the drain and leaves the row for retry.
            await _recordReconcile(
              table: table,
              entityId: entityId,
              fields: disposition.fields!,
            );
            await _delete(table, entityId, reason);
            repaired++;
          case _DispositionKind.drop:
            await _delete(table, entityId, reason);
            dropped++;
          case _DispositionKind.skip:
            await _delete(table, entityId, reason);
            skipped++;
        }
      }

      if (repaired > 0 || dropped > 0 || skipped > 0) {
        debugPrint(
          '[MIGRATION_SYNC_REPAIR] repaired=$repaired dropped=$dropped '
          'skipped=$skipped',
        );
      }
      return MigrationSyncRepairResult(
        repaired: repaired,
        dropped: dropped,
        skipped: skipped,
      );
    } catch (error) {
      debugPrint('[MIGRATION_SYNC_REPAIR] drain failed: $error');
      return MigrationSyncRepairResult(error: error.toString());
    }
  }

  /// Resolves what to do with one queued repair by re-reading CURRENT row state.
  Future<_Disposition> _resolve(
    String table,
    String entityId,
    List<String> fieldNames,
  ) async {
    switch (table) {
      case 'members':
        return _resolveMembers(entityId, fieldNames);
      case 'member_groups':
        return _resolveMemberGroups(entityId, fieldNames);
      case 'conversations':
        return _resolveConversations(entityId, fieldNames);
      case 'fronting_sessions':
        return _resolveFrontingSessions(entityId, fieldNames);
      default:
        // Unknown table — drop rather than wedge the drain forever.
        return const _Disposition.drop();
    }
  }

  Future<_Disposition> _resolveMembers(
    String entityId,
    List<String> fieldNames,
  ) async {
    // Whole-entity create: the orphan rescue enqueues the sentinel member
    // with the `__create__` marker. Re-read the whole row and reconcile every
    // field (DriftMemberRepository.memberFields), so a peer missing the
    // sentinel gets it (absent fields backfill) without clobbering any field a
    // peer already converged on. A tombstoned sentinel id is burned — skip
    // rather than emit into it (a no-op on peers, a local divergence).
    if (fieldNames.contains('__create__')) {
      final member = await _db.membersDao.getMemberById(entityId);
      // Missing or locally-deleted: tombstone propagation owns that — never
      // revive the sentinel via a create.
      if (member == null || member.isDeleted) return const _Disposition.drop();
      final gate = _tombstoneGate;
      if (gate != null && await gate.isTombstoned('members', entityId)) {
        debugPrint(
          '[MIGRATION_SYNC_REPAIR] skipping sentinel member create for '
          '$entityId — tombstoned in the engine (burned id).',
        );
        return const _Disposition.drop();
      }
      return _Disposition.emit(
        DriftMemberRepository.memberFields(MemberMapper.toDomain(member)),
      );
    }

    final rows = await _db
        .customSelect(
          'SELECT markdown_enabled, is_deleted FROM members WHERE id = ?',
          variables: [Variable.withString(entityId)],
        )
        .get();
    if (rows.isEmpty) return const _Disposition.drop();
    final row = rows.single;
    if (row.read<bool>('is_deleted')) return const _Disposition.drop();

    final fields = <String, dynamic>{};
    for (final field in fieldNames) {
      switch (field) {
        case 'markdown_enabled':
          // int -> bool, matching DriftMemberRepository.memberFields.
          fields['markdown_enabled'] = row.read<bool>('markdown_enabled');
        default:
          break;
      }
    }
    if (fields.isEmpty) return const _Disposition.drop();
    return _Disposition.emit(fields);
  }

  Future<_Disposition> _resolveMemberGroups(
    String entityId,
    List<String> fieldNames,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT sort_state, is_deleted, sync_suppressed, pluralkit_uuid '
          'FROM member_groups WHERE id = ?',
          variables: [Variable.withString(entityId)],
        )
        .get();
    if (rows.isEmpty) return const _Disposition.drop();
    final row = rows.single;
    if (row.read<bool>('is_deleted')) return const _Disposition.drop();

    // PK-gating/suppression: mirror the repository's emit gate. A suppressed
    // group never emits; a PK-backed group only emits when PK group-sync v2 is
    // enabled. Skip-and-delete so the queue does not grow unbounded.
    if (row.read<bool>('sync_suppressed')) return const _Disposition.skip();
    final pkUuid = row.readNullable<String>('pluralkit_uuid')?.trim() ?? '';
    if (pkUuid.isNotEmpty) {
      final settings = await _db.systemSettingsDao.getSettings();
      if (!settings.pkGroupSyncV2Enabled) return const _Disposition.skip();
    }

    final fields = <String, dynamic>{};
    for (final field in fieldNames) {
      switch (field) {
        case 'sort_state':
          fields['sort_state'] = sanitizeSortStateForEmission(
            row.read<String>('sort_state'),
            contextId: entityId,
          );
        default:
          break;
      }
    }
    if (fields.isEmpty) return const _Disposition.drop();
    return _Disposition.emit(fields);
  }

  Future<_Disposition> _resolveConversations(
    String entityId,
    List<String> fieldNames,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT includes_all_members, participant_ids, creator_id, '
          'is_deleted FROM conversations WHERE id = ?',
          variables: [Variable.withString(entityId)],
        )
        .get();
    if (rows.isEmpty) return const _Disposition.drop();
    final row = rows.single;
    if (row.read<bool>('is_deleted')) return const _Disposition.drop();

    final fields = <String, dynamic>{};
    for (final field in fieldNames) {
      switch (field) {
        case 'includes_all_members':
          // int -> bool, matching DriftConversationRepository emissions.
          fields['includes_all_members'] = row.read<bool>(
            'includes_all_members',
          );
        case 'participant_ids':
          // Passthrough of the stored JSON array text.
          fields['participant_ids'] = row.read<String>('participant_ids');
        case 'creator_id':
          fields['creator_id'] = row.readNullable<String>('creator_id');
        default:
          break;
      }
    }
    if (fields.isEmpty) return const _Disposition.drop();
    return _Disposition.emit(fields);
  }

  /// The orphan rescue rewrote `member_id`/`pluralkit_uuid` of a rescued
  /// session in raw SQL. Re-read the current values and reconcile them so the
  /// re-home to the Unknown sentinel propagates as a real op. Matches the
  /// `_frontingSessionsEntity.toSyncFields` encoding (passthrough strings).
  Future<_Disposition> _resolveFrontingSessions(
    String entityId,
    List<String> fieldNames,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT member_id, pluralkit_uuid, is_deleted '
          'FROM fronting_sessions WHERE id = ?',
          variables: [Variable.withString(entityId)],
        )
        .get();
    if (rows.isEmpty) return const _Disposition.drop();
    final row = rows.single;
    if (row.read<bool>('is_deleted')) return const _Disposition.drop();

    final fields = <String, dynamic>{};
    for (final field in fieldNames) {
      switch (field) {
        case 'member_id':
          fields['member_id'] = row.readNullable<String>('member_id');
        case 'pluralkit_uuid':
          fields['pluralkit_uuid'] = row.readNullable<String>('pluralkit_uuid');
        default:
          break;
      }
    }
    if (fields.isEmpty) return const _Disposition.drop();
    return _Disposition.emit(fields);
  }

  Future<void> _delete(String table, String entityId, String reason) {
    return _db.customStatement(
      'DELETE FROM sync_migration_repairs '
      'WHERE table_name = ? AND entity_id = ? AND reason = ?',
      [table, entityId, reason],
    );
  }

  /// Enqueues the APPROVED one-time blanket backfill for already-diverged
  /// installs (member_groups.sort_state for all non-deleted groups,
  /// members.markdown_enabled for markdown_enabled=true members), guarded by a
  /// SharedPreferences flag so it runs exactly once. Returns the number of rows
  /// enqueued; 0 on a no-op repeat run.
  ///
  /// Enqueue only — the actual emission happens via [drain]. Pass a [getFlag]
  /// reader / [setFlag] writer so the caller owns the SharedPreferences
  /// instance (matching GroupChatVisibilitySyncReemitService).
  Future<int> enqueueBlanketBackfillOnce({
    required Future<bool> Function() getFlag,
    required Future<void> Function() setFlag,
  }) async {
    if (await getFlag()) return 0;
    // No table to enqueue into on the renumbered-DB edge — leave the flag unset
    // so a later proper-schema open retries rather than burning the one-time run.
    if (!await _tableExists(_db)) return 0;

    var enqueued = 0;
    await _db.transaction(() async {
      enqueued += await _enqueueRepair(
        'SELECT id FROM member_groups WHERE is_deleted = 0',
        'member_groups',
        const ['sort_state'],
        'backfill_v1_sort_state',
      );
      enqueued += await _enqueueRepair(
        'SELECT id FROM members WHERE markdown_enabled = 1 AND is_deleted = 0',
        'members',
        const ['markdown_enabled'],
        'backfill_v1_markdown_enabled',
      );
    });
    await setFlag();
    return enqueued;
  }

  Future<int> _enqueueRepair(
    String idQuery,
    String table,
    List<String> fields,
    String reason,
  ) async {
    final rows = await _db.customSelect(idQuery).get();
    final fieldsJson = jsonEncode(fields);
    final enqueuedAt = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final row in rows) {
      await _db.customStatement(
        'INSERT OR REPLACE INTO sync_migration_repairs '
        '(table_name, entity_id, field_names_json, reason, enqueued_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [table, row.read<String>('id'), fieldsJson, reason, enqueuedAt],
      );
      count++;
    }
    return count;
  }
}

enum _DispositionKind { emit, drop, skip }

class _Disposition {
  const _Disposition.emit(this.fields) : kind = _DispositionKind.emit;
  const _Disposition.drop()
      : kind = _DispositionKind.drop,
        fields = null;
  const _Disposition.skip()
      : kind = _DispositionKind.skip,
        fields = null;

  final _DispositionKind kind;
  final Map<String, dynamic>? fields;
}
