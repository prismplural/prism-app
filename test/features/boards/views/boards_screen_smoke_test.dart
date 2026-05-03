// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/views/boards_screen.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider, SpeakingAsNotifier;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

class _FakeBoardPostNotifier extends MemberBoardPostNotifier {
  @override
  Future<void> build() async {}

  @override
  Future<void> markPublicViewed() async {}

  @override
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {}
}

// ---------------------------------------------------------------------------
// Fixture data
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 5, 1, 12);

MemberBoardPost _publicPost(String id) => MemberBoardPost(
      id: id,
      authorId: 'alice',
      audience: 'public',
      body: 'Hello system, this is post $id',
      createdAt: _now,
      writtenAt: _now,
    );

MemberBoardPost _privatePost(String id, String targetId) => MemberBoardPost(
      id: id,
      authorId: 'alice',
      targetMemberId: targetId,
      audience: 'private',
      body: 'Private message $id',
      createdAt: _now,
      writtenAt: _now,
    );

final _alice = Member(
  id: 'alice',
  name: 'Alice',
  createdAt: _now,
  isActive: true,
);

final _bob = Member(
  id: 'bob',
  name: 'Bob',
  createdAt: _now,
  isActive: true,
);

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildBoardsScreen({
  List<MemberBoardPost> publicPosts = const [],
  List<MemberBoardPost> inboxPosts = const [],
  List<Member> activeMembers = const [],
  bool hasUnreadPublic = false,
  int inboxBadge = 0,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings(boardsEnabled: true)),
      ),
      speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
      activeMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      currentFronterMemberIdsProvider.overrideWith(
        (ref) => activeMembers.map((m) => m.id).toList(growable: false),
      ),
      currentFronterMembersProvider.overrideWith((ref) => activeMembers),
      userVisibleMembersProvider.overrideWith(
        (ref) => AsyncValue.data(activeMembers),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(
          [...activeMembers].cast<Member?>().firstWhere(
                (m) => m?.id == id,
                orElse: () => null,
              ),
        ),
      ),
      publicBoardPostsProvider.overrideWith(
        (ref, cursor) => Stream.value(publicPosts),
      ),
      inboxBoardPostsProvider.overrideWith(
        (ref, cursor) => Stream.value(inboxPosts),
      ),
      publicBoardUnreadDotProvider.overrideWithValue(hasUnreadPublic),
      boardsTabBadgeProvider.overrideWithValue(inboxBadge),
      boardsEnabledProvider.overrideWithValue(true),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
      // inboxViewFilterProvider uses its real implementation (defaults to null).
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: BoardsScreen()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    // Mock SharedPreferences so BoardsScreen's async prefs load completes
    // in pumpAndSettle without hanging.
    SharedPreferences.setMockInitialValues({});
  });

  group('BoardsScreen smoke', () {
    testWidgets('renders with both segments visible', (tester) async {
      await tester.pumpWidget(_buildBoardsScreen());
      await tester.pumpAndSettle();

      // 'Public' appears in both the segment control and the empty-state page
      // header, so use findsWidgets rather than findsOneWidget.
      expect(find.text('Public'), findsWidgets);
      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('shows the Boards screen title', (tester) async {
      await tester.pumpWidget(_buildBoardsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Boards'), findsWidgets);
    });

    testWidgets('public empty state shown when no posts', (tester) async {
      await tester.pumpWidget(_buildBoardsScreen());
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing on the public timeline yet.'),
        findsOneWidget,
      );
    });

    testWidgets('renders public posts when data is available', (tester) async {
      final posts = [_publicPost('p1'), _publicPost('p2')];
      await tester.pumpWidget(_buildBoardsScreen(publicPosts: posts));
      await tester.pumpAndSettle();

      expect(find.textContaining('post p1'), findsOneWidget);
      expect(find.textContaining('post p2'), findsOneWidget);
    });

    testWidgets('tapping Inbox segment switches to inbox page', (tester) async {
      final inboxPosts = [_privatePost('i1', 'alice')];
      await tester.pumpWidget(
        _buildBoardsScreen(
          activeMembers: [_alice],
          inboxPosts: inboxPosts,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      // Inbox page shows the avatar filter trigger with an explicit label.
      expect(find.bySemanticsLabel(RegExp('All fronters')), findsWidgets);
    });

    testWidgets('swipe left reveals Inbox page', (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(activeMembers: [_alice]),
      );
      await tester.pumpAndSettle();

      // Swipe left on the page view.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('All fronters')), findsWidgets);
    });

    testWidgets('unread dot appears on Public segment when hasUnreadPublic',
        (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(hasUnreadPublic: true),
      );
      await tester.pumpAndSettle();

      // The Public segment Semantics node is annotated with ", unread" in its
      // semanticsLabel when hasUnreadPublic is true.
      expect(
        find.bySemanticsLabel(RegExp(r'Public.*unread')),
        findsOneWidget,
      );
    });

    testWidgets('numeric badge appears on Inbox segment when inboxBadge > 0',
        (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(inboxBadge: 3),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('inbox badge capped at 99+ when count > 99', (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(inboxBadge: 150),
      );
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('inbox empty state shows no-fronter hint when no active members',
        (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(activeMembers: const []),
      );
      await tester.pumpAndSettle();

      // Switch to Inbox tab.
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("No one's fronting right now"),
        findsOneWidget,
      );
    });

    testWidgets('inbox shows all-fronters filter when members are active',
        (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(activeMembers: [_alice, _bob]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('All fronters')), findsWidgets);
    });

    testWidgets('default landing tab is Public', (tester) async {
      await tester.pumpWidget(_buildBoardsScreen());
      // Allow SharedPreferences async load to complete.
      await tester.pumpAndSettle();

      // Public segment text is visible (may appear multiple times: segment bar
      // + empty-state page heading), and the public empty state is shown
      // (not the inbox empty state), confirming Public is the default tab.
      expect(find.text('Public'), findsWidgets);
      expect(
        find.text('Nothing on the public timeline yet.'),
        findsOneWidget,
      );
    });
  });

  group('BoardsScreen — filter dropdown', () {
    testWidgets('filter dropdown chip appears when on Inbox tab', (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(activeMembers: [_alice, _bob]),
      );
      await tester.pump();

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      // The avatar trigger exposes "All fronters" to assistive tech.
      expect(find.bySemanticsLabel(RegExp('All fronters')), findsWidgets);
    });

    testWidgets('filter trigger starts at "All fronters"', (tester) async {
      await tester.pumpWidget(
        _buildBoardsScreen(activeMembers: [_alice, _bob]),
      );
      await tester.pump();

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('All fronters')), findsWidgets);
    });
  });
}
