// Regression coverage for boards scroll-pagination. Guards the invariant that
// bumping a limit re-subscribes the same provider instance instead of spinning
// up a fresh family — see sleep_history_provider_test.dart for the canonical
// version of this pattern.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

// Fake repo — returns the top-N seeded posts that match each query.

class _FakeRepo implements MemberBoardPostsRepository {
  List<MemberBoardPost> _posts = const [];

  void seed(List<MemberBoardPost> posts) => _posts = List.of(posts);

  List<MemberBoardPost> _slice(
    bool Function(MemberBoardPost) predicate,
    int limit,
  ) {
    final matched = _posts.where(predicate).toList()
      ..sort((a, b) {
        final byWrittenAt = b.writtenAt.compareTo(a.writtenAt);
        if (byWrittenAt != 0) return byWrittenAt;
        return b.id.compareTo(a.id);
      });
    return matched.take(limit).toList();
  }

  @override
  Stream<List<MemberBoardPost>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    return Stream.value(
      _slice((p) => p.audience == 'public' && !p.isDeleted, limit),
    );
  }

  @override
  Stream<List<MemberBoardPost>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    if (targetMemberIds.isEmpty) return const Stream.empty();
    final ids = targetMemberIds.toSet();
    return Stream.value(
      _slice(
        (p) =>
            p.audience == 'private' &&
            !p.isDeleted &&
            p.targetMemberId != null &&
            ids.contains(p.targetMemberId),
        limit,
      ),
    );
  }

  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) {
    return Stream.value(
      _slice(
        (p) =>
            p.audience == 'public' &&
            !p.isDeleted &&
            (p.authorId == memberId || p.targetMemberId == memberId),
        limit,
      ),
    );
  }

  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  }) => watchPublicForMemberPaginated(memberId, limit: limit);

  @override
  Stream<MemberBoardPost?> watchPostById(String id) => Stream.value(
    _posts.cast<MemberBoardPost?>().firstWhere(
      (p) => p?.id == id,
      orElse: () => null,
    ),
  );

  @override
  Stream<List<MemberBoardPost>> watchMentionPostsByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <MemberBoardPost>[]);
    final wanted = ids.toSet();
    return Stream.value(
      _posts
          .where((post) => wanted.contains(post.id) && !post.isDeleted)
          .toList(),
    );
  }

  @override
  Future<List<MemberBoardPost>> searchMentionCandidates(
    String filter, {
    int limit = 12,
    List<String> activeFronterIds = const [],
  }) async {
    final lower = filter.trim().toLowerCase();
    final activeIds = activeFronterIds.toSet();
    return _slice(
      (post) =>
          !post.isDeleted &&
          (post.audience == 'public' ||
              (post.audience == 'private' &&
                  (activeIds.contains(post.targetMemberId) ||
                      activeIds.contains(post.authorId)))) &&
          (lower.isEmpty ||
              (post.title?.toLowerCase().contains(lower) ?? false) ||
              post.body.toLowerCase().contains(lower)),
      limit,
    );
  }

  @override
  Future<MemberBoardPost?> getPostById(String id) async => _posts
      .cast<MemberBoardPost?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);

  @override
  Future<void> createPost(MemberBoardPost post) async {}
  @override
  Future<void> updatePost(MemberBoardPost post) async {}
  @override
  Future<void> softDeletePost(String id) async {}
  @override
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {}
}

final _base = DateTime(2026, 4, 30, 12);

MemberBoardPost _public(int i, {String authorId = 'alice'}) => MemberBoardPost(
  id: 'pub-$i',
  authorId: authorId,
  audience: 'public',
  body: 'Public $i',
  createdAt: _base.subtract(Duration(minutes: i + 1)),
  writtenAt: _base.subtract(Duration(minutes: i + 1)),
);

MemberBoardPost _private(int i, {required String targetMemberId}) =>
    MemberBoardPost(
      id: 'priv-$i',
      authorId: 'sender',
      targetMemberId: targetMemberId,
      audience: 'private',
      body: 'Private $i',
      createdAt: _base.subtract(Duration(minutes: i + 1)),
      writtenAt: _base.subtract(Duration(minutes: i + 1)),
    );

Member _member(String id) =>
    Member(id: id, name: id, createdAt: _base, isActive: true);

