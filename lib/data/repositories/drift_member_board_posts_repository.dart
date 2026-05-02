import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/mappers/member_board_post_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
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
    final companion = MemberBoardPostMapper.toCompanion(post);
    await _dao.updatePost(post.id, companion);
    await syncRecordUpdate(_table, post.id, _postFields(post));
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

    // Write boardLastReadAt for every active fronter atomically, then emit
    // sync ops grouped under one logical batch so peers see the inbox-opened
    // action as a single CRDT event.
    await _membersDao.transaction(() async {
      for (final memberId in memberIds) {
        await _membersDao.updateMember(
          MembersCompanion(
            id: Value(memberId),
            boardLastReadAt: Value(now),
          ),
        );
      }
    });
    await withSyncBatch(() async {
      for (final memberId in memberIds) {
        await syncRecordUpdate(_membersTable, memberId, {
          'board_last_read_at': toSyncUtc(now),
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

  Map<String, dynamic> _postFields(MemberBoardPost p) {
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
