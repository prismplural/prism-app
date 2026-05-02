import 'package:prism_plurality/domain/models/member_board_post.dart';

abstract class MemberBoardPostsRepository {
  // ---------------------------------------------------------------------------
  // Read streams — mirror the DAO method set
  // ---------------------------------------------------------------------------

  Stream<List<MemberBoardPost>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  });

  Stream<List<MemberBoardPost>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  });

  /// Public posts by or to [memberId].
  ///
  /// WHERE `(target_member_id = memberId OR author_id = memberId)
  ///        AND audience = 'public' AND is_deleted = false`
  Stream<List<MemberBoardPost>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  });

  /// Convenience: up to [limit] most recent public posts for a member's
  /// profile section preview. Same WHERE semantics as
  /// [watchPublicForMemberPaginated].
  Stream<List<MemberBoardPost>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  });

  Stream<MemberBoardPost?> watchPostById(String id);

  // ---------------------------------------------------------------------------
  // Point reads
  // ---------------------------------------------------------------------------

  Future<MemberBoardPost?> getPostById(String id);

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Creates a new post, emitting a sync `recordCreate` op.
  ///
  /// [post.audience] must be exactly `'public'` or `'private'`.
  Future<void> createPost(MemberBoardPost post);

  /// Updates an existing post (full-object update), emitting a sync
  /// `recordUpdate` op.
  ///
  /// [post.audience] must be exactly `'public'` or `'private'`.
  /// Supports changing `targetMemberId` and `audience` (author-only,
  /// enforced by the permissions helper in the UI layer).
  Future<void> updatePost(MemberBoardPost post);

  /// Soft-deletes the post identified by [id].
  ///
  /// Sets `is_deleted = true` and emits a sync `recordUpdate` op
  /// (NOT a hard-delete `recordDelete` — tombstone semantics).
  Future<void> softDeletePost(String id);

  // ---------------------------------------------------------------------------
  // Read-state helpers
  // ---------------------------------------------------------------------------

  /// Bumps `members.boardLastReadAt = DateTime.now()` for each member in
  /// [activeFronterIds] in a single transaction.
  ///
  /// Used by the Inbox sub-tab to mark all currently-fronting members'
  /// private posts as read. The caller must snapshot [activeFronterIds]
  /// BEFORE awaiting — a fronter de-fronting between dispatch and execution
  /// should not get marked-read.
  Future<void> markInboxOpenedFor(List<String> activeFronterIds);
}
