import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/members_table.dart';

part 'members_dao.g.dart';

final class MemberAvatarMetadata {
  const MemberAvatarMetadata({
    required this.id,
    required this.isDeleted,
    required this.avatarByteLength,
  });

  final String id;
  final bool isDeleted;
  final int? avatarByteLength;
}

@DriftAccessor(tables: [Members])
class MembersDao extends DatabaseAccessor<AppDatabase> with _$MembersDaoMixin {
  MembersDao(super.db);

  static const _memberListColumns = '''
    id,
    name,
    pronouns,
    emoji,
    NULL AS age,
    NULL AS bio,
    NULL AS avatar_image_data,
    pk_avatar_cached_url,
    is_active,
    created_at,
    display_order,
    is_admin,
    custom_color_enabled,
    custom_color_hex,
    parent_system_id,
    pluralkit_uuid,
    pluralkit_id,
    pluralkit_display_name,
    display_name,
    birthday,
    proxy_tags_json,
    pk_banner_url,
    profile_header_source,
    profile_header_layout,
    profile_header_visible,
    name_style_font,
    name_style_bold,
    name_style_italic,
    name_style_color_mode,
    name_style_color_hex,
    NULL AS profile_header_image_data,
    NULL AS pk_banner_image_data,
    pk_banner_cached_url,
    pluralkit_sync_ignored,
    markdown_enabled,
    is_deleted,
    delete_intent_epoch,
    delete_push_started_at,
    is_always_fronting,
    board_last_read_at
  ''';

  static const _memberPkSyncColumns = '''
    id,
    name,
    pronouns,
    emoji,
    NULL AS age,
    bio,
    NULL AS avatar_image_data,
    pk_avatar_cached_url,
    is_active,
    created_at,
    display_order,
    is_admin,
    custom_color_enabled,
    custom_color_hex,
    parent_system_id,
    pluralkit_uuid,
    pluralkit_id,
    pluralkit_display_name,
    display_name,
    birthday,
    proxy_tags_json,
    pk_banner_url,
    profile_header_source,
    profile_header_layout,
    profile_header_visible,
    name_style_font,
    name_style_bold,
    name_style_italic,
    name_style_color_mode,
    name_style_color_hex,
    NULL AS profile_header_image_data,
    NULL AS pk_banner_image_data,
    pk_banner_cached_url,
    pluralkit_sync_ignored,
    markdown_enabled,
    is_deleted,
    delete_intent_epoch,
    delete_push_started_at,
    is_always_fronting,
    board_last_read_at
  ''';

