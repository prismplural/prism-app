// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';

/// Channel the url_launcher plugin answers on (links in post bodies).
const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

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
  VoidCallback? onTap,
  Widget Function(Widget tile)? wrapBody,
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
        body: wrapBody == null
            ? PostTile(
                post: post,
                viewerMember: viewerMember,
                showAudiencePill: showAudiencePill,
                onTap: onTap,
              )
            : wrapBody(
                PostTile(
                  post: post,
                  viewerMember: viewerMember,
                  showAudiencePill: showAudiencePill,
                  onTap: onTap,
                ),
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
    testWidgets('public post with no recipient renders "to everyone" once',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(audience: 'public', targetMemberId: null),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      expect(find.text('to'), findsOneWidget);
      expect(find.text('everyone'), findsOneWidget);
      expect(find.textContaining('to everyone'), findsNothing);
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

    testWidgets('redacts spoilers in the plain-text title', (tester) async {
      // The title is not markdown-rendered, so a spoiler must show as ▮ rather
      // than leak (the body uses MarkdownText with real tap-to-reveal pills).
      await tester.pumpWidget(
        _buildTile(
          _post(title: 'see ||hidden||', body: 'plain body'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      expect(visible, isNot(contains('hidden')));
      expect(visible, contains('▮'));
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
        'renders a terminology-neutral fallback when no author resolves',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          // authorId = null → the fallback chain hits boardsTileRemovedMember.
          _post(authorId: null),
          allMembers: const [],
        ),
      );
      await tester.pump();

      expect(find.text('Removed profile'), findsOneWidget);
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

    test('redacts spoiler plaintext so screen readers cannot announce it', () {
      // The visible body hides spoilers behind tap-to-reveal pills; the a11y
      // label must not leak the hidden text.
      expect(
        stripMarkdownForA11y('the answer is ||42 is secret||'),
        'the answer is spoiler',
      );
      expect(stripMarkdownForA11y('||a|| and ||b||'), 'spoiler and spoiler');
    });
  });
  // -------------------------------------------------------------------------
  // Selectable body (issue #2): post text must be selectable and copyable, and
  // the tile's other interactions must keep working around it.
  // -------------------------------------------------------------------------

  group('PostTile — selectable body', () {
    const bodyKey = ValueKey('post-body-post-1');
    final clipboardWrites = <String>[];
    final launchedUrls = <String>[];

    setUp(() {
      clipboardWrites.clear();
      launchedUrls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              clipboardWrites.add(args['text']! as String);
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, (call) async {
            if (call.method == 'launch') {
              final args = call.arguments as Map<Object?, Object?>;
              launchedUrls.add(args['url']! as String);
              return true;
            }
            return false;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, null);
    });

    /// Runs [body] under [platform]. The override is restored in `finally`
    /// because flutter_test verifies this debug variable before tear-downs.
    Future<void> withPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    }

    Finder bodySelectionArea() => find.ancestor(
          of: find.byKey(bodyKey),
          matching: find.byType(SelectionArea),
        );

    Finder bodyRichTexts() => find.descendant(
          of: find.byKey(bodyKey),
          matching: find.byType(RichText),
        );

    /// Hit-testable body text on either mechanism: a RichText paragraph
    /// (SelectionArea) or an EditableText field (Android selectable body).
    Finder bodyTextTarget() => find
        .descendant(
          of: find.byKey(bodyKey),
          matching: find.byWidgetPredicate(
            (widget) => widget is RichText || widget is EditableText,
          ),
        )
        .first;

    Future<void> dragSelect(
      WidgetTester tester,
      Offset from,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> copySelection(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> dragSelectBodyAndCopy(WidgetTester tester) async {
      final body = bodyTextTarget();
      await dragSelect(
        tester,
        tester.getTopLeft(body) + const Offset(2, 6),
        tester.getTopRight(body) + const Offset(-2, 6),
      );
      await copySelection(tester);
    }

    /// Taps [target] inside the rendered body on either mechanism.
    Future<void> tapBodyGlyphs(
      WidgetTester tester,
      String bodyText,
      String target,
    ) async {
      final start = bodyText.indexOf(target);
      expect(start, greaterThanOrEqualTo(0));
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: start + target.length,
      );
      final paragraphFinder = find.descendant(
        of: find.byKey(bodyKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == bodyText,
        ),
      );
      if (paragraphFinder.evaluate().isNotEmpty) {
        final paragraph = tester.renderObject<RenderParagraph>(
          paragraphFinder.first,
        );
        final boxes = paragraph.getBoxesForSelection(selection);
        expect(boxes, isNotEmpty);
        await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
        return;
      }
      final editable = tester.renderObject<RenderEditable>(
        find
            .descendant(
              of: find.byKey(bodyKey),
              matching: find.byType(EditableText),
            )
            .first,
      );
      final boxes = editable.getBoxesForSelection(selection);
      expect(boxes, isNotEmpty);
      await tester.tapAt(editable.localToGlobal(boxes.first.toRect().center));
    }

    /// Swipes left from [from] on a tile inside a PageView (the Boards screen
    /// pages between tabs) and asserts the page turned.
    Future<void> expectSwipePages(WidgetTester tester, Finder from) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await tester.pumpWidget(
        _buildTile(
          _post(body: 'Hello headmates!'),
          allMembers: [_alice],
          wrapBody: (tile) => PageView(
            controller: pageController,
            children: [tile, const Center(child: Text('second page'))],
          ),
        ),
      );
      await tester.pump();

      await tester.flingFrom(
        tester.getCenter(from),
        const Offset(-400, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(pageController.page, closeTo(1, 0.01));
      expect(find.text('second page'), findsOneWidget);
    }

    testWidgets('body is copied via SelectionArea, not a read-only text field', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(_post(body: 'Hello headmates!'), allMembers: [_alice]),
      );
      await tester.pump();

      expect(bodySelectionArea(), findsOneWidget);
      // Plain-text semantics: the body must stay a RenderParagraph, not a
      // SelectableText/EditableText (which announces itself as a text field).
      expect(
        find.descendant(
          of: bodySelectionArea(),
          matching: find.byType(SelectableText),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: bodySelectionArea(),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );

      await dragSelectBodyAndCopy(tester);

      expect(clipboardWrites, isNotEmpty);
      expect(clipboardWrites.last, contains('Hello headmates'));
    });

    testWidgets('one selection spans every rendered body block', (tester) async {
      // A `:::` fence splits the body into two separately rendered markdown
      // blocks; one SelectionArea must still cover both.
      await tester.pumpWidget(
        _buildTile(
          _post(
            body:
                'first paragraph text\n\n'
                ':::center\nsecond paragraph text\n:::',
          ),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      final blocks = bodyRichTexts();
      expect(blocks, findsNWidgets(2));

      await dragSelect(
        tester,
        tester.getTopLeft(blocks.first) + const Offset(2, 6),
        tester.getBottomRight(blocks.last) + const Offset(-2, -4),
      );
      await copySelection(tester);

      expect(clipboardWrites, isNotEmpty);
      expect(clipboardWrites.last, contains('first paragraph text'));
      expect(clipboardWrites.last, contains('second paragraph text'));
    });

    testWidgets('swipe from the header still pages the board', (tester) async {
      // On Android/Fuchsia a selection gesture that starts on the body takes
      // precedence over horizontal paging, so paging is exercised from
      // non-body space — here the header author name.
      await withPlatform(TargetPlatform.android, () async {
        expect(defaultTargetPlatform, TargetPlatform.android);
        await expectSwipePages(tester, find.text('Alice'));
      });
    });

    testWidgets('iOS: swipe that starts on body text still pages the board', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await expectSwipePages(tester, bodyTextTarget());
      });
    });

    testWidgets('body exposes no text-field semantics node', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _buildTile(_post(body: 'Hello headmates!'), allMembers: [_alice]),
        );
        await tester.pump();

        expect(_exposesTextFieldSemantics(tester), isFalse);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('tapping a non-text control area still opens the post', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _buildTile(
          _post(body: 'Hello headmates!'),
          allMembers: [_alice],
          onTap: () => opened++,
        ),
      );
      await tester.pump();

      // The header participant row is not body text, so the card's tap handler
      // must still fire there.
      await tester.tap(find.text('everyone'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('spoilers still reveal inside the selectable body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(_post(body: 'the ||secret|| thing'), allMembers: [_alice]),
      );
      await tester.pump();

      List<double> opacities() => tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();

      expect(opacities(), [1.0, 0.0]);
      await tester.tap(find.byType(SpoilerPill));
      await tester.pumpAndSettle();
      expect(opacities(), [0.0, 1.0]);
    });

    testWidgets('links inside the body still open on tap', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          _post(body: 'see [here](https://example.com) ok'),
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      await tapBodyGlyphs(tester, 'see here ok', 'here');
      await tester.pumpAndSettle();

      expect(launchedUrls, contains('https://example.com'));
    });

    testWidgets('edit/delete action menu stays reachable from the header', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(
          _post(body: 'Hello headmates!'),
          viewerMember: _alice,
          allMembers: [_alice],
        ),
      );
      await tester.pump();

      // Long-press on the body selects text, so the action menu lives on the
      // header/footer instead; the author name is a clearly non-body control.
      await tester.longPress(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
    });
  });
}

/// Whether any node in the current semantics tree is exposed as a text field.
bool _exposesTextFieldSemantics(WidgetTester tester) {
  final root = tester.binding.rootPipelineOwner.semanticsOwner
      ?.rootSemanticsNode;
  if (root == null) return false;
  var found = false;
  void visit(SemanticsNode node) {
    if (found) return;
    if (node.getSemanticsData().flagsCollection.isTextField) {
      found = true;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return !found;
    });
  }

  visit(root);
  return found;
}
