import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
// boardsEnabledProvider is imported from settings_providers.dart in UI files
// that consume it; not needed here.

// ---------------------------------------------------------------------------
// Cursor types — used as family parameters
// ---------------------------------------------------------------------------

/// Keyset cursor for the public timeline and inbox feeds.
///
/// [afterWrittenAt] and [afterId] together form the keyset; pass both null
/// for the first page. Always pass them in tandem — the keyset query orders
/// by `(written_at DESC, id DESC)`.
class BoardPagingCursor {
  const BoardPagingCursor({
    this.afterWrittenAt,
    this.afterId,
    this.limit = 30,
  });

  final DateTime? afterWrittenAt;
  final String? afterId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardPagingCursor &&
          runtimeType == other.runtimeType &&
          afterWrittenAt == other.afterWrittenAt &&
          afterId == other.afterId &&
          limit == other.limit;

  @override
  int get hashCode =>
      Object.hash(afterWrittenAt, afterId, limit);
}

/// Keyset cursor for a single member's public board.
class MemberBoardCursor {
  const MemberBoardCursor({
    required this.memberId,
    this.afterWrittenAt,
    this.afterId,
    this.limit = 30,
  });

  final String memberId;
  final DateTime? afterWrittenAt;
  final String? afterId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberBoardCursor &&
          runtimeType == other.runtimeType &&
          memberId == other.memberId &&
          afterWrittenAt == other.afterWrittenAt &&
          afterId == other.afterId &&
          limit == other.limit;

  @override
  int get hashCode =>
      Object.hash(memberId, afterWrittenAt, afterId, limit);
}

// ---------------------------------------------------------------------------
// Section model — returned by memberBoardSectionProvider
// ---------------------------------------------------------------------------

/// Summary data for a member's board section on their profile.
///
/// [publicPosts] — up to 3 most-recent public posts involving [memberId]
/// (WHERE `(author_id = memberId OR target_member_id = memberId) AND
/// audience = 'public'`).
/// [totalPublic] — total count of matching public posts (may exceed 3).
class MemberBoardSection {
  const MemberBoardSection({
    required this.publicPosts,
    required this.totalPublic,
  });

  final List<MemberBoardPost> publicPosts;
  final int totalPublic;
}

// ---------------------------------------------------------------------------
// SharedPreferences key
// ---------------------------------------------------------------------------

const _kPublicLastViewedAt = 'boards.public_last_viewed_at';

// ---------------------------------------------------------------------------
// Public timeline feed
// ---------------------------------------------------------------------------

/// Public sub-tab feed, keyset-paginated.
///
/// Pass `BoardPagingCursor()` (no arguments) for the first page.
final publicBoardPostsProvider = StreamProvider.autoDispose
    .family<List<MemberBoardPost>, BoardPagingCursor>((ref, cursor) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchPublicPaginated(
    afterWrittenAt: cursor.afterWrittenAt,
    afterId: cursor.afterId,
    limit: cursor.limit,
  );
});

// ---------------------------------------------------------------------------
// Inbox feed
// ---------------------------------------------------------------------------

/// Inbox sub-tab feed — private posts addressed to the currently-active
/// fronters, keyset-paginated.
///
/// Watches [activeMembersProvider] so the feed updates when co-fronters
/// change. Pass `BoardPagingCursor()` for the first page.
final inboxBoardPostsProvider = StreamProvider.autoDispose
    .family<List<MemberBoardPost>, BoardPagingCursor>((ref, cursor) {
  final activeMembers = ref.watch(activeMembersProvider).value ?? const [];
  final activeIds = activeMembers.map((m) => m.id).toList();
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchInboxPaginated(
    activeIds,
    afterWrittenAt: cursor.afterWrittenAt,
    afterId: cursor.afterId,
    limit: cursor.limit,
  );
});

// ---------------------------------------------------------------------------
// Inbox view filter — ephemeral, not persisted
// ---------------------------------------------------------------------------

/// Inbox view-filter selection.
///
/// `null` → show posts for all fronters; non-null → filter to a single
/// member ID. Ephemeral: reset when the tab is left (autoDispose).
///
/// The plan specifies `StateProvider.autoDispose<String?>` — in Riverpod 3
/// (which removed `StateProvider`) this is the idiomatic equivalent.
final inboxViewFilterProvider =
    NotifierProvider.autoDispose<_InboxViewFilterNotifier, String?>(
  _InboxViewFilterNotifier.new,
);

