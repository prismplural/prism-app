// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _now = DateTime(2026, 5, 1, 12);

Member _member(String id, String name, {bool isAdmin = false}) => Member(
      id: id,
      name: name,
      createdAt: _now,
      isActive: true,
      isAdmin: isAdmin,
    );

final _alice = _member('alice', 'Alice');
final _bob = _member('bob', 'Bob');

MemberBoardPost _post({
  String id = 'post-1',
  String? authorId = 'alice',
  String? targetMemberId,
  String audience = 'public',
  String body = 'Hello system',
  String? title,
  DateTime? editedAt,
  bool isDeleted = false,
}) =>
    MemberBoardPost(
      id: id,
      authorId: authorId,
      targetMemberId: targetMemberId,
      audience: audience,
      body: body,
      title: title,
      createdAt: _now.subtract(const Duration(hours: 2)),
      writtenAt: _now.subtract(const Duration(hours: 2)),
      editedAt: editedAt,
      isDeleted: isDeleted,
    );

// ---------------------------------------------------------------------------
// Fake notifier
// ---------------------------------------------------------------------------

class _FakeBoardPostNotifier extends MemberBoardPostNotifier {
  @override
  Future<void> build() async {}
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildTile(
  MemberBoardPost post, {
  Member? viewerMember,
  bool showAudiencePill = false,
  List<Member> allMembers = const [],
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(
          allMembers.cast<Member?>().firstWhere(
                (m) => m?.id == id,
                orElse: () => null,
              ),
        ),
      ),
      memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: PostTile(
          post: post,
          viewerMember: viewerMember,
          showAudiencePill: showAudiencePill,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PostTile — basic rendering', () {
    testWidgets('public post with no recipient renders "to everyone"',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'public', targetMemberId: null),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.textContaining('to everyone'), findsOneWidget);
    });

    testWidgets('public post with target member shows Bob', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'public', targetMemberId: 'bob'),
          allMembers: [_alice, _bob],
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('private post with target member shows Bob', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'private', targetMemberId: 'bob'),
          allMembers: [_alice, _bob],
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('renders post body text', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(body: 'Hello headmates!'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.textContaining('Hello headmates!'), findsOneWidget);
    });

    testWidgets('renders bold title when provided', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(title: 'Important notice'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('Important notice'), findsOneWidget);
    });

    testWidgets('does not show title widget when title is null', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(title: null),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      // Should not find bold title text.
      expect(find.text('(no title)'), findsNothing);
    });

    testWidgets('shows "edited" suffix when editedAt is non-null', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(editedAt: _now.subtract(const Duration(minutes: 5))),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('edited'), findsOneWidget);
    });

    testWidgets('does not show "edited" when editedAt is null', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(editedAt: null),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('edited'), findsNothing);
    });

    testWidgets('shows audience pill when showAudiencePill = true',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'public'),
          showAudiencePill: true,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('public'), findsOneWidget);
    });

    testWidgets('shows "private" pill for private post with showAudiencePill',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'private', targetMemberId: 'bob'),
          showAudiencePill: true,
          allMembers: [_alice, _bob],
        ),
      );
      await tester.pump();

      expect(find.text('private'), findsOneWidget);
    });

    testWidgets(
        'renders "Removed member" when authorId is null and no member resolves',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          // authorId = null → the fallback chain hits boardsTileRemovedMember.
          _post(authorId: null),
          allMembers: const [],
        ),
      );
      await tester.pump();

      expect(find.text('Removed member'), findsOneWidget);
    });

    testWidgets('renders authorId string as fallback when member not loaded',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(authorId: 'unknown-author'),
          // allMembers does not include 'unknown-author' → name = null,
          // falls back to authorId string.
          allMembers: const [],
        ),
      );
      await tester.pump();

      // Falls back to the authorId string.
      expect(find.text('unknown-author'), findsOneWidget);
    });
  });

  group('PostTile — long body', () {
    testWidgets('renders long body without overflow error', (tester) async {
      final longBody = List.generate(20, (i) => 'Word$i').join(' ');
      await tester.pumpWidget(
        _buildTile(
          _post(body: longBody),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('PostTile — semantics', () {
    testWidgets('semantics label contains plain-text body (no raw markdown)',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(body: '**bold** and _italic_ text'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      // The Semantics(button: true, label: ...) wraps the InkWell. We look for
      // a semantics node whose label contains 'bold' but not '**'.
      expect(
        find.bySemanticsLabel(RegExp(r'\bbold\b')),
        findsWidgets,
        reason: 'Semantics label should contain the plain word "bold"',
      );
      expect(
        find.bySemanticsLabel(RegExp(r'\*\*')),
        findsNothing,
        reason: 'Semantics label should not contain raw markdown "**"',
      );
    });

    testWidgets('semantics label includes "edited" when post is edited',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(editedAt: _now.subtract(const Duration(minutes: 1))),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      // The "edited" suffix must appear in the widget tree.
      expect(find.text('edited'), findsOneWidget);

      // And in the composed Semantics label.
      expect(
        find.bySemanticsLabel(RegExp(r'\bedited\b')),
        findsWidgets,
      );
    });

    testWidgets('semantics label includes author name', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(authorId: 'alice'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp(r'\bAlice\b')),
        findsWidgets,
      );
    });

    testWidgets('semantics label says "public" for public post', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'public', targetMemberId: null),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp(r'\bpublic\b')),
        findsWidgets,
      );
    });

    testWidgets('semantics label says "private" for private post', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'private', targetMemberId: 'bob'),
          allMembers: [_alice, _bob],
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp(r'\bprivate\b')),
        findsWidgets,
      );
    });
  });

  group('PostTile — stripMarkdownForA11y', () {
    test('strips bold markers', () {
      expect(stripMarkdownForA11y('**hello** world'), 'hello world');
    });

    test('strips italic markers', () {
      expect(stripMarkdownForA11y('_italic_ text'), 'italic text');
    });

    test('strips inline links', () {
      expect(
        stripMarkdownForA11y('[click here](https://example.com)'),
        'click here',
      );
    });

    test('strips strikethrough', () {
      expect(stripMarkdownForA11y('~~removed~~'), 'removed');
    });

    test('strips inline code backticks', () {
      expect(stripMarkdownForA11y('`code`'), 'code');
    });

    test('handles plain text unchanged', () {
      expect(stripMarkdownForA11y('Hello world'), 'Hello world');
    });

    test('collapses extra whitespace', () {
      expect(stripMarkdownForA11y('hello   world'), 'hello world');
    });
  });
}
