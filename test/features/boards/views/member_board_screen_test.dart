// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/views/member_board_screen.dart';
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
      createdAt: _now.subtract(const Duration(hours: 1)),
      writtenAt: _now.subtract(const Duration(hours: 1)),
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

Widget _buildScreen({
  String memberId = 'alice',
  List<MemberBoardPost> posts = const [],
  List<Member> allMembers = const [],
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
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
      memberBoardPostsProvider.overrideWith(
        (ref, c) => Stream.value(posts),
      ),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: MemberBoardScreen(memberId: memberId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MemberBoardScreen — smoke', () {
    testWidgets('renders screen title "Board Messages"', (tester) async {
      await tester.pumpWidget(
        _buildScreen(allMembers: [_alice]),
      );
      await tester.pump();

      // "Board Messages" appears at least once (top bar title), possibly more
      // in empty-state copy.
      expect(find.text('Board Messages'), findsWidgets);
    });

    testWidgets('shows member name as subtitle', (tester) async {
      await tester.pumpWidget(
        _buildScreen(memberId: 'alice', allMembers: [_alice]),
      );
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows empty state when no posts', (tester) async {
      await tester.pumpWidget(
        _buildScreen(posts: const [], allMembers: [_alice]),
      );
      await tester.pump();

      expect(find.text('No posts here yet.'), findsOneWidget);
    });

    testWidgets('renders list of posts when data available', (tester) async {
      final posts = [_publicPost('1'), _publicPost('2')];
      await tester.pumpWidget(
        _buildScreen(posts: posts, allMembers: [_alice]),
      );
      await tester.pump();

      expect(find.textContaining('Post body 1'), findsOneWidget);
      expect(find.textContaining('Post body 2'), findsOneWidget);
    });

    testWidgets('renders + action button in top bar', (tester) async {
      await tester.pumpWidget(
        _buildScreen(allMembers: [_alice]),
      );
      await tester.pump();

      // The top bar has a + button for composing.
      expect(find.byTooltip('Add'), findsOneWidget);
    });

    testWidgets('renders for unknown member without crashing', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          memberId: 'unknown-member',
          // allMembers doesn't include 'unknown-member' → member resolves null.
          allMembers: const [],
        ),
      );
      await tester.pump();

      // Screen still renders (no crash).
      expect(tester.takeException(), isNull);
    });
  });

  group('MemberBoardScreen — loading state', () {
    testWidgets('shows loading indicator initially', (tester) async {
      // Override with a stream that never emits.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
            activeMembersProvider.overrideWith(
              (ref) => Stream.value(const <Member>[]),
            ),
            memberByIdProvider.overrideWith(
              (ref, id) => Stream.value(null),
            ),
            memberBoardPostsProvider.overrideWith(
              (ref, cursor) => const Stream.empty(),
            ),
            memberBoardPostNotifierProvider
                .overrideWith(_FakeBoardPostNotifier.new),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: MemberBoardScreen(memberId: 'alice'),
          ),
        ),
      );

      // First pump — loading state.
      await tester.pump();

      expect(find.byType(PrismSpinner), findsOneWidget);
    });
  });
}
