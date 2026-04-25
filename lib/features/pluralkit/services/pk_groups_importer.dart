import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

typedef PkGroupSyncCreateOverride =
    Future<void> Function(
      String table,
      String entityId,
      Map<String, dynamic> fields,
    );
typedef PkGroupSyncUpdateOverride =
    Future<void> Function(
      String table,
      String entityId,
      Map<String, dynamic> fields,
    );
typedef PkGroupSyncDeleteOverride =
    Future<void> Function(String table, String entityId);

/// Result of a single PK-groups import pass.
class PkGroupsImportResult {
  final int groupsInserted;
  final int groupsUpdated;
  final int groupsObserved;
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;

  /// Count of groups whose `memberIds` came back as null (privacy / partial
  /// fetch). Surfaces flapping — a high number here means membership reconcile
  /// was intentionally skipped for those groups.
  final int groupsWithUnknownMembership;

  const PkGroupsImportResult({
    this.groupsInserted = 0,
    this.groupsUpdated = 0,
    this.groupsObserved = 0,
    this.entriesInserted = 0,
    this.entriesRemoved = 0,
    this.entriesDeferred = 0,
    this.groupsWithUnknownMembership = 0,
  });

  PkGroupsImportResult copyWith({
    int? groupsInserted,
    int? groupsUpdated,
    int? groupsObserved,
    int? entriesInserted,
    int? entriesRemoved,
    int? entriesDeferred,
    int? groupsWithUnknownMembership,
  }) => PkGroupsImportResult(
    groupsInserted: groupsInserted ?? this.groupsInserted,
    groupsUpdated: groupsUpdated ?? this.groupsUpdated,
    groupsObserved: groupsObserved ?? this.groupsObserved,
    entriesInserted: entriesInserted ?? this.entriesInserted,
    entriesRemoved: entriesRemoved ?? this.entriesRemoved,
    entriesDeferred: entriesDeferred ?? this.entriesDeferred,
    groupsWithUnknownMembership:
        groupsWithUnknownMembership ?? this.groupsWithUnknownMembership,
  );

  bool get changedRepairInputs =>
      groupsInserted > 0 ||
      groupsUpdated > 0 ||
      entriesInserted > 0 ||
      entriesRemoved > 0;
}

/// Imports PluralKit groups and memberships into Prism.
///
/// Phase 1 (pull only). Follows the codex-reviewed revisions in
/// `docs/plans/pk-sp-gaps/03-pk-groups.md`:
///
/// - R1: Authoritative-set diff — membership removals are driven by the PK
///   member UUID set, not by locally-resolved IDs. Unresolved members are
///   deferred, never treated as "missing on PK".
/// - R2: `memberIds == null` means "unknown" → skip removals entirely.
/// - R3: `reattribute(...)` insert-only pass for members that weren't linked
///   at first import.
/// - R5: `overwriteMetadata` — background sync reconciles membership only;
///   metadata (name/description/color/displayName) is only overwritten on
///   explicit user action.
/// - R6: Deterministic entry IDs `sha256(groupUuid\0memberPkUuid)[:16]`.
/// - R7: Identity matching is UUID-only.
/// - R8: Local emoji is never touched on PK pull.
/// - R9: `last_seen_from_pk_at` refreshed for every observed group.
/// - R10: PK-backed groups use deterministic local ids so parallel imports on
///   different devices converge on the same sync entity.
class PkGroupsImporter with SyncRecordMixin {
  final AppDatabase _db;
  final MemberGroupsDao _dao;
  final MemberRepository _memberRepository;
  final ffi.PrismSyncHandle? _syncHandle;
  final PkGroupSyncCreateOverride? _recordCreateOverride;
  final PkGroupSyncUpdateOverride? _recordUpdateOverride;
  final PkGroupSyncDeleteOverride? _recordDeleteOverride;

  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';

  PkGroupsImporter({
    required AppDatabase db,
    required MemberRepository memberRepository,
    ffi.PrismSyncHandle? syncHandle,
    PkGroupSyncCreateOverride? recordCreateOverride,
    PkGroupSyncUpdateOverride? recordUpdateOverride,
    PkGroupSyncDeleteOverride? recordDeleteOverride,
  }) : _db = db,
       _dao = db.memberGroupsDao,
       _memberRepository = memberRepository,
       _syncHandle = syncHandle,
       _recordCreateOverride = recordCreateOverride,
       _recordUpdateOverride = recordUpdateOverride,
       _recordDeleteOverride = recordDeleteOverride;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  /// Derive a deterministic `member_group_entries.id` from PK identifiers so
  /// two offline devices produce the same row (see R6).
  static String deriveEntryId(String groupUuid, String memberPkUuid) {
    final digest = sha256.convert(utf8.encode('$groupUuid\u0000$memberPkUuid'));
    // Hex → first 16 chars = 64 bits of entropy.
    return digest.toString().substring(0, 16);
  }