  Future<List<Member>> getAllMembers() =>
      (select(members)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .get();

  /// Like [getAllMembers] but includes soft-deleted tombstones. `idx_members_
  /// pluralkit_uuid` covers tombstones (no `is_deleted = 0` clause), so deduping
  /// by uuid off the active-only set would let an import hit the unique index and
  /// roll back the transaction. `idx_members_pluralkit_id` narrowed to active-only
  /// at v40 (short ids recyclable); importers still read tombstones here to reason
  /// about short-id reuse and delete intent.
  Future<List<Member>> getAllMembersIncludingDeleted() => select(members).get();

  Stream<List<Member>> watchAllMembers() =>
      (select(members)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .watch();

  Stream<List<Member>> watchActiveMembers() =>
      (select(members)
            ..where((m) => m.isActive.equals(true) & m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .watch();

  Stream<List<Member>> watchAllMembersForList() =>
      _watchMemberListRows('is_deleted = 0');

  Stream<List<Member>> watchActiveMembersForList() =>
      _watchMemberListRows('is_active = 1 AND is_deleted = 0');

  Stream<List<Member>> watchAllMembersForPkSync() {
    return customSelect(
      '''
      SELECT $_memberPkSyncColumns
      FROM members
      WHERE is_deleted = 0
      ORDER BY display_order ASC
      ''',
      readsFrom: {members},
    ).watch().map((rows) => rows.map((row) => members.map(row.data)).toList());
  }

  Stream<List<Member>> watchQuickFrontMembersForList({
    int recentLimit = 50,
    int suggestionLimit = 12,
    required String excludedSuggestionMemberId,
  }) {
    return customSelect(
      '''
      WITH current_fronts AS (
        SELECT member_id, MAX(start_time) AS current_started_at
        FROM fronting_sessions
        WHERE session_type = 0
          AND end_time IS NULL
          AND is_deleted = 0
          AND member_id IS NOT NULL
        GROUP BY member_id
      ),
      recent_sessions AS (
        SELECT member_id
        FROM fronting_sessions
        WHERE session_type = 0
          AND is_deleted = 0
          AND member_id IS NOT NULL
        ORDER BY start_time DESC
        LIMIT ?
      ),
      recent_counts AS (
        SELECT member_id, COUNT(*) AS front_count
        FROM recent_sessions
        GROUP BY member_id
      ),
      frequent_ids AS (
        SELECT
          members.id,
          COALESCE(recent_counts.front_count, 0) AS front_count
        FROM members
        LEFT JOIN current_fronts
          ON current_fronts.member_id = members.id
        LEFT JOIN recent_counts
          ON recent_counts.member_id = members.id
        WHERE members.is_active = 1
          AND members.is_deleted = 0
          AND current_fronts.member_id IS NULL
          AND members.id != ?
        ORDER BY front_count DESC, members.display_order ASC, members.id ASC
        LIMIT ?
      ),
      ranked AS (
        SELECT
          $_memberListColumns,
          0 AS group_order,
          current_fronts.current_started_at AS current_started_at,
          0 AS front_count
        FROM members
        JOIN current_fronts ON current_fronts.member_id = members.id
        WHERE members.is_deleted = 0

        UNION ALL

        SELECT
          $_memberListColumns,
          1 AS group_order,
          NULL AS current_started_at,
          (
            SELECT frequent_ids.front_count
            FROM frequent_ids
            WHERE frequent_ids.id = members.id
          ) AS front_count
        FROM members
        WHERE members.id IN (SELECT id FROM frequent_ids)
      )
      SELECT $_memberListColumns
      FROM ranked
      ORDER BY
        group_order ASC,
        CASE WHEN group_order = 0 THEN current_started_at END DESC,
        CASE WHEN group_order = 1 THEN front_count END DESC,
        display_order ASC,
        id ASC
      ''',
      variables: [
        Variable.withInt(recentLimit),
        Variable.withString(excludedSuggestionMemberId),
        Variable.withInt(suggestionLimit),
      ],
      readsFrom: {members, attachedDatabase.frontingSessions},
    ).watch().map((rows) => rows.map((row) => members.map(row.data)).toList());
  }

  Stream<List<Member>> _watchMemberListRows(String whereClause) {
    return customSelect(
      '''
      SELECT $_memberListColumns
      FROM members
      WHERE $whereClause
      ORDER BY display_order ASC
      ''',
      readsFrom: {members},
    ).watch().map((rows) => rows.map((row) => members.map(row.data)).toList());
  }

  Future<Member?> getMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Single-row read by ID, including tombstones. Repository writers use
  /// this to guard sync emission for missing/tombstoned rows. Alias for
  /// [getMemberById] — same query — provided so the patch-style update
  /// path reads as `getMemberByIdRow` consistently with peer repos
  /// (`getHabitByIdRow`, `getCompletionByIdRow`).
  Future<Member?> getMemberByIdRow(String id) => getMemberById(id);

  Stream<Member?> watchMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).watchSingleOrNull();

  Stream<Uint8List?> watchAvatarImageData(String id) {
    return customSelect(
      '''
      SELECT avatar_image_data
      FROM members
      WHERE id = ? AND is_deleted = 0
      LIMIT 1
      ''',
      variables: [Variable.withString(id)],
      readsFrom: {members},
    ).watchSingleOrNull().map(
      (row) => row?.read<Uint8List?>('avatar_image_data'),
    );
  }

  Future<int> insertMember(MembersCompanion member) =>
      into(members).insert(member);

  /// Inserts at the end of the display order, including tombstones.
  Future<int> insertMemberAtEnd(MembersCompanion member) async {
    return transaction(() async {
      final nextOrder = await nextDisplayOrderIncludingDeleted();
      await into(
        members,
      ).insert(member.copyWith(displayOrder: Value(nextOrder)));
      return nextOrder;
    });
  }

  /// Batch-insert members in a single Drift `batch()` round-trip.
  ///
  /// Used by the SP importer's Phase 6 capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`) to collapse N per-member
  /// inserts into one DAO call. Bypasses [DriftMemberRepository.createMember],
  /// so the caller is responsible for pushing a captured op tuple per row
  /// using [DriftMemberRepository.memberFields]. The SP importer pre-filters
  /// rows whose ID already exists, so plain `insertAll` (no conflict policy)
  /// is correct here — re-using the per-row `insertMember` policy.
  Future<void> batchInsertMembers(List<MembersCompanion> rows) async {
    if (rows.isEmpty) return;
    // insertOrIgnore, not plain insert: SP member ids are now deterministic (v5
    // from the SP _id), so a re-import after sp_id_map was cleared can re-derive
    // an already-present id. Ignore the dup (same member) rather than aborting
    // the whole import; a no-op for random-id rows that never collided.
    await batch(
      (b) => b.insertAll(members, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  /// Bulk-update `boardLastReadAt` per (memberId, readAt) pair in a single
  /// Drift batch. The caller is responsible for preserving LWW semantics by
  /// passing only rows whose current `boardLastReadAt` is null or older than
  /// the supplied value.
  ///
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchUpdateBoardLastReadAt(
    Map<String, DateTime> readAtByMemberId,
  ) async {
    if (readAtByMemberId.isEmpty) return;
    await batch((b) {
      for (final entry in readAtByMemberId.entries) {
        b.update(
          members,
          MembersCompanion(boardLastReadAt: Value(entry.value)),
          where: (m) => m.id.equals(entry.key),
        );
      }
    });
  }

  /// Atomic-per-row variant: write `now` into `boardLastReadAt` only for
  /// active members whose current value is null or strictly older than
  /// `now`. The conditional `WHERE` is evaluated and the write applied as
  /// one SQL statement per row, so two concurrent callers cannot regress a
  /// newer stamp to an older one — the loser's `WHERE` excludes the row
  /// that already holds the winner's stamp.
  ///
  /// Returns the subset of `memberIds` whose row was actually updated, so
  /// the caller can emit `syncRecordUpdate` only for those members (and
  /// not waste CRDT ops on rows where the LWW guard already short-
  /// circuited the local write).
  Future<List<String>> setBoardLastReadAtIfOlder(
    List<String> memberIds,
    DateTime now,
  ) async {
    if (memberIds.isEmpty) return const [];
    final updated = <String>[];
    await transaction(() async {
      for (final memberId in memberIds) {
        final affected =
            await (update(members)..where(
                  (m) =>
                      m.id.equals(memberId) &
                      m.isDeleted.equals(false) &
                      (m.boardLastReadAt.isNull() |
                          m.boardLastReadAt.isSmallerThanValue(now)),
                ))
                .write(MembersCompanion(boardLastReadAt: Value(now)));
        if (affected > 0) updated.add(memberId);
      }
    });
    return updated;
  }

  Future<void> updateMember(MembersCompanion member) {
    assert(member.id.present, 'Member id is required for update');
    return (update(
      members,
    )..where((m) => m.id.equals(member.id.value))).write(member);
  }

  /// Update an active member by ID with a sparse companion. Returns the
  /// affected row count (0 if the row is tombstoned or missing, 1 on
  /// success). The `is_deleted = false` predicate is the tombstone
  /// guard — Drift `write` on a tombstoned row returns 0, letting the
  /// repository skip sync emission and avoid resurrection.
  Future<int> updateMemberById(String id, MembersCompanion companion) =>
      (update(members)
            ..where((m) => m.id.equals(id) & m.isDeleted.equals(false)))
          .write(companion);

  /// Bulk-update display orders in one SQL statement.
  ///
  /// Reordering can touch many rows in large systems; updating them one at a
  /// time forces repeated Drift write plumbing and makes drag/drop feel laggy.
  /// This keeps the database work to a single statement while callers still
  /// emit the corresponding sync ops per changed member.
  Future<void> bulkUpdateDisplayOrders(Map<String, int> displayOrders) async {
    if (displayOrders.isEmpty) return;

    final ids = displayOrders.keys.toList(growable: false);
    final whenClauses = ids.map((_) => 'WHEN ? THEN ?').join(' ');
    final wherePlaceholders = List.filled(ids.length, '?').join(', ');
    final variables = <Variable>[];

    for (final entry in displayOrders.entries) {
      variables.add(Variable.withString(entry.key));
      variables.add(Variable.withInt(entry.value));
    }
    variables.addAll(ids.map(Variable.withString));

    await customUpdate(
      '''
      UPDATE members
      SET display_order = CASE id
        $whenClauses
        ELSE display_order
      END
      WHERE id IN ($wherePlaceholders)
      ''',
      variables: variables,
      updates: {members},
    );
  }

  Future<void> upsertMember(MembersCompanion member) =>
      into(members).insertOnConflictUpdate(member);

  /// Bulk-update `avatarImageData` for many members in a single Drift batch.
  ///
  /// Replaces N round-tripped `update(...)` calls with one batched statement.
  /// Used by the SP importer's parallel avatar phase
  /// (`sp_importer.dart:_downloadAvatars`); callers are expected to emit the
  /// matching `syncRecordUpdate` per member after the batch returns so the
  /// emission shape on the wire is unchanged.
  Future<void> batchUpdateAvatars(Map<String, Uint8List> bytesById) async {
    if (bytesById.isEmpty) return;
    await batch((b) {
      for (final entry in bytesById.entries) {
        b.update(
          members,
          MembersCompanion(avatarImageData: Value(entry.value)),
          where: (m) => m.id.equals(entry.key),
        );
      }
    });
  }

  Future<List<MemberAvatarMetadata>> getAvatarMetadataByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];

    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await customSelect(
      '''
      SELECT id, is_deleted, LENGTH(avatar_image_data) AS avatar_byte_length
      FROM members
      WHERE id IN ($placeholders)
      ''',
      variables: ids.map(Variable.withString).toList(growable: false),
      readsFrom: {members},
    ).get();

    return [
      for (final row in rows)
        MemberAvatarMetadata(
          id: row.read<String>('id'),
          isDeleted: row.read<bool>('is_deleted'),
          avatarByteLength: row.read<int?>('avatar_byte_length'),
        ),
    ];
  }

  Future<Map<String, Uint8List>> getAvatarBytesByIds(List<String> ids) async {
    if (ids.isEmpty) return const {};

    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await customSelect(
      '''
      SELECT id, avatar_image_data
      FROM members
      WHERE id IN ($placeholders) AND is_deleted = 0
      ''',
      variables: ids.map(Variable.withString).toList(growable: false),
      readsFrom: {members},
    ).get();

    final result = <String, Uint8List>{};
    for (final row in rows) {
      final bytes = row.read<Uint8List?>('avatar_image_data');
      if (bytes != null) result[row.read<String>('id')] = bytes;
    }
    return result;
  }

  Future<void> softDeleteMember(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        const MembersCompanion(isDeleted: Value(true)),
      );

  /// Tombstoned members that still carry a PK link and a delete
  /// intent stamped under some link epoch. Callers must additionally gate
  /// by `deleteIntentEpoch == state.linkEpoch` at push time — this
  /// query surfaces the candidate set only.
  Future<List<Member>> getDeletedLinkedMembers() =>
      (select(members)..where(
            (m) =>
                m.isDeleted.equals(true) &
                m.pluralkitId.isNotNull() &
                m.deleteIntentEpoch.isNotNull(),
          ))
          .get();

  /// Live local sessions for a member that still point at PK. Used
  /// by the cascade guard: if any exist when we want to push a member
  /// DELETE, we skip the member DELETE this pass to keep PK's cascade from
  /// silently deleting switches Prism still considers live.
  Future<List<FrontingSession>> _getLiveLinkedSessionsForMember(
    String memberId,
  ) =>
      (select(attachedDatabase.frontingSessions)..where(
            (s) =>
                s.memberId.equals(memberId) &
                s.isDeleted.equals(false) &
                s.pluralkitUuid.isNotNull(),
          ))
          .get();

  /// Plan 02 R5 hook — convenience wrapper.
  Future<bool> hasLiveLinkedSessionsForMember(String memberId) async {
    final rows = await _getLiveLinkedSessionsForMember(memberId);
    return rows.isNotEmpty;
  }

  /// Plan 02 R3: clear the PK link on a tombstone (row stays `is_deleted = 1`).
  /// Bypasses the `is_deleted = false` filter that exists on most writers so
  /// the cleanup runs after the tombstone was written. Callers should route
  /// via the repository's `clearPluralKitLink` so a CRDT op is also emitted.
  Future<void> clearPluralKitLinkRaw(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        const MembersCompanion(
          pluralkitId: Value(null),
          pluralkitUuid: Value(null),
        ),
      );

  /// Plan 02 R1: stamp delete intent on a member tombstone. Called in the
  /// same transaction as `softDeleteMember` by the repository.
  Future<void> stampDeleteIntent(String id, int epoch) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(deleteIntentEpoch: Value(epoch)),
      );

  /// Plan 02 R6: stamp the cross-device coordination timestamp. Callers
  /// should route this through `syncRecordUpdate` as well so other devices
  /// see it. The DAO-level write is the local half.
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(deletePushStartedAt: Value(timestampMs)),
      );

  /// F4: stamp the create-push lease. Callers route it through `syncRecordUpdate`
  /// too so other devices see it.
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(createPushStartedAt: Value(timestampMs)),
      );

  /// F4: clear the create-push lease once the create completes or is adopted.
  Future<void> clearCreatePushStartedAt(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        const MembersCompanion(createPushStartedAt: Value(null)),
      );

  Future<List<Member>> getMembersByIds(List<String> ids) =>
      (select(members)..where((m) => m.id.isIn(ids))).get();

  Stream<List<Member>> watchMembersByIds(List<String> ids) =>
      (select(members)..where((m) => m.id.isIn(ids))).watch();

  Stream<List<Member>> watchMembersByIdsForList(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <Member>[]);

    final placeholders = List.filled(ids.length, '?').join(', ');
    return customSelect(
      '''
      SELECT $_memberListColumns
      FROM members
      WHERE id IN ($placeholders)
      ''',
      variables: ids.map(Variable.withString).toList(),
      readsFrom: {members},
    ).watch().map((rows) => rows.map((row) => members.map(row.data)).toList());
  }

  Future<List<Member>> getSubsystemMembers(String parentId) =>
      (select(members)..where(
            (m) =>
                m.parentSystemId.equals(parentId) & m.isDeleted.equals(false),
          ))
          .get();

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(members)
      ..where(members.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }

  Future<int> nextDisplayOrderIncludingDeleted() async {
    final rows = await customSelect(
      'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM members',
      readsFrom: {members},
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('next');
  }
}