Future<List<MemberBoardPost>> _waitForCount(
  AsyncValue<List<MemberBoardPost>> Function() reader,
  int expected, {
  String label = 'provider',
}) async {
  for (var i = 0; i < 100; i++) {
    final value = reader();
    final data = value.value;
    if (data != null && data.length == expected) return data;
    final err = value.whenOrNull(error: (e, _) => e);
    if (err != null) throw err;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $label to reach $expected items');
}

void main() {
  group('publicBoardFeedProvider', () {
    test('loads the first page using the limit notifier default', () async {
      final repo = _FakeRepo();
      repo.seed([for (var i = 0; i < boardPostsPageSize + 5; i++) _public(i)]);

      final container = ProviderContainer(
        overrides: [memberBoardPostsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        publicBoardFeedProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final firstPage = await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        boardPostsPageSize,
        label: 'publicBoardFeedProvider',
      );
      expect(firstPage, hasLength(boardPostsPageSize));
    });

    test('loadMore extends the page in place', () async {
      final repo = _FakeRepo();
      repo.seed([for (var i = 0; i < boardPostsPageSize * 2; i++) _public(i)]);

      final container = ProviderContainer(
        overrides: [memberBoardPostsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        publicBoardFeedProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        boardPostsPageSize,
      );
      container.read(publicBoardLimitProvider.notifier).loadMore();
      final secondPage = await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        boardPostsPageSize * 2,
      );
      expect(secondPage, hasLength(boardPostsPageSize * 2));
    });

    test(
      'load-more never emits a bare loading state after first page settles',
      () async {
        // Regression: a family keyed by limit (or cursor record) emits
        // AsyncLoading with no `.value` per page bump, collapsing the list
        // and snapping scroll to top. Walk two load-more cycles and assert
        // every post-first-page state carries a value.
        final repo = _FakeRepo();
        repo.seed([
          for (var i = 0; i < boardPostsPageSize * 3 + 5; i++) _public(i),
        ]);

        final container = ProviderContainer(
          overrides: [
            memberBoardPostsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final transitions = <AsyncValue<List<MemberBoardPost>>>[];
        final sub = container.listen<AsyncValue<List<MemberBoardPost>>>(
          publicBoardFeedProvider,
          (_, next) => transitions.add(next),
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await _waitForCount(
          () => container.read(publicBoardFeedProvider),
          boardPostsPageSize,
        );
        transitions.clear();

        for (var page = 2; page <= 3; page++) {
          container.read(publicBoardLimitProvider.notifier).loadMore();
          await _waitForCount(
            () => container.read(publicBoardFeedProvider),
            boardPostsPageSize * page,
          );
        }

        expect(
          transitions,
          isNotEmpty,
          reason: 'expected provider updates during pagination',
        );
        for (final state in transitions) {
          expect(
            state.hasValue,
            isTrue,
            reason: 'every state after first page must carry a value',
          );
        }
      },
    );

    test('pages stitch in order with no duplicates at the boundary', () async {
      final repo = _FakeRepo();
      // 75 posts → 3 pages of 30 with the last partial.
      repo.seed([for (var i = 0; i < 75; i++) _public(i)]);

      final container = ProviderContainer(
        overrides: [memberBoardPostsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        publicBoardFeedProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        boardPostsPageSize,
      );
      container.read(publicBoardLimitProvider.notifier).loadMore();
      await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        boardPostsPageSize * 2,
      );
      container.read(publicBoardLimitProvider.notifier).loadMore();
      final all = await _waitForCount(
        () => container.read(publicBoardFeedProvider),
        75,
      );

      // No duplicates.
      expect(all.map((p) => p.id).toSet(), hasLength(75));

      // Ordering preserved — writtenAt descending, ids in the seeded sequence.
      for (var i = 1; i < all.length; i++) {
        expect(
          all[i].writtenAt.isAfter(all[i - 1].writtenAt),
          isFalse,
          reason: 'writtenAt must be non-increasing across boundary',
        );
      }
      expect(all.first.id, 'pub-0');
      expect(all.last.id, 'pub-74');
    });
  });

  group('inboxBoardFeedProvider', () {
    test('loads private posts addressed to current fronters', () async {
      final repo = _FakeRepo();
      repo.seed([
        for (var i = 0; i < boardPostsPageSize + 5; i++)
          _private(i, targetMemberId: 'alice'),
      ]);

      final container = ProviderContainer(
        overrides: [
          memberBoardPostsRepositoryProvider.overrideWithValue(repo),
          activeMembersProvider.overrideWith(
            (ref) => Stream.value([_member('alice')]),
          ),
          activeSessionsProvider.overrideWith(
            (ref) => Stream.value([
              FrontingSession(
                id: 'session-alice',
                memberId: 'alice',
                startTime: _base,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        inboxBoardFeedProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final firstPage = await _waitForCount(
        () => container.read(inboxBoardFeedProvider),
        boardPostsPageSize,
        label: 'inboxBoardFeedProvider',
      );
      expect(firstPage, hasLength(boardPostsPageSize));
    });

    test('limit resets to page size when the inbox filter changes', () async {
      final repo = _FakeRepo();
      repo.seed([
        for (var i = 0; i < 100; i++) _private(i, targetMemberId: 'alice'),
        for (var i = 100; i < 200; i++) _private(i, targetMemberId: 'bob'),
      ]);

      final container = ProviderContainer(
        overrides: [
          memberBoardPostsRepositoryProvider.overrideWithValue(repo),
          activeMembersProvider.overrideWith(
            (ref) => Stream.value([_member('alice'), _member('bob')]),
          ),
          activeSessionsProvider.overrideWith(
            (ref) => Stream.value([
              FrontingSession(
                id: 'session-alice',
                memberId: 'alice',
                startTime: _base,
              ),
              FrontingSession(
                id: 'session-bob',
                memberId: 'bob',
                startTime: _base,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        inboxBoardFeedProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await _waitForCount(
        () => container.read(inboxBoardFeedProvider),
        boardPostsPageSize,
      );

      // Walk to page 3 (90 posts) with no filter.
      container.read(inboxBoardLimitProvider.notifier).loadMore();
      container.read(inboxBoardLimitProvider.notifier).loadMore();
      await _waitForCount(
        () => container.read(inboxBoardFeedProvider),
        boardPostsPageSize * 3,
      );
      expect(container.read(inboxBoardLimitProvider), boardPostsPageSize * 3);

      // Filter to alice — limit must reset to page size (alice has 100 posts,
      // so we should see boardPostsPageSize, not 90).
      container.read(inboxViewFilterProvider.notifier).setFilter('alice');
      await _waitForCount(
        () => container.read(inboxBoardFeedProvider),
        boardPostsPageSize,
      );
      expect(container.read(inboxBoardLimitProvider), boardPostsPageSize);
    });
  });

  group('memberBoardFeedProvider', () {
    test('family instances are independent across memberIds', () async {
      final repo = _FakeRepo();
      // Each member needs enough posts to load past one page so the test can
      // bump alice's limit while bob's stays put.
      repo.seed([
        for (var i = 0; i < boardPostsPageSize * 3; i++)
          _public(i, authorId: 'alice'),
        for (var i = boardPostsPageSize * 3; i < boardPostsPageSize * 6; i++)
          _public(i, authorId: 'bob'),
      ]);

      final container = ProviderContainer(
        overrides: [memberBoardPostsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        memberBoardFeedProvider('alice'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen<AsyncValue<List<MemberBoardPost>>>(
        memberBoardFeedProvider('bob'),
        (_, _) {},
        fireImmediately: true,
      );

      await _waitForCount(
        () => container.read(memberBoardFeedProvider('alice')),
        boardPostsPageSize,
        label: "memberBoardFeedProvider('alice')",
      );
      await _waitForCount(
        () => container.read(memberBoardFeedProvider('bob')),
        boardPostsPageSize,
        label: "memberBoardFeedProvider('bob')",
      );

      // Bump alice's limit — bob's must stay at the default.
      container.read(memberBoardLimitProvider('alice').notifier).loadMore();
      await _waitForCount(
        () => container.read(memberBoardFeedProvider('alice')),
        boardPostsPageSize * 2,
      );

      expect(
        container.read(memberBoardLimitProvider('alice')),
        boardPostsPageSize * 2,
      );
      expect(
        container.read(memberBoardLimitProvider('bob')),
        boardPostsPageSize,
      );
      expect(
        container.read(memberBoardFeedProvider('bob')).value,
        hasLength(boardPostsPageSize),
      );
    });

    test(
      'load-more never emits a bare loading state after first page settles',
      () async {
        final repo = _FakeRepo();
        repo.seed([
          for (var i = 0; i < boardPostsPageSize * 3 + 5; i++)
            _public(i, authorId: 'alice'),
        ]);

        final container = ProviderContainer(
          overrides: [
            memberBoardPostsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final transitions = <AsyncValue<List<MemberBoardPost>>>[];
        final sub = container.listen<AsyncValue<List<MemberBoardPost>>>(
          memberBoardFeedProvider('alice'),
          (_, next) => transitions.add(next),
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await _waitForCount(
          () => container.read(memberBoardFeedProvider('alice')),
          boardPostsPageSize,
        );
        transitions.clear();

        for (var page = 2; page <= 3; page++) {
          container.read(memberBoardLimitProvider('alice').notifier).loadMore();
          await _waitForCount(
            () => container.read(memberBoardFeedProvider('alice')),
            boardPostsPageSize * page,
          );
        }

        expect(transitions, isNotEmpty);
        for (final state in transitions) {
          expect(
            state.hasValue,
            isTrue,
            reason: 'every state after first page must carry a value',
          );
        }
      },
    );
  });
}