  /// Derive a deterministic local group id from the PK UUID so independent
  /// devices import the same PK group under the same entity id.
  static String deriveGroupId(String groupUuid) => 'pk-group-$groupUuid';

  /// Canonical sync entity id for PK-backed groups.
  static String deriveGroupSyncEntityId(String groupUuid) =>
      'pk-group:$groupUuid';

  @visibleForTesting
  static Map<String, dynamic> groupCreateSyncFields(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'display_order': row.displayOrder,
      'parent_group_id': row.parentGroupId,
      'group_type': row.groupType,
      'filter_rules': row.filterRules,
      'created_at': row.createdAt.toIso8601String(),
      'pluralkit_id': row.pluralkitId,
      'pluralkit_uuid': row.pluralkitUuid,
      'last_seen_from_pk_at': row.lastSeenFromPkAt?.toIso8601String(),
      'is_deleted': row.isDeleted,
    };
  }

  @visibleForTesting
  static Map<String, dynamic> groupUpdateSyncFields(MemberGroupRow row) {
    return groupCreateSyncFields(row);
  }

  @visibleForTesting
  static Map<String, dynamic> entrySyncFields({
    required String groupId,
    required String memberId,
    required String pkGroupUuid,
    required String pkMemberUuid,
  }) {
    return {
      'group_id': groupId,
      'member_id': memberId,
      'pk_group_uuid': pkGroupUuid,
      'pk_member_uuid': pkMemberUuid,
      'is_deleted': false,
    };
  }

  /// Import a batch of PK groups.
  ///
  /// When [overwriteMetadata] is false (default for background sync),
  /// existing rows keep their local name/description/color/displayOrder and
  /// only membership is reconciled. When true (explicit re-import / user
  /// action), metadata is replaced with PK's values.
  Future<PkGroupsImportResult> importGroups(
    List<PKGroup> pkGroups, {
    bool overwriteMetadata = false,
  }) async {
    var result = const PkGroupsImportResult();
    if (pkGroups.isEmpty) return result;
    final syncEnabled = await _pkGroupSyncV2Enabled();

    // Resolve members once up front so we know which PK UUIDs are locally
    // available *right now*. The authoritative set (R1) is the PK list, not
    // this map — the map only tells us which PK UUIDs map to a local row.
    final allMembers = await _memberRepository.getAllMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty) {
        pkUuidToLocalMemberId[m.pluralkitUuid!] = m.id;
      }
    }

    final now = DateTime.now();

    for (final pk in pkGroups) {
      result = result.copyWith(groupsObserved: result.groupsObserved + 1);

      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      final groupLocalId = existing?.id ?? deriveGroupId(pk.uuid);

      if (existing == null) {
        // Insert new row. Always writes metadata — there is nothing local to
        // preserve. Local emoji stays null (R8): PK's `icon` is a URL, not an
        // emoji.
        final displayOrder = await _dao.nextDisplayOrder(null);
        await _dao.upsertGroup(
          MemberGroupsCompanion.insert(
            id: groupLocalId,
            name: pk.displayName ?? pk.name,
            description: Value(pk.description),
            colorHex: Value(pk.color == null ? null : '#${pk.color}'),
            emoji: const Value(null),
            displayOrder: Value(displayOrder),
            createdAt: now,
            isDeleted: const Value(false),
            pluralkitId: Value(pk.id),
            pluralkitUuid: Value(pk.uuid),
            lastSeenFromPkAt: Value(now),
          ),
        );
        final createdRow = await _loadGroupRow(groupLocalId);
        if (syncEnabled) {
          await _emitCreate(
            _groupTable,
            deriveGroupSyncEntityId(pk.uuid),
            groupCreateSyncFields(createdRow),
          );
          await _emitLegacyAliasDeletesForPkGroup(pk.uuid);
        }
        result = result.copyWith(groupsInserted: result.groupsInserted + 1);
      } else {
        // Existing row. Refresh last_seen_from_pk_at always; only update
        // metadata when the caller asked us to (R5). Never touch emoji (R8).
        final updates = MemberGroupsCompanion(
          id: Value(existing.id),
          lastSeenFromPkAt: Value(now),
          pluralkitId: Value(pk.id),
          pluralkitUuid: Value(pk.uuid),
          name: overwriteMetadata
              ? Value(pk.displayName ?? pk.name)
              : const Value.absent(),
          description: overwriteMetadata
              ? Value(pk.description)
              : const Value.absent(),
          colorHex: overwriteMetadata
              ? Value(pk.color == null ? null : '#${pk.color}')
              : const Value.absent(),
        );
        await (_db.update(
          _db.memberGroups,
        )..where((g) => g.id.equals(existing.id))).write(updates);
        final updatedRow = await _loadGroupRow(existing.id);
        if (syncEnabled) {
          await _emitUpdate(
            _groupTable,
            deriveGroupSyncEntityId(pk.uuid),
            groupUpdateSyncFields(updatedRow),
          );
          await _emitLegacyAliasDeletesForPkGroup(pk.uuid);
        }
        if (overwriteMetadata) {
          result = result.copyWith(groupsUpdated: result.groupsUpdated + 1);
        }
      }

      // Membership reconciliation — R1 + R2.
      if (pk.memberIds == null) {
        // Unknown → don't touch entries at all.
        result = result.copyWith(
          groupsWithUnknownMembership: result.groupsWithUnknownMembership + 1,
        );
        debugPrint(
          '[PK groups] unknown membership for group ${pk.uuid}; skipping '
          'reconciliation.',
        );
        continue;
      }

      final delta = await _reconcileMembership(
        groupLocalId: groupLocalId,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: false,
      );
      if (syncEnabled) {
        await _emitMembershipSync(delta);
      }
      result = result.copyWith(
        entriesInserted: result.entriesInserted + delta.entriesInserted,
        entriesRemoved: result.entriesRemoved + delta.entriesRemoved,
        entriesDeferred: result.entriesDeferred + delta.entriesDeferred,
      );
    }

    await _markRepairDirtyIfNeeded(result);
    return result;
  }

  /// R3 — insert-only re-attribution pass. Called after member mapping has
  /// applied so PK UUIDs that were previously unknown can now be resolved.
  /// Never removes entries.
  Future<PkGroupsImportResult> reattribute(PluralKitClient client) async {
    final pkGroups = await client.getGroups(withMembers: true);
    if (pkGroups.isEmpty) return const PkGroupsImportResult();
    final syncEnabled = await _pkGroupSyncV2Enabled();

    final allMembers = await _memberRepository.getAllMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      if (m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty) {
        pkUuidToLocalMemberId[m.pluralkitUuid!] = m.id;
      }
    }

    var result = const PkGroupsImportResult();
    for (final pk in pkGroups) {
      if (pk.memberIds == null) continue;
      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      if (existing == null) continue; // Reattribute only touches known groups.
      final delta = await _reconcileMembership(
        groupLocalId: existing.id,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: true,
      );
      if (syncEnabled) {
        await _emitMembershipSync(delta);
      }
      result = result.copyWith(
        groupsObserved: result.groupsObserved + 1,
        entriesInserted: result.entriesInserted + delta.entriesInserted,
      );
    }
    await _markRepairDirtyIfNeeded(result);
    return result;
  }

  Future<void> _markRepairDirtyIfNeeded(PkGroupsImportResult result) async {
    if (!result.changedRepairInputs) return;
    try {
      await PkGroupRepairRunGate.markDirtyInDefaultStore();
    } catch (error) {
      debugPrint('[PK groups] failed to mark repair dirty: $error');
    }
  }

  Future<_ReconcileDelta> _reconcileMembership({
    required String groupLocalId,
    required String groupPkUuid,
    required List<String> authoritativePkMemberUuids,
    required List<domain.Member> allMembers,
    required Map<String, String> pkUuidToLocalMemberId,
    required bool insertOnly,
  }) async {
    final memberById = <String, domain.Member>{
      for (final m in allMembers) m.id: m,
    };

    final authoritativeSet = authoritativePkMemberUuids.toSet();
    final entries = await _dao.entriesForGroup(groupLocalId);

    int inserted = 0;
    int removed = 0;
    int deferred = 0;
    final insertedEntries = <_SyncedEntry>[];
    final removedEntryIds = <String>[];

    await _db.transaction(() async {
      if (!insertOnly) {
        for (final entry in entries) {
          final member = memberById[entry.memberId];
          if (member == null) continue; // orphan row — leave alone.
          final pkUuid = member.pluralkitUuid;
          if (pkUuid == null || pkUuid.isEmpty) {
            // Local-only member — preserve.
            continue;
          }
          if (authoritativeSet.contains(pkUuid)) continue; // preserve.
          // PK-linked member, not in authoritative set → soft-delete.
          await _dao.softDeleteEntry(entry.id);
          removed++;
          removedEntryIds.add(entry.id);
        }
      }

      // Insert path — for every PK UUID in authoritative set, add an entry if
      // we can resolve it locally. Unresolved UUIDs count as deferred (R3).
      final existingActiveMemberIds = <String>{
        for (final e in entries)
          if (!e.isDeleted) e.memberId,
      };

      for (final pkMemberUuid in authoritativePkMemberUuids) {
        final localMemberId = pkUuidToLocalMemberId[pkMemberUuid];
        if (localMemberId == null) {
          deferred++;
          continue;
        }
        if (existingActiveMemberIds.contains(localMemberId)) continue;

        final entryId = deriveEntryId(groupPkUuid, pkMemberUuid);
        final existedBefore = entries.any((e) => e.id == entryId);
        try {
          await _dao.upsertEntry(
            MemberGroupEntriesCompanion.insert(
              id: entryId,
              groupId: groupLocalId,
              memberId: localMemberId,
              pkGroupUuid: Value(groupPkUuid),
              pkMemberUuid: Value(pkMemberUuid),
              isDeleted: const Value(false),
            ),
          );
        } on SqliteException catch (e) {
          // SQLITE_CONSTRAINT_UNIQUE (2067): concurrent sync already inserted
          // this entry. Treat as already-inserted.
          if (e.resultCode != 2067) rethrow;
        }
        inserted++;
        insertedEntries.add(
          _SyncedEntry(
            id: entryId,
            groupId: groupLocalId,
            memberId: localMemberId,
            pkGroupUuid: groupPkUuid,
            pkMemberUuid: pkMemberUuid,
            existedBefore: existedBefore,
          ),
        );
      }
    });

    return _ReconcileDelta(
      entriesInserted: inserted,
      entriesRemoved: removed,
      entriesDeferred: deferred,
      insertedEntries: insertedEntries,
      removedEntryIds: removedEntryIds,
    );
  }

  Future<MemberGroupRow> _loadGroupRow(String id) async {
    return (await (_db.select(
      _db.memberGroups,
    )..where((g) => g.id.equals(id))).getSingle());
  }

  Future<void> _emitCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final override = _recordCreateOverride;
    if (override != null) {
      await override(table, entityId, fields);
      return;
    }
    await syncRecordCreate(table, entityId, fields);
  }

  Future<void> _emitUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final override = _recordUpdateOverride;
    if (override != null) {
      await override(table, entityId, fields);
      return;
    }
    await syncRecordUpdate(table, entityId, fields);
  }

  Future<void> _emitDelete(String table, String entityId) async {
    final override = _recordDeleteOverride;
    if (override != null) {
      await override(table, entityId);
      return;
    }
    await syncRecordDelete(table, entityId);
  }

  Future<void> _emitLegacyAliasDeletesForPkGroup(String pkGroupUuid) async {
    final canonicalEntityId = deriveGroupSyncEntityId(pkGroupUuid);
    final aliases = await _db.pkGroupSyncAliasesDao.getByPkGroupUuid(
      pkGroupUuid,
    );
    final legacyEntityIds = <String>{};
    for (final alias in aliases) {
      final legacyEntityId = alias.legacyEntityId.trim();
      if (legacyEntityId.isEmpty || legacyEntityId == canonicalEntityId) {
        continue;
      }
      legacyEntityIds.add(legacyEntityId);
    }
    for (final legacyEntityId in legacyEntityIds) {
      await _emitDelete(_groupTable, legacyEntityId);
    }
  }

  Future<void> _emitMembershipSync(_ReconcileDelta delta) async {
    for (final entry in delta.insertedEntries) {
      final fields = entrySyncFields(
        groupId: entry.groupId,
        memberId: entry.memberId,
        pkGroupUuid: entry.pkGroupUuid,
        pkMemberUuid: entry.pkMemberUuid,
      );
      if (entry.existedBefore) {
        await _emitUpdate(_entryTable, entry.id, fields);
      } else {
        await _emitCreate(_entryTable, entry.id, fields);
      }
    }
    for (final entryId in delta.removedEntryIds) {
      await _emitDelete(_entryTable, entryId);
    }
  }

  Future<bool> _pkGroupSyncV2Enabled() async {
    final settings = await _db.systemSettingsDao.getSettings();
    return settings.pkGroupSyncV2Enabled;
  }
}

class _ReconcileDelta {
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;
  final List<_SyncedEntry> insertedEntries;
  final List<String> removedEntryIds;
  const _ReconcileDelta({
    required this.entriesInserted,
    required this.entriesRemoved,
    required this.entriesDeferred,
    required this.insertedEntries,
    required this.removedEntryIds,
  });
}

class _SyncedEntry {
  final String id;
  final String groupId;
  final String memberId;
  final String pkGroupUuid;
  final String pkMemberUuid;
  final bool existedBefore;

  const _SyncedEntry({
    required this.id,
    required this.groupId,
    required this.memberId,
    required this.pkGroupUuid,
    required this.pkMemberUuid,
    required this.existedBefore,
  });
}
