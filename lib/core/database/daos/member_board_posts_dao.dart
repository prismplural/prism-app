import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/member_board_posts_table.dart';

part 'member_board_posts_dao.g.dart';

@DriftAccessor(tables: [MemberBoardPosts])
class MemberBoardPostsDao extends DatabaseAccessor<AppDatabase>
    with _$MemberBoardPostsDaoMixin {
  MemberBoardPostsDao(super.db);

  // ---------------------------------------------------------------------------
  // Public timeline — paginated via keyset cursor (written_at DESC, id DESC)
  // ---------------------------------------------------------------------------

  Stream<List<MemberBoardPostRow>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    final q =
        select(memberBoardPosts)
          ..where(
            (p) =>
                p.audience.equals('public') &
                p.isDeleted.equals(false) &
                _keysetWhere(p, afterWrittenAt, afterId),
          )
          ..orderBy([
            (p) => OrderingTerm.desc(p.writtenAt),
            (p) => OrderingTerm.desc(p.id),
          ])
          ..limit(limit);
    return q.watch();
  }

  // ---------------------------------------------------------------------------
  // Inbox — private posts addressed to any of the given members (paginated)
  // ---------------------------------------------------------------------------

  Stream<List<MemberBoardPostRow>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    if (targetMemberIds.isEmpty) {
      return const Stream.empty();
    }
    final q =
        select(memberBoardPosts)
          ..where(
            (p) =>
                p.audience.equals('private') &
                p.targetMemberId.isIn(targetMemberIds) &
                p.isDeleted.equals(false) &
                _keysetWhere(p, afterWrittenAt, afterId),
          )
          ..orderBy([
            (p) => OrderingTerm.desc(p.writtenAt),
            (p) => OrderingTerm.desc(p.id),
          ])
          ..limit(limit);
    return q.watch();
  }

  // ---------------------------------------------------------------------------
  // Per-member public board — paginated
  //
  // WHERE (target_member_id = :memberId OR author_id = :memberId)
  //       AND audience = 'public' AND is_deleted = false
  // ---------------------------------------------------------------------------

  Stream<List<MemberBoardPostRow>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    final q =
        select(memberBoardPosts)
          ..where(
            (p) =>
                (p.targetMemberId.equals(memberId) | p.authorId.equals(memberId)) &
                p.audience.equals('public') &
                p.isDeleted.equals(false) &
                _keysetWhere(p, afterWrittenAt, afterId),
          )
          ..orderBy([
            (p) => OrderingTerm.desc(p.writtenAt),
            (p) => OrderingTerm.desc(p.id),
          ])
          ..limit(limit);
    return q.watch();
  }

  // ---------------------------------------------------------------------------
  // Per-member public board — recent (profile section preview)
  //
  // Same WHERE as watchPublicForMemberPaginated; no keyset (always first page).
  // ---------------------------------------------------------------------------

  Stream<List<MemberBoardPostRow>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  }) {
    final q =
        select(memberBoardPosts)
          ..where(
            (p) =>
                (p.targetMemberId.equals(memberId) | p.authorId.equals(memberId)) &
                p.audience.equals('public') &
                p.isDeleted.equals(false),
          )
          ..orderBy([
            (p) => OrderingTerm.desc(p.writtenAt),
            (p) => OrderingTerm.desc(p.id),
          ])
          ..limit(limit);
    return q.watch();
  }

  // ---------------------------------------------------------------------------
  // Single-post watch / fetch
  // ---------------------------------------------------------------------------

  Stream<MemberBoardPostRow?> watchPostById(String id) =>
      (select(memberBoardPosts)..where((p) => p.id.equals(id)))
          .watchSingleOrNull();

  Future<MemberBoardPostRow?> getPostById(String id) =>
      (select(memberBoardPosts)..where((p) => p.id.equals(id)))
          .getSingleOrNull();

  // ---------------------------------------------------------------------------
  // Badge / unread counts
  // ---------------------------------------------------------------------------

  /// Count of unread private posts for the given members.
  ///
  /// A post is "unread" for a member when its `written_at` is AFTER that
  /// member's `boardLastReadAt` (or when `boardLastReadAt` is null, meaning
  /// the member has never opened the inbox — all posts count as unread).
  Future<int> countUnreadForMembers(
    List<String> memberIds,
    Map<String, DateTime?> lastReadByMember,
  ) async {
    if (memberIds.isEmpty) return 0;

    var total = 0;
    for (final memberId in memberIds) {
      final lastRead = lastReadByMember[memberId];
      final countExpr = memberBoardPosts.id.count();
      final query =
          selectOnly(memberBoardPosts)
            ..addColumns([countExpr])
            ..where(
              memberBoardPosts.audience.equals('private') &
                  memberBoardPosts.targetMemberId.equals(memberId) &
                  memberBoardPosts.isDeleted.equals(false) &
                  (lastRead == null
                      ? const Constant<bool>(true)
                      : memberBoardPosts.writtenAt.isBiggerThanValue(lastRead)),
            );
      final row = await query.getSingle();
      total += row.read(countExpr) ?? 0;
    }
    return total;
  }

  /// Count of public posts written since [lastViewedAt].
  ///
  /// Used to drive the "unread dot" on the Public sub-tab segment label.
  /// Returns all public posts when [lastViewedAt] is null (first open).
  Future<int> countNewPublicSince(DateTime? lastViewedAt) async {
    final countExpr = memberBoardPosts.id.count();
    final query =
        selectOnly(memberBoardPosts)
          ..addColumns([countExpr])
          ..where(
            memberBoardPosts.audience.equals('public') &
                memberBoardPosts.isDeleted.equals(false) &
                (lastViewedAt == null
                    ? const Constant<bool>(true)
                    : memberBoardPosts.writtenAt.isBiggerThanValue(
                      lastViewedAt,
                    )),
          );
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<int> createPost(MemberBoardPostsCompanion c) =>
      into(memberBoardPosts).insert(c);

  Future<void> updatePost(String id, MemberBoardPostsCompanion c) =>
      (update(memberBoardPosts)..where((p) => p.id.equals(id))).write(c);

  /// Soft-delete: sets `is_deleted = true`. Never hard-deletes.
  Future<void> softDeletePost(String id) =>
      (update(memberBoardPosts)..where((p) => p.id.equals(id))).write(
        const MemberBoardPostsCompanion(isDeleted: Value(true)),
      );

  // ---------------------------------------------------------------------------
  // SP backfill dedup helper
  // ---------------------------------------------------------------------------

  /// Returns an existing post matching the dedup tuple used by the SP backfill
  /// service. Used by Batch F to skip already-imported posts.
  ///
  /// The [bodyHash] parameter is carried by the caller for UUID v5 generation;
  /// the SQL query matches on (target_member_id, author_id, written_at) because
  /// the body is not stored as a hash in the DB column.
  Future<MemberBoardPostRow?> findByDedupTuple({
    required String targetMemberId,
    required String? authorId,
    required DateTime writtenAt,
    required String bodyHash,
  }) {
    final q =
        select(memberBoardPosts)
          ..where(
            (p) =>
                p.targetMemberId.equals(targetMemberId) &
                (authorId == null
                    ? p.authorId.isNull()
                    : p.authorId.equals(authorId)) &
                p.writtenAt.equals(writtenAt),
          )
          ..limit(1);
    return q.getSingleOrNull();
  }

  // ---------------------------------------------------------------------------
  // Private keyset helper
  // ---------------------------------------------------------------------------

  /// Builds the keyset continuation predicate for paginated queries.
  ///
  /// Returns a predicate that matches all rows when both parameters are null
  /// (first page). For subsequent pages, returns:
  ///
  ///   `(written_at < afterWrittenAt)
  ///   OR (written_at = afterWrittenAt AND id < afterId)`
  ///
  /// This correctly implements stable keyset pagination on the
  /// `(written_at DESC, id DESC)` ordering.
  Expression<bool> _keysetWhere(
    $MemberBoardPostsTable p,
    DateTime? afterWrittenAt,
    String? afterId,
  ) {
    if (afterWrittenAt == null || afterId == null) {
      return const Constant<bool>(true);
    }
    return p.writtenAt.isSmallerThanValue(afterWrittenAt) |
        (p.writtenAt.equals(afterWrittenAt) & p.id.isSmallerThanValue(afterId));
  }
}
