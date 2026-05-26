import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
// `markInboxOpenedFor` writes `boardLastReadAt` on the members table via
// the dedicated atomic-conditional DAO method; the dependency on the
// members DAO is intentional (kept narrow to one method on one table).
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/mappers/member_board_post_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';

class DriftMemberBoardPostsRepository
    with SyncRecordMixin
    implements MemberBoardPostsRepository {
  final MemberBoardPostsDao _dao;
  final MembersDao _membersDao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'member_board_posts';
  static const _membersTable = 'members';

  DriftMemberBoardPostsRepository(
    this._dao,
    this._membersDao,
    this._syncHandle,
  );

  // ---------------------------------------------------------------------------
  // Read streams
  // ---------------------------------------------------------------------------

  @override
  Stream<List<MemberBoardPost>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    return _dao
        .watchPublicPaginated(
          afterWrittenAt: afterWrittenAt,
          afterId: afterId,
          limit: limit,
        )
        .map((rows) => rows.map(MemberBoardPostMapper.toDomain).toList());
  }

  @override
  Stream<List<MemberBoardPost>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    return _dao
        .watchInboxPaginated(
          targetMemberIds,
          afterWrittenAt: afterWrittenAt,
          afterId: afterId,
          limit: limit,
        )
        .map((rows) => rows.map(MemberBoardPostMapper.toDomain).toList());
  }

  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    return _dao
        .watchPublicForMemberPaginated(
          memberId,
          afterWrittenAt: afterWrittenAt,
          afterId: afterId,
          limit: limit,
        )
        .map((rows) => rows.map(MemberBoardPostMapper.toDomain).toList());
  }

  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  }) {
    return _dao
        .watchPublicForMemberRecent(memberId, limit: limit)
        .map((rows) => rows.map(MemberBoardPostMapper.toDomain).toList());
  }

  @override
  Stream<MemberBoardPost?> watchPostById(String id) {
    return _dao
        .watchPostById(id)
        .map((row) => row != null ? MemberBoardPostMapper.toDomain(row) : null);
  }

  // ---------------------------------------------------------------------------
  // Point reads
  // ---------------------------------------------------------------------------

  @override
  Future<MemberBoardPost?> getPostById(String id) async {
    final row = await _dao.getPostById(id);
    return row != null ? MemberBoardPostMapper.toDomain(row) : null;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createPost(MemberBoardPost post) async {
    assert(
      post.audience == 'public' || post.audience == 'private',
      'audience must be exactly "public" or "private", got "${post.audience}"',
    );
    final companion = MemberBoardPostMapper.toCompanion(post);
    await _dao.createPost(companion);
    await syncRecordCreate(_table, post.id, _postFields(post));
  }

  @override
  Future<void> updatePost(MemberBoardPost post) async {
    assert(
      post.audience == 'public' || post.audience == 'private',
      'audience must be exactly "public" or "private", got "${post.audience}"',
    );
    // The DAO read path does not filter tombstoned rows, so a stale caller
    // can hand us a domain object carrying `isDeleted: true`. Refusing the
    // edit here is the last line of defense — without it the diff-based
    // update path would silently strip `is_deleted` (owned by
    // `syncRecordDelete` / `syncRecordCreate`) and resurrect the post on
    // peers via a fresh-HLC write to the surviving fields.
    final existingRow = await _dao.getPostById(post.id);
    if (existingRow == null || existingRow.isDeleted) return;

    final changedFields = diffSyncFields(
      _postFieldsFromRow(existingRow),
      _postFields(post),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialPostCompanion(changedFields);
    await _dao.updatePost(post.id, companion);
    await syncRecordUpdate(_table, post.id, changedFields);
  }

  @override
  Future<void> softDeletePost(String id) async {
    await _dao.softDeletePost(id);
    // Soft-delete emits a syncRecordUpdate (not syncRecordDelete) so the
    // tombstone is a field-level LWW write, not an entity-level hard delete.
    await syncRecordUpdate(_table, id, {'is_deleted': true});
  }

  // ---------------------------------------------------------------------------
  // Read-state — mark inbox opened
  // ---------------------------------------------------------------------------

  @override
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {
    if (activeFronterIds.isEmpty) return;
    // Snapshot the list immediately so a fronter de-fronting between dispatch
    // and execution does not get marked-read after the fact.
    final memberIds = List<String>.unmodifiable(activeFronterIds);
    final now = DateTime.now().toUtc();
    final nowIso = toSyncUtc(now);

    // Two-step shape: (1) atomic conditional DAO update — `WHERE
    // boardLastReadAt IS NULL OR < now` — that protects the local row
    // from regressing under concurrent callers, and returns the subset
    // of members whose row was actually written. (2) Emit one narrow
    // `{board_last_read_at: now}` patch per actually-updated member.
    //
    // The earlier read-then-route-through-updateMemberFields shape had a
    // TOCTOU window: two overlapping `markInboxOpenedFor` calls could
    // each pass the pre-read freshness check, then race to write and
    // regress the local stamp. The conditional DAO update closes that.
    final updatedIds = await _membersDao.setBoardLastReadAtIfOlder(
      memberIds,
      now,
    );
    if (updatedIds.isEmpty) return;
    await withSyncBatch(() async {
      for (final memberId in updatedIds) {
        await syncRecordUpdate(_membersTable, memberId, {
          'board_last_read_at': nowIso,
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Visible-for-testing field map
  // ---------------------------------------------------------------------------

  /// Builds the field map handed to the Rust sync engine for create/update.
  ///
  /// Exposed so regression tests can pin every emitted field — including
  /// nullable fields and the `is_deleted` tombstone — matching the
  /// `debugNoteFields` pattern in `drift_notes_repository.dart`.
  @visibleForTesting
  Map<String, dynamic> debugPostFields(MemberBoardPost p) => _postFields(p);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _postFields(MemberBoardPost p) => postFields(p);

  /// Mirror of [postFields] keyed off the raw Drift row. Used by the
  /// patch-style update path to diff the stored row against the
  /// incoming domain object so the wire-side emission only carries
  /// the fields the writer actually changed. Includes `is_deleted`
  /// so the diff sees the stored tombstone value; `diffSyncFields`
  /// strips that key from the patch unconditionally.
  Map<String, dynamic> _postFieldsFromRow(MemberBoardPostRow row) {
    return {
      'target_member_id': row.targetMemberId,
      'author_id': row.authorId,
      'audience': row.audience,
      'title': row.title,
      'body': row.body,
      'created_at': toSyncUtc(row.createdAt),
      'written_at': toSyncUtc(row.writtenAt),
      'edited_at': toSyncUtcOrNull(row.editedAt),
      'is_deleted': row.isDeleted,
    };
  }

  /// Build a sparse [MemberBoardPostsCompanion] from a patch map keyed
  /// by sync-wire column names. Only keys present in [patch] are
  /// written; anything else stays `Value.absent()` so untouched columns
  /// are preserved on disk. DateTime columns route through
  /// [parseSyncDateTime] so a caller that hands us either an ISO
  /// string (the wire format) or a raw `DateTime` (internal Dart
  /// callers) round-trips correctly.
  MemberBoardPostsCompanion _partialPostCompanion(Map<String, dynamic> patch) {
    return MemberBoardPostsCompanion(
      targetMemberId: patch.containsKey('target_member_id')
          ? Value(patch['target_member_id'] as String?)
          : const Value.absent(),
      authorId: patch.containsKey('author_id')
          ? Value(patch['author_id'] as String?)
          : const Value.absent(),
      audience: patch.containsKey('audience')
          ? Value(patch['audience'] as String)
          : const Value.absent(),
      title: patch.containsKey('title')
          ? Value(patch['title'] as String?)
          : const Value.absent(),
      body: patch.containsKey('body')
          ? Value(patch['body'] as String)
          : const Value.absent(),
      createdAt: patch.containsKey('created_at')
          ? Value(parseSyncDateTime(patch['created_at']))
          : const Value.absent(),
      writtenAt: patch.containsKey('written_at')
          ? Value(parseSyncDateTime(patch['written_at']))
          : const Value.absent(),
      editedAt: patch.containsKey('edited_at')
          ? Value(_parseSyncDateTimeOrNull(patch['edited_at']))
          : const Value.absent(),
    );
  }

  DateTime? _parseSyncDateTimeOrNull(Object? value) {
    if (value == null) return null;
    return parseSyncDateTime(value);
  }

  /// Field-map builder for member-board-post sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createPost()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> postFields(MemberBoardPost p) {
    return {
      'target_member_id': p.targetMemberId,
      'author_id': p.authorId,
      'audience': p.audience,
      'title': p.title,
      'body': p.body,
      'created_at': toSyncUtc(p.createdAt),
      'written_at': toSyncUtc(p.writtenAt),
      'edited_at': toSyncUtcOrNull(p.editedAt),
      'is_deleted': p.isDeleted,
    };
  }
}
