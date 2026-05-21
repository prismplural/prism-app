// Asserts the per-member board scrolls past the load-more threshold without
// resetting scroll position. Mirrors the sleep history flicker regression.

// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/views/member_board_screen.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider, SpeakingAsNotifier;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _LimitedRepo implements MemberBoardPostsRepository {
  _LimitedRepo(this._posts);

  final List<MemberBoardPost> _posts;

  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => Stream.value(_posts.take(limit).toList());

  // Stubs.
  @override
  Stream<List<MemberBoardPost>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => const Stream.empty();
  @override
  Stream<List<MemberBoardPost>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => const Stream.empty();
  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  }) => Stream.value(_posts.take(limit).toList());
  @override
  Stream<MemberBoardPost?> watchPostById(String id) => Stream.value(null);
  @override
  Stream<List<MemberBoardPost>> watchMentionPostsByIds(List<String> ids) =>
      Stream.value(const <MemberBoardPost>[]);
  @override
  Future<List<MemberBoardPost>> searchMentionCandidates(
    String filter, {
    int limit = 12,
    List<String> activeFronterIds = const [],
  }) async => const <MemberBoardPost>[];
  @override
  Future<MemberBoardPost?> getPostById(String id) async => null;
  @override
  Future<void> createPost(MemberBoardPost post) async {}
  @override
  Future<void> updatePost(MemberBoardPost post) async {}
  @override
  Future<void> softDeletePost(String id) async {}
  @override
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {}
}

final _now = DateTime(2026, 5, 1, 12);

Member _alice() =>
    Member(id: 'alice', name: 'Alice', createdAt: _now, isActive: true);

MemberBoardPost _post(int i) => MemberBoardPost(
  id: 'p-$i',
  authorId: 'alice',
  audience: 'public',
  body: 'Body $i — long enough to take up some vertical space in the list',
  createdAt: _now.subtract(Duration(minutes: i + 1)),
  writtenAt: _now.subtract(Duration(minutes: i + 1)),
);

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

class _FakeBoardPostNotifier extends MemberBoardPostNotifier {
  @override
  Future<void> build() async {}
}

void main() {
  testWidgets(
    'scrolling near the bottom triggers loadMore and keeps scroll position',
    (tester) async {
      // Seed enough rows for at least three pages.
      final posts = [for (var i = 0; i < boardPostsPageSize * 3; i++) _post(i)];
      final repo = _LimitedRepo(posts);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
            activeMembersProvider.overrideWith(
              (ref) => Stream.value([_alice()]),
            ),
            memberByIdProvider.overrideWith(
              (ref, id) => Stream.value(id == 'alice' ? _alice() : null),
            ),
            memberBoardPostsRepositoryProvider.overrideWithValue(repo),
            memberBoardPostNotifierProvider.overrideWith(
              _FakeBoardPostNotifier.new,
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: MediaQuery(
              data: MediaQueryData(size: Size(400, 800)),
              child: MemberBoardScreen(memberId: 'alice'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Grab the screen's controller off the CustomScrollView — find.byType
      // (Scrollable).first can resolve to a wrapping MaterialApp scrollable.
      final csv = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final controller = csv.controller!;

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MemberBoardScreen)),
      );
      var loaded = container.read(memberBoardFeedProvider('alice')).value;
      expect(loaded, isNotNull);
      expect(loaded!.length, boardPostsPageSize);

      controller.jumpTo(controller.position.maxScrollExtent - 50);
      final positionBeforeLoad = controller.position.pixels;
      await tester.pump();
      await tester.pumpAndSettle();

      loaded = container.read(memberBoardFeedProvider('alice')).value;
      expect(loaded, isNotNull);
      expect(
        loaded!.length,
        greaterThan(boardPostsPageSize),
        reason: 'load-more should have extended the list past the first page',
      );
      expect(
        controller.position.pixels,
        greaterThanOrEqualTo(positionBeforeLoad - 1),
        reason: 'scroll position must not reset after load-more',
      );
    },
  );
}
