import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

import '../../../helpers/fake_repositories.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

const String _aliceId = '11111111-2222-3333-4444-555555555555';
const String _bobId = '99999999-8888-7777-6666-555555555555';

// Text sizes used by the layout policy tests: the phone body-medium role is
// 14, so 15 em is 210 pt at 1x, 315 pt at 1.5x and 420 pt at 2x.
const double _wideHeader = 390; // 390 pt phone minus the 24 pt page padding
const double _narrowHeader = 272; // 320 pt phone minus the page padding

Member _member({
  String id = _aliceId,
  String name = 'Alice',
  String? displayName,
  String? pronouns,
  String? age,
  String? birthday,
  Uint8List? headerImage,
  Uint8List? avatarImage,
  MemberProfileHeaderLayout layout =
      MemberProfileHeaderLayout.compactBackground,
  MemberProfileHeaderSource source = MemberProfileHeaderSource.prism,
  bool headerVisible = true,
  bool isAdmin = false,
  bool isActive = true,
  MemberNameFont nameStyleFont = MemberNameFont.standard,
  bool nameStyleItalic = false,
}) => Member(
  id: id,
  name: name,
  displayName: displayName,
  emoji: '*',
  age: age,
  birthday: birthday,
  pronouns: pronouns,
  createdAt: DateTime(2026, 4, 1),
  avatarImageData: avatarImage,
  isAdmin: isAdmin,
  isActive: isActive,
  nameStyleFont: nameStyleFont,
  nameStyleItalic: nameStyleItalic,
  profileHeaderSource: source,
  profileHeaderLayout: layout,
  profileHeaderVisible: headerVisible,
  profileHeaderImageData: headerImage,
);

/// A scaler that behaves like Android's nonlinear scaling: reported factor 1.5,
/// but the body role (14) really scales to 2x while larger sizes scale less.
class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.4;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.5;
}

/// Pumps a header inside a fixed-width column so layout assertions do not depend
/// on the test surface size.
Future<void> _pumpHeader(
  WidgetTester tester,
  Member member, {
  double width = _wideHeader,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
  ThemeData? theme,
  bool isFronting = false,
  List<Member> mentionMembers = const [],
  VoidCallback? onAvatarTap,
  VoidCallback? onAvatarRemove,
  VoidCallback? onNameStyleTap,
}) async {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => appPrefs.close().timeout(const Duration(seconds: 5)),
    );
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        databaseProvider.overrideWith((ref) {
          throw StateError('Pronoun header tests must not open a database');
        }),
        if (mentionMembers.isNotEmpty)
          activeMemberListProvider.overrideWith(
            (ref) => Stream.value(mentionMembers),
          ),
      ],
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: MemberProfileHeader(
                  member: member,
                  isFronting: isFronting,
                  onAvatarTap: onAvatarTap,
                  onAvatarRemove: onAvatarRemove,
                  onNameStyleTap: onNameStyleTap,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final Finder _capsule = find.byKey(memberProfilePronounsCapsuleKey);

Finder _insideCapsule(Finder matching) =>
    find.descendant(of: _capsule, matching: matching);

/// Every RichText painted inside [root], so assertions read what the header
/// really renders rather than the raw markdown source.
List<RichText> _richTexts(WidgetTester tester, Finder root) => tester
    .widgetList<RichText>(
      find.descendant(of: root, matching: find.byType(RichText)),
    )
    .toList();

List<TextSpan> _textSpans(WidgetTester tester, Finder root) {
  final spans = <TextSpan>[];
  for (final richText in _richTexts(tester, root)) {
    richText.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
        spans.add(span);
      }
      return true;
    });
  }
  return spans;
}

String _renderedText(WidgetTester tester, Finder root) => _richTexts(
  tester,
  root,
).map((richText) => richText.text.toPlainText()).join();

