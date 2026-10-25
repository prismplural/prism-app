import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/views/member_board_screen.dart';
import 'package:prism_plurality/features/boards/views/post_detail_screen.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

class _ChatSpeaker extends SpeakingAsNotifier {
  @override
  String? build() => 'bob';

  @override
  void setMember(String? memberId, {bool recordLastUsed = true}) {
    state = memberId;
  }
}

class _PostRepository implements MemberBoardPostsRepository {
  _PostRepository(this.post);
  final MemberBoardPost post;

  @override
  Stream<MemberBoardPost?> watchPostById(String id) => Stream.value(post);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _selectActor(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('boards.actorSelector')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(MemberSearchSheet),
      matching: find.text(name),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime(2026, 5, 1);
  final members = [
    Member(id: 'alice', name: 'Alice', createdAt: now),
    Member(id: 'bob', name: 'Bob', createdAt: now),
    Member(id: 'charlie', name: 'Charlie', createdAt: now),
    Member(id: 'admin', name: 'Admin', createdAt: now, isAdmin: true),
  ];
  final post = MemberBoardPost(
    id: 'post',
    authorId: 'alice',
    targetMemberId: 'bob',
    audience: 'public',
    body: 'Synthetic post',
    createdAt: now,
    writtenAt: now,
  );

  testWidgets('board actor controls list and detail independently of chat', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        speakingAsProvider.overrideWith(_ChatSpeaker.new),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
        userVisibleMemberListProvider.overrideWith(
          (ref) => AsyncValue.data(members),
        ),
        memberByIdProvider.overrideWith(
          (ref, id) =>
              Stream.value(members.where((m) => m.id == id).firstOrNull),
        ),
        allGroupsProvider.overrideWith((ref) => Stream.value(<MemberGroup>[])),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(<MemberGroupEntry>[]),
        ),
        memberBoardFeedProvider.overrideWith((ref, id) => Stream.value([post])),
        memberBoardPostsRepositoryProvider.overrideWithValue(
          _PostRepository(post),
        ),
      ],
    );
    addTearDown(container.dispose);

    Future<void> show(Widget screen) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Viewing the author's board must not select them as the actor.
    await show(const MemberBoardScreen(memberId: 'alice'));
    expect(tester.widget<PostTile>(find.byType(PostTile)).viewerMember, isNull);
    await _selectActor(tester, 'Alice');
    expect(container.read(speakingAsProvider), 'bob');
    expect(
      tester.widget<PostTile>(find.byType(PostTile)).viewerMember?.id,
      'alice',
    );
    container.read(speakingAsProvider.notifier).setMember('charlie');
    await tester.pumpAndSettle();
    expect(
      tester.widget<PostTile>(find.byType(PostTile)).viewerMember?.id,
      'alice',
    );

    await show(const PostDetailScreen(postId: 'post'));
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    container.read(speakingAsProvider.notifier).setMember('bob');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);

    // Profile owner and admin may delete, but never edit someone else's post.
    for (final actor in ['Bob', 'Admin']) {
      await _selectActor(tester, actor);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byTooltip('Delete'), findsOneWidget);
    }
    await _selectActor(tester, 'Charlie');
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    await show(const MemberBoardScreen(memberId: 'alice'));
    expect(
      tester.widget<PostTile>(find.byType(PostTile)).viewerMember?.id,
      'charlie',
    );
  });
}
