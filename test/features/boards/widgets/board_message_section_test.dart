// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/board_message_section.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider, SpeakingAsNotifier;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 5, 1, 12);

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: _now, isActive: true);

final _alice = _member('alice', 'Alice');

MemberBoardPost _publicPost(String id, {String authorId = 'alice'}) =>
    MemberBoardPost(
      id: id,
      authorId: authorId,
      audience: 'public',
      body: 'Post body $id',
      createdAt: _now.subtract(Duration(hours: int.parse(id))),
      writtenAt: _now.subtract(Duration(hours: int.parse(id))),
    );

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
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildSection({
  String memberId = 'alice',
  List<MemberBoardPost> publicPosts = const [],
  int totalPublic = 0,
  bool boardsEnabled = true,
  List<Member> allMembers = const [],
}) {
  final section = MemberBoardSection(
    publicPosts: publicPosts,
    totalPublic: totalPublic,
  );

  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(SystemSettings(boardsEnabled: boardsEnabled)),
      ),
      boardsEnabledProvider.overrideWithValue(boardsEnabled),
      speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
      activeMembersProvider.overrideWith(
        (ref) => Stream.value(allMembers),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(
          allMembers.cast<Member?>().firstWhere(
                (m) => m?.id == id,
                orElse: () => null,
              ),
        ),
      ),
      memberBoardSectionProvider.overrideWith(
        (ref, mid) => Stream.value(section),
      ),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: SingleChildScrollView(
                child: BoardMessageSection(memberId: memberId),
              ),
            ),
          ),
          GoRoute(
            path: '/boards/member/:memberId',
            builder: (context, state) =>
                Text('Member board ${state.pathParameters['memberId']}'),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BoardMessageSection — visibility', () {
    testWidgets('returns shrink when boards is disabled', (tester) async {
      await tester.pumpWidget(
        _buildSection(boardsEnabled: false),
      );
      await tester.pump();

      // When disabled, section should render nothing (SizedBox.shrink).
      expect(find.text('Board Messages'), findsNothing);
    });

    testWidgets('shows section header when boards is enabled', (tester) async {
      await tester.pumpWidget(
        _buildSection(boardsEnabled: true),
      );
      await tester.pump();

      expect(find.text('Board Messages'), findsOneWidget);
    });
  });

  group('BoardMessageSection — empty state', () {
    testWidgets('shows empty state text when no posts', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          publicPosts: const [],
          totalPublic: 0,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('No posts here yet.'), findsOneWidget);
    });
  });

  group('BoardMessageSection — posts list', () {
    testWidgets('renders up to 3 posts when available', (tester) async {
      final posts = [
        _publicPost('1'),
        _publicPost('2'),
        _publicPost('3'),
      ];
      await tester.pumpWidget(
        _buildSection(
          publicPosts: posts,
          totalPublic: 3,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.textContaining('Post body 1'), findsOneWidget);
      expect(find.textContaining('Post body 2'), findsOneWidget);
      expect(find.textContaining('Post body 3'), findsOneWidget);
    });

    testWidgets('does NOT show "See all" when totalPublic < 4', (tester) async {
      final posts = [_publicPost('1'), _publicPost('2'), _publicPost('3')];
      await tester.pumpWidget(
        _buildSection(
          publicPosts: posts,
          totalPublic: 3,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.textContaining('See all'), findsNothing);
    });

    testWidgets('shows "See all" link when totalPublic >= 4', (tester) async {
      final posts = [
        _publicPost('1'),
        _publicPost('2'),
        _publicPost('3'),
      ];
      await tester.pumpWidget(
        _buildSection(
          publicPosts: posts,
          totalPublic: 4,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.textContaining('See all 4 posts'), findsOneWidget);
    });

    testWidgets('"See all" link navigates to /boards/member/:id', (tester) async {
      final posts = [_publicPost('1'), _publicPost('2'), _publicPost('3')];
      await tester.pumpWidget(
        _buildSection(
          memberId: 'alice',
          publicPosts: posts,
          totalPublic: 5,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining('See all'));
      await tester.pumpAndSettle();

      // Verifies route navigation occurred to the member board screen.
      expect(find.text('Member board alice'), findsOneWidget);
    });
  });

  group('BoardMessageSection — header', () {
    testWidgets('section header has Semantics header=true', (tester) async {
      await tester.pumpWidget(
        _buildSection(allMembers: [_alice]),
      );
      await tester.pump();

      // Find a Semantics widget with header: true.
      final semanticsWidgets = tester.widgetList<Semantics>(
        find.byType(Semantics),
      );
      final hasHeaderSemantics = semanticsWidgets.any(
        (s) => s.properties.header == true,
      );
      expect(hasHeaderSemantics, isTrue);
    });

    testWidgets('"Post to Alice" tooltip on + button', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          memberId: 'alice',
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Post to Alice'), findsOneWidget);
    });
  });
}