class _InboxViewFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Set to a specific member ID to filter the inbox to that member only.
  void setFilter(String? memberId) => state = memberId;
}

// ---------------------------------------------------------------------------
// Per-member board section (profile section preview)
// ---------------------------------------------------------------------------

/// Summary for the Board Messages section on a member's profile page.
///
/// Returns the 3 most-recent public posts by or about [memberId], plus a
/// total-count used to drive the "See all N posts" link.
///
/// WHERE `(author_id = memberId OR target_member_id = memberId)
///        AND audience = 'public' AND is_deleted = false`.
final memberBoardSectionProvider = StreamProvider.autoDispose
    .family<MemberBoardSection, String>((ref, memberId) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);

  // Watch the recent-3 stream — the section only renders a preview.
  final recentStream = repo.watchPublicForMemberRecent(memberId, limit: 3);

  // For the total count we also watch the full paginated stream at limit=100
  // (reasonable upper bound for section badge; profile UX doesn't paginate).
  final allStream = repo.watchPublicForMemberPaginated(memberId, limit: 100);

  // Combine: whenever either stream emits, rebuild the section.
  return recentStream.asyncExpand((recent) {
    return allStream.map(
      (all) => MemberBoardSection(
        publicPosts: recent,
        totalPublic: all.length,
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Per-member board posts (full paginated list)
// ---------------------------------------------------------------------------

/// Full paginated list of public posts by or about [cursor.memberId].
///
/// WHERE `(author_id = memberId OR target_member_id = memberId)
///        AND audience = 'public' AND is_deleted = false`.
final memberBoardPostsProvider = StreamProvider.autoDispose
    .family<List<MemberBoardPost>, MemberBoardCursor>((ref, cursor) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchPublicForMemberPaginated(
    cursor.memberId,
    afterWrittenAt: cursor.afterWrittenAt,
    afterId: cursor.afterId,
    limit: cursor.limit,
  );
});

// ---------------------------------------------------------------------------
// Unread public-dot — SharedPreferences-backed last-viewed timestamp
// ---------------------------------------------------------------------------

/// Device-local timestamp of the last time the user opened the Public sub-tab.
///
/// Backed by SharedPreferences (key: `boards.public_last_viewed_at`).
/// Call `ref.read(publicBoardLastViewedAtProvider.notifier).markViewed()` when
/// the Public tab opens.
final publicBoardLastViewedAtProvider =
    NotifierProvider<PublicLastViewedAtNotifier, DateTime?>(
  PublicLastViewedAtNotifier.new,
);

class PublicLastViewedAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    // Kick off async load without blocking the synchronous build.
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kPublicLastViewedAt);
    if (ms != null) {
      state = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
  }

  /// Records that the Public sub-tab was just viewed.
  Future<void> markViewed() async {
    final now = DateTime.now().toUtc();
    state = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPublicLastViewedAt, now.millisecondsSinceEpoch);
  }
}

// ---------------------------------------------------------------------------
// Public unread dot
// ---------------------------------------------------------------------------

/// True when there are new public posts since the last time the Public
/// sub-tab was opened.
///
/// Drives the small unread dot on the "Public" segment label in Boards screen.
/// Returns false while loading or on error.
final publicBoardUnreadDotProvider = Provider<bool>((ref) {
  final countAsync = ref.watch(_publicUnreadCountProvider);
  return countAsync.whenOrNull(data: (n) => n > 0) ?? false;
});

/// Internal: async count of new public posts since [publicBoardLastViewedAtProvider].
/// Returns 0 while loading. Private to this file.
final _publicUnreadCountProvider = FutureProvider.autoDispose<int>((ref) {
  final lastViewed = ref.watch(publicBoardLastViewedAtProvider);
  final dao = ref.watch(memberBoardPostsDaoProvider);
  return dao.countNewPublicSince(lastViewed);
});

// ---------------------------------------------------------------------------
// Nav tab badge
// ---------------------------------------------------------------------------

/// Count of unread private posts for all currently-active fronters.
///
/// Returns `Provider<int>` (not `AsyncValue`) per the locked contract:
/// returns 0 while loading or on error, so callers never need to unwrap.
final boardsTabBadgeProvider = Provider<int>((ref) {
  final countAsync = ref.watch(_boardsBadgeCountProvider);
  return countAsync.whenOrNull(data: (n) => n) ?? 0;
});