String _collapsed(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

double _bodyMediumSize(WidgetTester tester) =>
    Theme.of(
      tester.element(find.byType(MemberProfileHeader)),
    ).textTheme.bodyMedium?.fontSize ??
    14;

void main() {
  group('pronoun capsule', () {
    testWidgets('shows the string once at body-medium under the name', (
      tester,
    ) async {
      const pronouns = 'they/them';
      await _pumpHeader(tester, _member(pronouns: pronouns));

      expect(_capsule, findsOneWidget);
      // Rendered text is the pronoun string itself, not raw markdown.
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(find.text(pronouns), findsOneWidget);
      // The name line keeps the name only: no inline `` · pronouns`` suffix.
      expect(find.text('Alice'), findsOneWidget);

      final spans = _textSpans(tester, _capsule);
      expect(spans, isNotEmpty);
      expect(spans.first.style?.fontSize, _bodyMediumSize(tester));
      expect(spans.first.style?.fontWeight, FontWeight.w500);

      for (final richText in _richTexts(tester, _capsule)) {
        expect(richText.maxLines, isNull);
        expect(richText.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(_insideCapsule(find.byType(FittedBox)), findsNothing);

      // The capsule sits under the name, not on the name line.
      expect(
        tester.getRect(_capsule).top,
        greaterThanOrEqualTo(tester.getRect(find.text('Alice')).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keeps short pronouns beside the avatar as a single-line pill',
      (tester) async {
        await _pumpHeader(tester, _member(pronouns: 'she/her'));

        final avatar = tester.getRect(find.byType(MemberAvatar));
        final capsule = tester.getRect(_capsule);
        expect(capsule.left, greaterThanOrEqualTo(avatar.right + 15));
        // Still inside the avatar column, so narrower than the column itself.
        expect(capsule.width, lessThan(_wideHeader - 80 - 16));
        // One line of body-medium plus the 6 pt vertical padding on each side.
        expect(capsule.height, lessThan(_bodyMediumSize(tester) * 2 + 14));
      },
    );

    testWidgets('grows a long list beside the avatar without truncation', (
      tester,
    ) async {
      const pronouns =
          'She/Her, Sae/Saers, Lace/Laces, Bliss/Blissful, Pure/Pures';
      await _pumpHeader(tester, _member(pronouns: 'she/her'));
      final shortHeight = tester.getSize(_capsule).height;

      await _pumpHeader(tester, _member(pronouns: pronouns));

      final avatar = tester.getRect(find.byType(MemberAvatar));
      final capsule = tester.getRect(_capsule);
      expect(capsule.left, greaterThanOrEqualTo(avatar.right + 15));
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      expect(capsule.height, greaterThan(shortHeight));
      for (final richText in _richTexts(tester, _capsule)) {
        expect(richText.maxLines, isNull);
        expect(richText.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('grows a very long list instead of clipping it', (
      tester,
    ) async {
      const pronouns =
          'she/her, they/them, xe/xem, ze/zir, fae/faer, it/its, ae/aer, '
          'co/cos, ve/ver, e/em, per/per, thy/thym, hu/hum, ne/nem, '
          'vi/vim, ey/em, sie/hir, he/him, one/ones, any/all';
      await _pumpHeader(tester, _member(pronouns: pronouns));

      expect(_capsule, findsOneWidget);
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      final size = tester.getSize(_capsule);
      expect(size.width, lessThanOrEqualTo(_wideHeader + 0.01));
      // Many wrapped lines, not one clipped line.
      expect(size.height, greaterThan(_bodyMediumSize(tester) * 4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('preserves emoji, ZWJ sequences and authored order', (
      tester,
    ) async {
      const pronouns = 'they/them 🧑🏽‍🚀 🏳️‍🌈 ze/zie';
      await _pumpHeader(tester, _member(pronouns: pronouns));

      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reuses the field renderer for formatting and mentions', (
      tester,
    ) async {
      final bob = _member(id: _bobId, name: 'Bob');
      const pronouns = 'they/them **bold** @[$_bobId]';
      await _pumpHeader(
        tester,
        _member(pronouns: pronouns),
        mentionMembers: [bob],
      );
      // Let the member stream deliver so the mention resolves to its label.
      await tester.pumpAndSettle();

      // One shared renderer, inside the capsule, reading the stored string.
      final fieldText = _insideCapsule(
        find.byWidgetPredicate(
          (widget) =>
              widget is FieldInlineMarkdownText && widget.data == pronouns,
        ),
      );
      expect(fieldText, findsOneWidget);

      final spans = _textSpans(tester, _capsule);
      final boldSpan = spans.where((span) => span.text == 'bold').toList();
      expect(boldSpan, isNotEmpty);
      expect(boldSpan.first.style?.fontWeight, FontWeight.bold);

      final rendered = _renderedText(tester, _capsule);
      expect(rendered, contains('@Bob'));
      expect(rendered, isNot(contains('@[$_bobId]')));
      expect(rendered, isNot(contains('**')));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'uses the full header width when text scale outgrows the column',
      (tester) async {
        const pronouns = 'they/them/ze/zie';
        await _pumpHeader(tester, _member(pronouns: pronouns));
        final beside = tester.getRect(_capsule);
        final avatar = tester.getRect(find.byType(MemberAvatar));
        expect(beside.left, greaterThanOrEqualTo(avatar.right + 15));

        // 390 pt header at 2x: 15 em of 28 pt is 420 pt, wider than the header.
        await _pumpHeader(
          tester,
          _member(pronouns: pronouns),
          textScaler: const TextScaler.linear(2),
        );

        final dropped = tester.getRect(_capsule);
        expect(
          dropped.left,
          lessThanOrEqualTo(
            tester.getRect(find.byType(MemberAvatar)).left + 0.5,
          ),
        );
        expect(dropped.width, greaterThan(beside.width));
        expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('drops under the avatar on a narrow phone at 1.5x', (
      tester,
    ) async {
      const pronouns = 'they/them/ze/zie';
      await _pumpHeader(
        tester,
        _member(pronouns: pronouns),
        width: _narrowHeader,
        textScaler: const TextScaler.linear(1.5),
      );

      final avatar = tester.getRect(find.byType(MemberAvatar));
      final capsule = tester.getRect(_capsule);
      // 15 em of 21 pt is 315 pt, wider than the 272 pt header.
      expect(capsule.left, lessThanOrEqualTo(avatar.left + 0.5));
      expect(capsule.width, greaterThan(_narrowHeader - 80 - 16));
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      expect(tester.takeException(), isNull);
    });

    testWidgets('follows a nonlinear scaler at the capsule font size', (
      tester,
    ) async {
      const pronouns = 'they/them/ze/zie';
      await _pumpHeader(tester, _member(pronouns: pronouns));
      final avatar = tester.getRect(find.byType(MemberAvatar));
      expect(
        tester.getRect(_capsule).left,
        greaterThanOrEqualTo(avatar.right + 15),
      );

      // Reported factor 1.5 would keep 15 em at 315 pt (still narrower than
      // 390), but the body role really scales to 28 pt, so the capsule moves.
      await _pumpHeader(
        tester,
        _member(pronouns: pronouns),
        textScaler: const _NonlinearTextScaler(),
      );

      expect(
        tester.getRect(_capsule).left,
        lessThanOrEqualTo(tester.getRect(find.byType(MemberAvatar)).left + 0.5),
      );
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders fully and grows at 3.375x without clipping', (
      tester,
    ) async {
      const pronouns = 'she/her, they/them, xe/xem';
      await _pumpHeader(
        tester,
        _member(pronouns: pronouns),
        textScaler: const TextScaler.linear(3.375),
      );

      final capsule = tester.getRect(_capsule);
      expect(capsule.width, lessThanOrEqualTo(_wideHeader + 0.01));
      expect(_collapsed(_renderedText(tester, _capsule)), pronouns);
      for (final richText in _richTexts(tester, _capsule)) {
        expect(richText.maxLines, isNull);
      }
      expect(
        tester.getSize(_insideCapsule(find.byType(RichText)).first).height,
        greaterThan(_bodyMediumSize(tester) * 3),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing and leaves no gap when pronouns are empty', (
      tester,
    ) async {
      await _pumpHeader(tester, _member());
      final withoutPronouns = tester.getSize(find.byType(MemberProfileHeader));
      expect(_capsule, findsNothing);

      await _pumpHeader(tester, _member(pronouns: ''));
      expect(_capsule, findsNothing);
      expect(tester.getSize(find.byType(MemberProfileHeader)), withoutPronouns);

      await _pumpHeader(tester, _member(pronouns: '   '));
      expect(_capsule, findsNothing);
      expect(tester.getSize(find.byType(MemberProfileHeader)), withoutPronouns);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays the capsule out from the start edge in right-to-left', (
      tester,
    ) async {
      const pronouns = 'هي/لها they/them';
      await _pumpHeader(
        tester,
        _member(pronouns: pronouns),
        textDirection: TextDirection.rtl,
      );

      // In RTL the avatar is on the right and the capsule starts at the
      // identity column's inline start edge, i.e. flush with the avatar gap.
      final avatar = tester.getRect(find.byType(MemberAvatar));
      final capsule = tester.getRect(_capsule);
      expect(capsule.right, closeTo(avatar.left - 16, 0.5));
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in compact, image-behind and classic headers', (
      tester,
    ) async {
      const pronouns = 'they/them 🦊';

      await _pumpHeader(tester, _member(pronouns: pronouns));
      expect(_capsule, findsOneWidget);
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(tester.takeException(), isNull);

      await _pumpHeader(
        tester,
        _member(pronouns: pronouns, headerImage: _pngBytes),
      );
      expect(_capsule, findsOneWidget);
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(tester.takeException(), isNull);

      await _pumpHeader(
        tester,
        _member(
          pronouns: pronouns,
          headerImage: _pngBytes,
          layout: MemberProfileHeaderLayout.classicOverlap,
        ),
      );
      expect(_capsule, findsOneWidget);
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps status chips separate from the pronoun capsule', (
      tester,
    ) async {
      const pronouns = 'they/them';
      await _pumpHeader(
        tester,
        _member(
          pronouns: pronouns,
          birthday: '2011-06-15',
          age: '25',
          isAdmin: true,
          isActive: false,
        ),
        isFronting: true,
      );

      expect(find.text('Fronting'), findsOneWidget);
      expect(_insideCapsule(find.text('Fronting')), findsNothing);
      expect(_insideCapsule(find.textContaining('25')), findsNothing);
      expect(_renderedText(tester, _capsule).trim(), pronouns);
      // Chips stay below the capsule rather than above it.
      expect(
        tester.getRect(find.text('Fronting')).top,
        greaterThan(tester.getRect(_capsule).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps avatar, remove and name-style callbacks', (
      tester,
    ) async {
      var avatarTapped = 0;
      var avatarRemoved = 0;
      var nameStyleTapped = 0;
      await _pumpHeader(
        tester,
        _member(pronouns: 'they/them', avatarImage: _pngBytes),
        onAvatarTap: () => avatarTapped++,
        onAvatarRemove: () => avatarRemoved++,
        onNameStyleTap: () => nameStyleTapped++,
      );

      expect(_capsule, findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.textFields));
      await tester.pump();
      expect(nameStyleTapped, 1);

      await tester.tap(find.byType(MemberAvatar));
      await tester.pump();
      expect(avatarTapped, 1);

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pump();
      expect(avatarRemoved, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hugs a short capsule instead of filling the avatar column', (
      tester,
    ) async {
      await _pumpHeader(tester, _member(pronouns: 'she/her'));

      final capsule = tester.getSize(_capsule);
      // The avatar column is 390 - 80 - 16 = 294 wide; a hugged capsule stays
      // well inside it instead of taking the whole column.
      expect(capsule.width, lessThan((_wideHeader - 96) * 0.8));
      final textWidth = tester
          .getSize(_insideCapsule(find.byType(RichText)).first)
          .width;
      expect(textWidth, greaterThan(0));
      // The capsule is the rendered text plus the 12 pt padding on each side.
      expect(capsule.width, closeTo(textWidth + 24, 1));
      expect(_renderedText(tester, _capsule).trim(), 'she/her');
      expect(tester.takeException(), isNull);
    });

    testWidgets('labels the capsule and keeps mentions reachable', (
      tester,
    ) async {
      final bob = _member(id: _bobId, name: 'Bob');
      const pronouns = 'they/them @[$_bobId]';
      // The active handle must be disposed inside the test body: the widget
      // tester verifies handles before addTearDown callbacks run.
      final handle = tester.ensureSemantics();
      try {
        await _pumpHeader(
          tester,
          _member(pronouns: pronouns),
          mentionMembers: [bob],
        );
        await tester.pumpAndSettle();

        final labels = <String>[];
        void collect(SemanticsNode node) {
          if (node.label.isNotEmpty) labels.add(node.label);
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        collect(tester.getSemantics(_capsule));
        final announced = labels.join(' ');
        // The pronoun role is announced, but nothing is excluded or flattened:
        // the rendered text and the mention are still in the semantics subtree.
        expect(announced, contains('Pronouns'));
        expect(announced, contains('they/them'));
        expect(announced, contains('@Bob'));

        // The mention keeps its tap recognizer under the label.
        var mentionHasRecognizer = false;
        for (final richText in _richTexts(tester, _capsule)) {
          richText.text.visitChildren((span) {
            if (span is TextSpan &&
                (span.text ?? '').contains('@Bob') &&
                span.recognizer is TapGestureRecognizer) {
              mentionHasRecognizer = true;
            }
            return true;
          });
        }
        expect(mentionHasRecognizer, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('opens a mentioned member from inside the capsule', (
      tester,
    ) async {
      final bob = _member(id: _bobId, name: 'Bob');
      const pronouns = 'they/them @[$_bobId]';
      final appPrefs = FakeAppPreferenceRepository();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: _wideHeader,
                  child: MemberProfileHeader(
                    member: _member(pronouns: pronouns),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutePaths.members,
            builder: (_, _) => const Scaffold(body: Text('members')),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => Scaffold(
                  body: Text('member-${state.pathParameters['id']}'),
                ),
              ),
            ],
          ),
        ],
      );
      // Unmount before disposing the router, then close the preference fake.
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
        await tester.runAsync(
          () => appPrefs.close().timeout(const Duration(seconds: 5)),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
            databaseProvider.overrideWith((ref) {
              throw StateError('Pronoun header tests must not open a database');
            }),
            activeMemberListProvider.overrideWith((ref) => Stream.value([bob])),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the mention span itself. The paragraph's own centre sits on
      // "they/them", and a paragraph forwards a pointer only to the span under
      // it, so resolve the "@Bob" glyph box and tap its centre.
      final mentionFinder = find.textContaining('@Bob');
      expect(mentionFinder, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(mentionFinder);
      final mentionStart = paragraph.text.toPlainText().indexOf('@Bob');
      expect(mentionStart, isNonNegative);
      final mentionBoxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: mentionStart,
          extentOffset: mentionStart + '@Bob'.length,
        ),
      );
      expect(mentionBoxes, isNotEmpty);
      await tester.tapAt(
        paragraph.localToGlobal(mentionBoxes.first.toRect().center),
      );
      await tester.pumpAndSettle();

      expect(find.text('member-$_bobId'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps square corners when PrismShapes is angular', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        _member(pronouns: 'they/them'),
        theme: ThemeData(
          useMaterial3: true,
          extensions: const [PrismShapes.angular],
        ),
      );

      expect(_capsule, findsOneWidget);
      final decoration = tester.widget<Container>(_capsule).decoration;
      expect(decoration, isA<BoxDecoration>());
      expect((decoration! as BoxDecoration).borderRadius, BorderRadius.zero);
      expect(_renderedText(tester, _capsule).trim(), 'they/them');
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the display-name preference and name styling', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        _member(
          name: 'North Star',
          displayName: 'Navigator',
          pronouns: 'xe/xem',
          nameStyleFont: MemberNameFont.display,
          nameStyleItalic: true,
        ),
      );

      final nameSpans = _textSpans(
        tester,
        find.byType(MemberProfileHeader),
      ).where((span) => (span.text ?? '').contains('Navigator')).toList();
      expect(nameSpans, isNotEmpty);
      // The chosen name style still applies to the primary or alternate name.
      expect(nameSpans.first.style?.fontFamily, 'Unbounded');
      expect(nameSpans.first.style?.fontStyle, FontStyle.italic);
      // Pronouns stay out of the name line and keep their own capsule.
      expect(_renderedText(tester, _capsule).trim(), 'xe/xem');
      expect(tester.takeException(), isNull);
    });
  });
}
