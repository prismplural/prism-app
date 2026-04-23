import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/member_groups_table.dart';
import 'package:prism_plurality/core/database/tables/member_group_entries_table.dart';

part 'member_groups_dao.g.dart';

class PkLinkedGroupDuplicateSet {
  const PkLinkedGroupDuplicateSet({
    required this.pkGroupUuid,
    required this.groups,
  });

  final String pkGroupUuid;
  final List<MemberGroupRow> groups;
}

class PkGroupEntryRehomeResult {
  const PkGroupEntryRehomeResult({
    this.movedEntries = 0,
    this.softDeletedConflicts = 0,
  });

  final int movedEntries;
  final int softDeletedConflicts;

  PkGroupEntryRehomeResult copyWith({
    int? movedEntries,
    int? softDeletedConflicts,
  }) {
    return PkGroupEntryRehomeResult(
      movedEntries: movedEntries ?? this.movedEntries,
      softDeletedConflicts: softDeletedConflicts ?? this.softDeletedConflicts,
    );
  }
}

@DriftAccessor(tables: [MemberGroups, MemberGroupEntries])
class MemberGroupsDao extends DatabaseAccessor<AppDatabase>
    with _$MemberGroupsDaoMixin {
  static const _memberGroupsTableName = 'member_groups';
  static const _syncSuppressedColumnName = 'sync_suppressed';
  static const _lookupBatchSize = 500;

  bool? _hasSyncSuppressedColumn;

  MemberGroupsDao(super.db);

  // ── Groups ──────────────────────────────────────────────────────

  Stream<List<MemberGroupRow>> watchAllGroups() =>
      (select(memberGroups)
            ..where((g) => g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .watch();

  Stream<MemberGroupRow?> watchGroupById(String id) =>
      (select(memberGroups)
            ..where((g) => g.id.equals(id) & g.isDeleted.equals(false)))
          .watchSingleOrNull();

  Future<MemberGroupRow?> getGroupById(String id) =>
      (select(memberGroups)
            ..where((g) => g.id.equals(id) & g.isDeleted.equals(false)))
          .getSingleOrNull();

  Stream<List<MemberGroupRow>> watchGroupsForMember(String memberId) {
    final entryQuery = select(memberGroupEntries)
      ..where((e) => e.memberId.equals(memberId) & e.isDeleted.equals(false));

    return entryQuery.watch().asyncMap((entries) async {
      if (entries.isEmpty) return <MemberGroupRow>[];
      final groupIds = entries.map((e) => e.groupId).toList();
      return (select(memberGroups)
            ..where((g) => g.id.isIn(groupIds) & g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .get();
    });
  }

  Stream<List<MemberGroupEntryRow>> watchGroupEntries(String groupId) =>
      (select(memberGroupEntries)..where(
            (e) => e.groupId.equals(groupId) & e.isDeleted.equals(false),
          ))
          .watch();

  Future<int> createGroup(MemberGroupsCompanion companion) =>
      into(memberGroups).insert(companion);

  Future<void> updateGroup(String id, MemberGroupsCompanion companion) =>
      (update(memberGroups)..where((g) => g.id.equals(id))).write(companion);

  Future<void> deleteGroup(String id) async {
    // Soft-delete entries for this group
    await (update(memberGroupEntries)..where((e) => e.groupId.equals(id)))
        .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
    // Soft-delete the group itself
    await (update(memberGroups)..where((g) => g.id.equals(id))).write(
      const MemberGroupsCompanion(isDeleted: Value(true)),
    );
  }

  // ── Entries ─────────────────────────────────────────────────────

  Future<int> createEntry(MemberGroupEntriesCompanion companion) =>
      into(memberGroupEntries).insert(companion);

  Future<void> deleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
        const MemberGroupEntriesCompanion(isDeleted: Value(true)),
      );

  Future<void> deleteEntriesForGroup(String groupId) =>
      (update(memberGroupEntries)..where((e) => e.groupId.equals(groupId)))
          .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));

  /// Watches member counts per group in a single query.
  /// Returns a map of groupId → count.
  Stream<Map<String, int>> watchMemberCountsByGroup() {
    final query = select(memberGroupEntries)
      ..where((e) => e.isDeleted.equals(false));

    return query.watch().map((entries) {
      final counts = <String, int>{};
      for (final e in entries) {
        counts[e.groupId] = (counts[e.groupId] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Returns all active group entries across all groups.
  Stream<List<MemberGroupEntryRow>> watchAllGroupEntries() => (select(
    memberGroupEntries,
  )..where((e) => e.isDeleted.equals(false))).watch();

  /// Returns all active group entries across all groups as a future.
  Future<List<MemberGroupEntryRow>> getAllGroupEntries() => (select(
    memberGroupEntries,
  )..where((e) => e.isDeleted.equals(false))).get();

  Future<Map<String, int>> activeEntryCountsByGroupId() async {
    final rows = await customSelect(
      '''
      SELECT group_id, COUNT(*) AS entry_count
      FROM member_group_entries
      WHERE is_deleted = 0
      GROUP BY group_id
      ''',
      readsFrom: {memberGroupEntries},
    ).get();

    return {
      for (final row in rows)
        row.read<String>('group_id'): row.read<int>('entry_count'),
    };
  }

  Future<Map<String, Set<String>>> activePkMemberUuidsByGroupId() async {
    final rows = await customSelect(
      '''
      SELECT group_id, pk_member_uuid
      FROM member_group_entries
      WHERE is_deleted = 0
        AND pk_member_uuid IS NOT NULL
        AND pk_member_uuid != ''
      ''',
      readsFrom: {memberGroupEntries},
    ).get();

    final grouped = <String, Set<String>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent(row.read<String>('group_id'), () => <String>{})
          .add(row.read<String>('pk_member_uuid'));
    }
    return grouped;
  }

  /// Find an active entry for a specific group + member combination.
  Future<MemberGroupEntryRow?> findEntry(String groupId, String memberId) =>
      (select(memberGroupEntries)..where(
            (e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  // ── PluralKit linkage ───────────────────────────────────────────

  /// Look up an existing group by its PluralKit UUID. Identity is UUID-only
  /// (R7): PK short IDs can be recycled, so we never match on them.
  Future<MemberGroupRow?> findByPluralkitUuid(String uuid) async {
    final rows =
        await (select(memberGroups)..where(
              (g) => g.pluralkitUuid.equals(uuid) & g.isDeleted.equals(false),
            ))
            .get();
    if (rows.isEmpty) return null;

    final sorted = [...rows]..sort(_compareActivePkLookupRows);
    return sorted.first;
  }

  Future<MemberGroupRow?> findByPluralkitUuidIncludingDeleted(
    String uuid,
  ) async {
    final rows = await (select(
      memberGroups,
    )..where((g) => g.pluralkitUuid.equals(uuid))).get();
    if (rows.isEmpty) return null;

    final sorted = [...rows]
      ..sort((left, right) {
        if (left.isDeleted != right.isDeleted) {
          return left.isDeleted ? 1 : -1;
        }
        return _compareActivePkLookupRows(left, right);
      });
    return sorted.first;
  }

  Future<List<MemberGroupRow>> getAllGroupsIncludingDeleted() =>
      select(memberGroups).get();

  Future<List<MemberGroupRow>> getAllActiveGroups() =>
      (select(memberGroups)..where((g) => g.isDeleted.equals(false))).get();

  /// Backfill missing PK UUID references on active membership rows using the
  /// currently linked local group/member records.
  ///
  /// This is safe to re-run; existing non-empty PK UUID fields are preserved.
  Future<int> backfillActiveEntryPkReferences() {
    return customUpdate(
      '''
      UPDATE member_group_entries
      SET
        pk_group_uuid = COALESCE(
          NULLIF(pk_group_uuid, ''),
          (
            SELECT g.pluralkit_uuid
            FROM member_groups g
            WHERE g.id = member_group_entries.group_id
              AND g.is_deleted = 0
              AND g.pluralkit_uuid IS NOT NULL
              AND g.pluralkit_uuid <> ''
            LIMIT 1
          )
        ),
        pk_member_uuid = COALESCE(
          NULLIF(pk_member_uuid, ''),
          (
            SELECT m.pluralkit_uuid
            FROM members m
            WHERE m.id = member_group_entries.member_id
              AND m.is_deleted = 0
              AND m.pluralkit_uuid IS NOT NULL
              AND m.pluralkit_uuid <> ''
            LIMIT 1
          )
        )
      WHERE is_deleted = 0
        AND (
          (
            NULLIF(pk_group_uuid, '') IS NULL
            AND EXISTS (
              SELECT 1
              FROM member_groups g
              WHERE g.id = member_group_entries.group_id
                AND g.is_deleted = 0
                AND g.pluralkit_uuid IS NOT NULL
                AND g.pluralkit_uuid <> ''
            )
          )
          OR (
            NULLIF(pk_member_uuid, '') IS NULL
            AND EXISTS (
              SELECT 1
              FROM members m
              WHERE m.id = member_group_entries.member_id
                AND m.is_deleted = 0
                AND m.pluralkit_uuid IS NOT NULL
                AND m.pluralkit_uuid <> ''
            )
          )
        )
      ''',
      updates: {memberGroupEntries},
    );
  }

  /// Canonicalizes PK-backed entry IDs by rewriting each active row whose
  /// `pk_group_uuid` + `pk_member_uuid` are set onto the deterministic
  /// `sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]` hash the sync layer
  /// already emits. Reviving tombstones under the canonical id when a
  /// matching tombstoned row already exists.
  ///
  /// Idempotent: rows whose `id` already equals the canonical hash are left
  /// alone. Rows without both PK UUIDs set are skipped (non-PK entries).
  ///
  /// Algorithm per row:
  /// 1. Compute `canonical = sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]`.
  /// 2. If `id == canonical` skip.
  /// 3. If a tombstoned row (`is_deleted = 1`) already exists under
  ///    `canonical`: promote that tombstone (set `is_deleted = 0` and sync
  ///    the group/member onto the logical edge) and soft-delete the legacy
  ///    active row.
  /// 4. Otherwise rewrite the legacy row's `id` to `canonical`.
  ///
  /// Wrapped in a transaction so repair sees an atomic before/after state
  /// if any row fails mid-pass.
  Future<
    ({int rewritten, int revivedTombstones, int softDeletedLegacyConflicts})
  >
  canonicalizePkBackedEntryIds() {
    return transaction(() async {
      var rewritten = 0;
      var revivedTombstones = 0;
      var softDeletedLegacyConflicts = 0;

      // Scope to active PK-backed entries. Order by id so repeated runs
      // process rows in the same sequence when multiple legacy rows map to
      // the same canonical edge.
      final candidates =
          await (select(memberGroupEntries)
                ..where(
                  (e) =>
                      e.isDeleted.equals(false) &
                      e.pkGroupUuid.isNotNull() &
                      e.pkMemberUuid.isNotNull(),
                )
                ..orderBy([(e) => OrderingTerm.asc(e.id)]))
              .get();

      final idsToLoad = <String>{};
      final canonicalIdsByEntryId = <String, String>{};
      for (final entry in candidates) {
        final pkGroupUuid = entry.pkGroupUuid;
        final pkMemberUuid = entry.pkMemberUuid;
        if (pkGroupUuid == null ||
            pkGroupUuid.isEmpty ||
            pkMemberUuid == null ||
            pkMemberUuid.isEmpty) {
          continue;
        }
        final canonical = _canonicalPkEntryId(pkGroupUuid, pkMemberUuid);
        canonicalIdsByEntryId[entry.id] = canonical;
        idsToLoad
          ..add(entry.id)
          ..add(canonical);
      }

      final byId = <String, MemberGroupEntryRow>{};
      final idsList = idsToLoad.toList(growable: false);
      for (var start = 0; start < idsList.length; start += _lookupBatchSize) {
        final end = start + _lookupBatchSize > idsList.length
            ? idsList.length
            : start + _lookupBatchSize;
        final batch = idsList.sublist(start, end);
        if (batch.isEmpty) continue;
        final existingRows = await (select(
          memberGroupEntries,
        )..where((e) => e.id.isIn(batch))).get();
        for (final row in existingRows) {
          byId[row.id] = row;
        }
      }

      for (final entry in candidates) {
        final pkGroupUuid = entry.pkGroupUuid;
        final pkMemberUuid = entry.pkMemberUuid;
        if (pkGroupUuid == null ||
            pkGroupUuid.isEmpty ||
            pkMemberUuid == null ||
            pkMemberUuid.isEmpty) {
          continue;
        }

        final canonical = canonicalIdsByEntryId[entry.id]!;
        if (entry.id == canonical) continue;

        final canonicalRow = byId[canonical];

        if (canonicalRow != null && canonicalRow.isDeleted) {
          // Soft-delete the legacy active row first so the partial unique
          // index on (group_id, member_id) WHERE is_deleted = 0 is clear,
          // then revive the tombstoned canonical row onto the logical edge.
          await (update(memberGroupEntries)
                ..where((e) => e.id.equals(entry.id)))
              .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
          await (update(
            memberGroupEntries,
          )..where((e) => e.id.equals(canonical))).write(
            MemberGroupEntriesCompanion(
              groupId: Value(entry.groupId),
              memberId: Value(entry.memberId),
              pkGroupUuid: Value(pkGroupUuid),
              pkMemberUuid: Value(pkMemberUuid),
              isDeleted: const Value(false),
            ),
          );
          revivedTombstones++;
          softDeletedLegacyConflicts++;
          byId[entry.id] = entry.copyWith(isDeleted: true);
          byId[canonical] = canonicalRow.copyWith(
            groupId: entry.groupId,
            memberId: entry.memberId,
            pkGroupUuid: Value(pkGroupUuid),
            pkMemberUuid: Value(pkMemberUuid),
            isDeleted: false,
          );
          continue;
        }

        if (canonicalRow != null && !canonicalRow.isDeleted) {
          // An active row already occupies the canonical id for a different
          // edge (shouldn't normally happen because the hash is derived from
          // the same PK pair, but be defensive). Skip so we don't collapse
          // two distinct edges; repair continues with the next legacy row.
          continue;
        }

        // Primary-key rewrite. SQLite permits `UPDATE ... SET id = ?`; the
        // member_group_entries table declares no foreign keys, so this is
        // safe. `member_groups` tables never join on entry ids either.
        await customUpdate(
          'UPDATE member_group_entries SET id = ? WHERE id = ?',
          variables: [
            Variable.withString(canonical),
            Variable.withString(entry.id),
          ],
          updates: {memberGroupEntries},
        );
        rewritten++;
        byId
          ..remove(entry.id)
          ..[canonical] = entry.copyWith(id: canonical);
      }

      return (
        rewritten: rewritten,
        revivedTombstones: revivedTombstones,
        softDeletedLegacyConflicts: softDeletedLegacyConflicts,
      );
    });
  }

  static String _canonicalPkEntryId(String pkGroupUuid, String pkMemberUuid) {
    final joined = '$pkGroupUuid\x00$pkMemberUuid';
    final digest = sha256.convert(utf8.encode(joined));
    return digest.toString().substring(0, 16);
  }

  /// Groups active PK-linked rows that still share the same PK UUID.
  Future<List<PkLinkedGroupDuplicateSet>>
  getActiveLinkedPkGroupDuplicateSets() async {
    final duplicateUuidRows = await customSelect(
      '''
      SELECT pluralkit_uuid
      FROM member_groups
      WHERE is_deleted = 0
        AND pluralkit_uuid IS NOT NULL
        AND pluralkit_uuid != ''
      GROUP BY pluralkit_uuid
      HAVING COUNT(*) > 1
      ''',
      readsFrom: {memberGroups},
    ).get();
    if (duplicateUuidRows.isEmpty) return const <PkLinkedGroupDuplicateSet>[];

    final duplicateUuids = duplicateUuidRows
        .map((row) => row.read<String>('pluralkit_uuid'))
        .toList(growable: false);
    final grouped = <String, List<MemberGroupRow>>{};

    for (
      var start = 0;
      start < duplicateUuids.length;
      start += _lookupBatchSize
    ) {
      final end = start + _lookupBatchSize > duplicateUuids.length
          ? duplicateUuids.length
          : start + _lookupBatchSize;
      final batch = duplicateUuids.sublist(start, end);
      if (batch.isEmpty) continue;

      final groups =
          await (select(memberGroups)..where(
                (g) => g.isDeleted.equals(false) & g.pluralkitUuid.isIn(batch),
              ))
              .get();
      for (final group in groups) {
        final pkGroupUuid = group.pluralkitUuid;
        if (pkGroupUuid == null || pkGroupUuid.isEmpty) continue;
        grouped.putIfAbsent(pkGroupUuid, () => <MemberGroupRow>[]).add(group);
      }
    }

    final duplicates = <PkLinkedGroupDuplicateSet>[];
    for (final entry in grouped.entries) {
      if (entry.value.length < 2) continue;
      entry.value.sort(_compareGroupRowsForRepair);
      duplicates.add(
        PkLinkedGroupDuplicateSet(pkGroupUuid: entry.key, groups: entry.value),
      );
    }
    duplicates.sort((a, b) => a.pkGroupUuid.compareTo(b.pkGroupUuid));
    return duplicates;
  }

  /// Re-home active membership rows from loser groups onto the chosen winner.
  ///
  /// Conflicting duplicate memberships are soft-deleted on the loser row after
  /// opportunistically filling missing PK UUID references on the winner row.
  Future<PkGroupEntryRehomeResult> rehomeEntriesToWinner({
    required String winnerGroupId,
    required List<String> loserGroupIds,
    required String canonicalPkGroupUuid,
  }) async {
    if (loserGroupIds.isEmpty) {
      return const PkGroupEntryRehomeResult();
    }

    return transaction(() async {
      final loserEntries =
          await (select(memberGroupEntries)..where(
                (e) =>
                    e.groupId.isIn(loserGroupIds) & e.isDeleted.equals(false),
              ))
              .get();
      if (loserEntries.isEmpty) return const PkGroupEntryRehomeResult();

      final memberIds = {
        for (final entry in loserEntries) entry.memberId,
      }.toList(growable: false);
      final winnerEntriesByMemberId = <String, MemberGroupEntryRow>{};
      for (var start = 0; start < memberIds.length; start += _lookupBatchSize) {
        final end = start + _lookupBatchSize > memberIds.length
            ? memberIds.length
            : start + _lookupBatchSize;
        final batch = memberIds.sublist(start, end);
        if (batch.isEmpty) continue;
        final winnerEntries =
            await (select(memberGroupEntries)..where(
                  (e) =>
                      e.groupId.equals(winnerGroupId) &
                      e.memberId.isIn(batch) &
                      e.isDeleted.equals(false),
                ))
                .get();
        for (final entry in winnerEntries) {
          winnerEntriesByMemberId[entry.memberId] = entry;
        }
      }

      var result = const PkGroupEntryRehomeResult();
      for (final entry in loserEntries) {
        final winnerEntry = winnerEntriesByMemberId[entry.memberId];

        if (winnerEntry != null) {
          final mergedPkMemberUuid = _coalesceNullableNonEmpty(
            winnerEntry.pkMemberUuid,
            entry.pkMemberUuid,
          );
          await (update(
            memberGroupEntries,
          )..where((e) => e.id.equals(winnerEntry.id))).write(
            MemberGroupEntriesCompanion(
              pkGroupUuid: Value(
                _coalesceNonEmpty(
                  winnerEntry.pkGroupUuid,
                  canonicalPkGroupUuid,
                ),
              ),
              pkMemberUuid: mergedPkMemberUuid == null
                  ? const Value.absent()
                  : Value(mergedPkMemberUuid),
            ),
          );
          await (update(memberGroupEntries)
                ..where((e) => e.id.equals(entry.id)))
              .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
          result = result.copyWith(
            softDeletedConflicts: result.softDeletedConflicts + 1,
          );
          continue;
        }

        await (update(
          memberGroupEntries,
        )..where((e) => e.id.equals(entry.id))).write(
          MemberGroupEntriesCompanion(
            groupId: Value(winnerGroupId),
            pkGroupUuid: Value(
              _coalesceNonEmpty(entry.pkGroupUuid, canonicalPkGroupUuid),
            ),
          ),
        );
        winnerEntriesByMemberId[entry.memberId] = entry.copyWith(
          groupId: winnerGroupId,
          pkGroupUuid: Value(
            _coalesceNonEmpty(entry.pkGroupUuid, canonicalPkGroupUuid),
          ),
        );
        result = result.copyWith(movedEntries: result.movedEntries + 1);
      }

      return result;
    });
  }

  /// Re-home active child-group references that currently point at loser rows.
  ///
  /// The winner row itself is excluded so we never create a self-parent loop.
  Future<int> rehomeParentReferencesToWinner({
    required String winnerGroupId,
    required List<String> loserGroupIds,
  }) async {
    if (loserGroupIds.isEmpty) return Future.value(0);

    return transaction(() async {
      final impactedChildren =
          await (select(memberGroups)..where(
                (g) =>
                    g.isDeleted.equals(false) &
                    g.parentGroupId.isIn(loserGroupIds) &
                    g.id.equals(winnerGroupId).not(),
              ))
              .get();
      if (impactedChildren.isEmpty) return 0;

      await customUpdate(
        '''
        UPDATE member_groups
        SET parent_group_id = ?
        WHERE is_deleted = 0
          AND parent_group_id IN (${_placeholders(loserGroupIds.length)})
          AND id <> ?
        ''',
        variables: [
          Variable.withString(winnerGroupId),
          ...loserGroupIds.map(Variable.withString),
          Variable.withString(winnerGroupId),
        ],
        updates: {memberGroups},
      );
      return impactedChildren.length;
    });
  }

  /// Soft-delete legacy loser rows after their memberships/children are
  /// re-homed.
  Future<int> softDeleteGroupsForRepair(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        is_deleted = 1,
        sync_suppressed = 1,
        suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
  }

  /// Mark active plain groups as local-only until the user reviews them.
  Future<int> markGroupsSuppressedForReview({
    required List<String> groupIds,
    required String suspectedPkGroupUuid,
  }) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        sync_suppressed = 1,
        suspected_pk_group_uuid = ?
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: [
        Variable.withString(suspectedPkGroupUuid),
        ...groupIds.map(Variable.withString),
      ],
      updates: {memberGroups},
    );
  }

  Future<List<MemberGroupRow>> getGroupsPendingPkReview() =>
      (select(memberGroups)
            ..where(
              (g) =>
                  g.isDeleted.equals(false) &
                  g.suspectedPkGroupUuid.isNotNull(),
            )
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .get();

  /// Clears a PK review item and restores the group to normal sync.
  Future<int> dismissGroupsFromPkReview(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        sync_suppressed = 0,
        suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
  }

  /// Keeps the row out of the review queue but leaves it suppressed locally.
  Future<int> keepGroupsLocalOnly(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
  }

  /// Converts a reviewed group into the canonical PK-linked row when needed.
  Future<void> linkGroupToPluralkitUuid({
    required String groupId,
    required String pluralkitUuid,
  }) async {
    await (update(memberGroups)..where((g) => g.id.equals(groupId))).write(
      MemberGroupsCompanion(
        syncSuppressed: const Value(false),
        suspectedPkGroupUuid: const Value(null),
        pluralkitUuid: Value(pluralkitUuid),
      ),
    );
  }

  /// Returns whether the group row is currently flagged to stay local-only.
  ///
  /// The `sync_suppressed` column is still landing across the schema in this
  /// workspace, so older builds of the table may not have it yet. In that
  /// case we treat every group as syncable.
  Future<bool> isGroupSyncSuppressed(String groupId) async {
    if (!await _supportsSyncSuppression()) return false;

    final rows = await customSelect(
      '''
      SELECT COALESCE($_syncSuppressedColumnName, 0) AS $_syncSuppressedColumnName
      FROM $_memberGroupsTableName
      WHERE id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(groupId)],
    ).get();

    if (rows.isEmpty) return false;

    final rawValue = attachedDatabase.typeMapping.read(
      DriftSqlType.bool,
      rows.single.data[_syncSuppressedColumnName],
    );
    return rawValue ?? false;
  }

  /// Live entries for a group, without streaming.
  Future<List<MemberGroupEntryRow>> entriesForGroup(String groupId) => (select(
    memberGroupEntries,
  )..where((e) => e.groupId.equals(groupId) & e.isDeleted.equals(false))).get();

  /// Insert-or-update a member group row. Used by the PK group importer to
  /// persist metadata updates; membership is reconciled via [upsertEntry] /
  /// [softDeleteEntry].
  Future<void> upsertGroup(MemberGroupsCompanion c) =>
      into(memberGroups).insertOnConflictUpdate(c);

  /// Insert-or-update a membership entry. The caller is responsible for
  /// choosing the primary key (deterministic sha256 for PK-originated entries,
  /// see plan R6). Re-activates a soft-deleted entry on conflict.
  Future<void> upsertEntry(MemberGroupEntriesCompanion c) =>
      into(memberGroupEntries).insertOnConflictUpdate(c);

  /// Soft-delete a membership entry by id.
  Future<void> softDeleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
        const MemberGroupEntriesCompanion(isDeleted: Value(true)),
      );

  Future<List<MemberGroupRow>> getDirectChildrenOf(String parentGroupId) =>
      (select(memberGroups)
            ..where((g) => g.parentGroupId.equals(parentGroupId))
            ..where((g) => g.isDeleted.equals(false)))
          .get();

  Stream<List<MemberGroupRow>> watchChildGroups(String? parentGroupId) =>
      (select(memberGroups)
            ..where(
              (g) => parentGroupId == null
                  ? g.parentGroupId.isNull()
                  : g.parentGroupId.equals(parentGroupId),
            )
            ..where((g) => g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .watch();

  /// Next `display_order` scoped to siblings sharing the same [parentGroupId].
  /// Returns 0 when no siblings exist.
  Future<int> nextDisplayOrder(String? parentGroupId) async {
    final sql = parentGroupId == null
        ? 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM member_groups WHERE is_deleted = 0 AND parent_group_id IS NULL'
        : 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM member_groups WHERE is_deleted = 0 AND parent_group_id = ?';
    final rows = await customSelect(
      sql,
      variables: parentGroupId != null
          ? [Variable.withString(parentGroupId)]
          : [],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('next');
  }

  Future<bool> _supportsSyncSuppression() async {
    final cached = _hasSyncSuppressedColumn;
    if (cached != null) return cached;

    final rows = await customSelect(
      'PRAGMA table_info($_memberGroupsTableName)',
    ).get();
    final hasColumn = rows.any(
      (row) => row.data['name'] == _syncSuppressedColumnName,
    );
    _hasSyncSuppressedColumn = hasColumn;
    return hasColumn;
  }

  static int _compareGroupRowsForRepair(
    MemberGroupRow left,
    MemberGroupRow right,
  ) {
    final createdAtCompare = left.createdAt.compareTo(right.createdAt);
    if (createdAtCompare != 0) return createdAtCompare;
    return left.id.compareTo(right.id);
  }

  static int _compareActivePkLookupRows(
    MemberGroupRow left,
    MemberGroupRow right,
  ) {
    if (left.syncSuppressed != right.syncSuppressed) {
      return left.syncSuppressed ? 1 : -1;
    }

    if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt == null) {
      return -1;
    }
    if (left.lastSeenFromPkAt == null && right.lastSeenFromPkAt != null) {
      return 1;
    }
    if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt != null) {
      final seenCompare = right.lastSeenFromPkAt!.compareTo(
        left.lastSeenFromPkAt!,
      );
      if (seenCompare != 0) return seenCompare;
    }

    final createdAtCompare = left.createdAt.compareTo(right.createdAt);
    if (createdAtCompare != 0) return createdAtCompare;
    return left.id.compareTo(right.id);
  }

  static String _coalesceNonEmpty(String? primary, String fallback) {
    if (primary != null && primary.isNotEmpty) return primary;
    return fallback;
  }

  static String? _coalesceNullableNonEmpty(String? primary, String? fallback) {
    if (primary != null && primary.isNotEmpty) return primary;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}