/// Internal async computation backing [boardsTabBadgeProvider].
/// Private to this file; callers use [boardsTabBadgeProvider].
final _boardsBadgeCountProvider = FutureProvider.autoDispose<int>((ref) async {
  // Watch active members so the badge rebuilds when co-fronters change.
  final activeMembersAsync = ref.watch(activeMembersProvider);
  final activeMembers = activeMembersAsync.value;
  if (activeMembers == null || activeMembers.isEmpty) return 0;

  final activeIds = activeMembers.map((m) => m.id).toList();

  // Fetch boardLastReadAt for each active member directly from the DB row,
  // since the domain Member model does not carry this field.
  final membersDao = ref.watch(membersDaoProvider);
  final lastReadByMember = <String, DateTime?>{};
  for (final memberId in activeIds) {
    final row = await membersDao.getMemberById(memberId);
    lastReadByMember[memberId] = row?.boardLastReadAt;
  }

  final dao = ref.watch(memberBoardPostsDaoProvider);
  return dao.countUnreadForMembers(activeIds, lastReadByMember);
});

// ---------------------------------------------------------------------------
// Mutation notifier
// ---------------------------------------------------------------------------

/// CRUD notifier for member board posts.
///
/// Exposed as [memberBoardPostNotifierProvider].
class MemberBoardPostNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  /// Creates a new post and returns it (callers that need the ID can use it).
  ///
  /// Sets both `createdAt` and `writtenAt` to `DateTime.now()`.
  Future<MemberBoardPost> createPost({
    required String? targetMemberId,
    required String authorId,
    required String audience,
    String? title,
    required String body,
  }) async {
    assert(
      audience == 'public' || audience == 'private',
      'audience must be "public" or "private"',
    );
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      throw ArgumentError('body must not be empty after trimming');
    }
    final repo = ref.read(memberBoardPostsRepositoryProvider);
    final now = DateTime.now();
    final post = MemberBoardPost(
      id: _uuid.v4(),
      targetMemberId: targetMemberId,
      authorId: authorId,
      audience: audience,
      title: title?.trim().isEmpty ?? true ? null : title?.trim(),
      body: trimmedBody,
      createdAt: now,
      writtenAt: now,
    );
    state = await AsyncValue.guard(() => repo.createPost(post));
    return post;
  }

  /// Full-shape edit of an existing post.
  ///
  /// Allows changing [targetMemberId] and [audience] (author-only permission
  /// enforced at the UI layer via [MemberBoardPostPermissions]). Sets
  /// `editedAt = DateTime.now()`. Validates that [body] is non-empty after
  /// trimming.
  Future<void> updatePost({
    required String id,
    String? targetMemberId,
    String? audience,
    String? title,
    required String body,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      throw ArgumentError('body must not be empty after trimming');
    }
    if (audience != null) {
      assert(
        audience == 'public' || audience == 'private',
        'audience must be "public" or "private"',
      );
    }
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberBoardPostsRepositoryProvider);
      final existing = await repo.getPostById(id);
      if (existing == null) {
        throw StateError('Post $id not found');
      }
      final updated = existing.copyWith(
        targetMemberId: targetMemberId ?? existing.targetMemberId,
        audience: audience ?? existing.audience,
        title: title?.trim().isEmpty ?? true ? null : title?.trim(),
        body: trimmedBody,
        editedAt: DateTime.now(),
      );
      await repo.updatePost(updated);
    });
  }

  /// Soft-deletes the post identified by [id].
  Future<void> deletePost(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberBoardPostsRepositoryProvider);
      await repo.softDeletePost(id);
    });
  }

  /// Marks the inbox as read for all currently-active fronters.
  ///
  /// Snapshots the fronter list at call time — a fronter de-fronting between
  /// dispatch and execution does not get marked-read after the fact.
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {
    // Snapshot immediately per the contract — do NOT re-read activeMembersProvider.
    final snapshot = List<String>.unmodifiable(activeFronterIds);
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberBoardPostsRepositoryProvider);
      await repo.markInboxOpenedFor(snapshot);
    });
  }

  /// Bumps the device-local public-last-viewed timestamp to now, clearing
  /// the unread dot on the Public sub-tab.
  Future<void> markPublicViewed() async {
    await ref
        .read(publicBoardLastViewedAtProvider.notifier)
        .markViewed();
  }
}

/// Provider for [MemberBoardPostNotifier].
final memberBoardPostNotifierProvider =
    AsyncNotifierProvider<MemberBoardPostNotifier, void>(
  MemberBoardPostNotifier.new,
);

