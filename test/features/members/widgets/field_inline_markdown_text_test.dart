import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import '../../../helpers/fake_repositories.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

void main() {
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  const aliceId = '11111111-2222-3333-4444-555555555555';
  final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  Widget host(String data, {List<Member> members = const []}) => ProviderScope(
    overrides: [
      activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
    ],
    child: MaterialApp(home: Scaffold(body: FieldInlineMarkdownText(data))),
  );

  /// Same host, but with an explicit block alignment so a `null` opt-in can be
  /// compared against the widget's default.
  Widget hostWithAlignment(String data, TextAlign? textAlign) => ProviderScope(
    overrides: [
      activeMemberListProvider.overrideWith(
        (ref) => Stream.value(const <Member>[]),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: FieldInlineMarkdownText(data, textAlign: textAlign)),
    ),
  );

  List<double> spoilerOpacities(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .map((w) => w.opacity)
      .toList();

  testWidgets('plain text renders without a spoiler pill', (tester) async {
    await tester.pumpWidget(host('just text'));
    expect(find.byType(SpoilerPill), findsNothing);
    expect(find.text('just text'), findsOneWidget);
  });

  testWidgets('||spoiler|| renders a hidden pill, not literal pipes', (
    tester,
  ) async {
    await tester.pumpWidget(host('value: ||hidden||'));
    expect(find.byType(SpoilerPill), findsOneWidget);
    // Hidden layer opaque, revealed layer transparent.
    expect(spoilerOpacities(tester), [1.0, 0.0]);
    // No literal pipe markers leak into any Text.
    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(visible, isNot(contains('||')));
  });

  testWidgets('tapping the pill reveals it', (tester) async {
    await tester.pumpWidget(host('||secret||'));
    expect(spoilerOpacities(tester), [1.0, 0.0]);
    await tester.tap(find.byType(SpoilerPill));
    await tester.pumpAndSettle();
    expect(spoilerOpacities(tester), [0.0, 1.0]);
  });

  testWidgets('two spoilers reveal independently', (tester) async {
    await tester.pumpWidget(host('||a|| and ||b||'));
    expect(find.byType(SpoilerPill), findsNWidgets(2));
    expect(spoilerOpacities(tester), [1.0, 0.0, 1.0, 0.0]);
    await tester.tap(find.byType(SpoilerPill).first);
    await tester.pumpAndSettle();
    // Only the first reveals.
    expect(spoilerOpacities(tester), [0.0, 1.0, 1.0, 0.0]);
  });

  testWidgets('spoiler locks out bold inside it', (tester) async {
    await tester.pumpWidget(host('||**x**||'));
    // The pill's inner text keeps the literal ** (not parsed as bold).
    expect(find.byType(SpoilerPill), findsOneWidget);
    final pill = tester.widget<SpoilerPill>(find.byType(SpoilerPill));
    expect(pill.text, '**x**');
  });

  // -------------------------------------------------------------------------
  // Link markdown tests
  // -------------------------------------------------------------------------

  testWidgets('[label](url) renders label text without syntax leaking', (
    tester,
  ) async {
    await tester.pumpWidget(host('[my carrd](https://my.carrd.co)'));
    // Combined text of all Text widgets contains the label.
    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('my carrd'));
    // No syntax characters leak into any rendered Text.
    expect(allText, isNot(contains('[')));
    expect(allText, isNot(contains('](')));
    expect(allText, isNot(contains(') ')));
  });

  testWidgets('tapping a link calls launchUrl with the correct url', (
    tester,
  ) async {
    final launchedUrls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch') {
            final args = call.arguments as Map<Object?, Object?>;
            launchedUrls.add(args['url']! as String);
            return true;
          }
          return false;
        });

    await tester.pumpWidget(host('[my carrd](https://my.carrd.co)'));
    await tester.tap(find.byType(RichText));
    await tester.pumpAndSettle();
    expect(launchedUrls, contains('https://my.carrd.co'));
  });

  testWidgets(
    'unsafe javascript: link renders label as plain text, no launch',
    (tester) async {
      final launchedUrls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, (call) async {
            if (call.method == 'launch') {
              final args = call.arguments as Map<Object?, Object?>;
              launchedUrls.add(args['url']! as String);
              return true;
            }
            return false;
          });

      await tester.pumpWidget(host('[x](javascript:alert(1))'));
      // Label renders as plain text.
      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join();
      expect(allText, contains('x'));

      // No link styling (no TapGestureRecognizer on a span with text 'x').
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      var foundLinkSpan = false;
      for (final rt in richTexts) {
        rt.text.visitChildren((span) {
          if (span is TextSpan &&
              (span.text?.contains('x') ?? false) &&
              span.recognizer is TapGestureRecognizer) {
            foundLinkSpan = true;
          }
          return true;
        });
      }
      expect(
        foundLinkSpan,
        isFalse,
        reason: 'unsafe link must not have a tap recognizer',
      );

      // Tapping does not call launchUrl.
      await tester.tap(find.byType(RichText));
      await tester.pumpAndSettle();
      expect(launchedUrls, isEmpty);
    },
  );

  testWidgets('surrounding text is preserved around a link', (tester) async {
    await tester.pumpWidget(host('see [here](https://x.com) ok'));
    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('see'));
    expect(allText, contains('here'));
    expect(allText, contains('ok'));
  });

  testWidgets(
    'spoiler wins over link: ||[hi](https://x.com)|| is a spoiler pill',
    (tester) async {
      await tester.pumpWidget(host('||[hi](https://x.com)||'));
      // Exactly one spoiler pill.
      expect(find.byType(SpoilerPill), findsOneWidget);
      // No TapGestureRecognizer link spans created.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      var foundLinkSpan = false;
      for (final rt in richTexts) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            foundLinkSpan = true;
          }
          return true;
        });
      }
      expect(
        foundLinkSpan,
        isFalse,
        reason: 'link inside spoiler must not create a tap recognizer',
      );
    },
  );

  testWidgets('mixed: link and bold both render', (tester) async {
    await tester.pumpWidget(host('[a](https://x.com) and **b**'));
    // Link 'a' has a tap recognizer.
    bool foundLinkSpan = false;
    bool foundBoldSpan = false;
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    for (final rt in richTexts) {
      rt.text.visitChildren((span) {
        if (span is TextSpan) {
          if ((span.text ?? '').contains('a') &&
              span.recognizer is TapGestureRecognizer) {
            foundLinkSpan = true;
          }
          if ((span.text ?? '').contains('b') &&
              span.style?.fontWeight == FontWeight.bold) {
            foundBoldSpan = true;
          }
        }
        return true;
      });
    }
    expect(foundLinkSpan, isTrue, reason: 'link span with recognizer expected');
    expect(foundBoldSpan, isTrue, reason: 'bold span expected');
  });

  testWidgets('bold link preserves both the link and bold styles', (
    tester,
  ) async {
    await tester.pumpWidget(host('**[resource](https://example.com)**'));

    var foundBoldLink = false;
    for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
      richText.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'resource' &&
            span.style?.fontWeight == FontWeight.bold &&
            span.recognizer is TapGestureRecognizer) {
          foundBoldLink = true;
        }
        return true;
      });
    }

    expect(
      foundBoldLink,
      isTrue,
      reason: 'a link nested in bold markdown must retain bold weight',
    );
  });

  testWidgets('member mention renders display name without raw token', (
    tester,
  ) async {
    await tester.pumpWidget(host('talked to @[$aliceId]', members: [alice]));
    await tester.pumpAndSettle();

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('@Alice'));
    expect(allText, isNot(contains('@[$aliceId]')));
  });

  testWidgets('member mention wins over link parsing', (tester) async {
    await tester.pumpWidget(
      host('[@[$aliceId]](https://x.com)', members: [alice]),
    );
    await tester.pumpAndSettle();

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('@Alice'));
    expect(allText, isNot(contains('](https://x.com)')));

    var foundMentionSpan = false;
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    for (final rt in richTexts) {
      rt.text.visitChildren((span) {
        if (span is TextSpan) {
          if ((span.text ?? '').contains('@Alice')) {
            foundMentionSpan = true;
          }
        }
        return true;
      });
    }
    expect(foundMentionSpan, isTrue, reason: 'mention span expected');
  });

  testWidgets('inline code beats member mention parsing', (tester) async {
    await tester.pumpWidget(host('`@[$aliceId]`', members: [alice]));
    await tester.pumpAndSettle();

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('@[$aliceId]'));
    expect(allText, isNot(contains('@Alice')));

    var foundTap = false;
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    for (final rt in richTexts) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          foundTap = true;
        }
        return true;
      });
    }
    expect(
      foundTap,
      isFalse,
      reason: 'mention inside backtick code must not become tappable',
    );
  });

  testWidgets('disposal: rebuilding with new link does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(host('[a](https://x.com)'));
    await tester.pumpWidget(host('[b](https://y.com)'));
    await tester.pumpAndSettle();
    // No exceptions means stale recognizers were properly disposed.
  });

  // -------------------------------------------------------------------------
  // Code-span precedence tests
  // -------------------------------------------------------------------------

  testWidgets(
    'inline code beats link: `[x](https://example.com)` renders as monospace literal, no tap recognizer',
    (tester) async {
      await tester.pumpWidget(host('`[x](https://example.com)`'));

      // The rendered text must contain the literal link syntax (not just 'x').
      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join();
      expect(
        allText,
        contains('[x](https://example.com)'),
        reason: 'literal code content must be visible',
      );

      // No TapGestureRecognizer should exist anywhere in the tree.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      var foundTap = false;
      for (final rt in richTexts) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            foundTap = true;
          }
          return true;
        });
      }
      expect(
        foundTap,
        isFalse,
        reason:
            'link inside backtick code span must not create a tap recognizer',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Block alignment (fit-content opt-in) tests
  // -------------------------------------------------------------------------

  testWidgets('default alignment keeps blocks at the available width', (
    tester,
  ) async {
    const data = '# heading\n\nthey/them';
    await tester.pumpWidget(host(data));

    final field = tester.widget<FieldInlineMarkdownText>(
      find.byType(FieldInlineMarkdownText),
    );
    // Existing callers keep the start alignment and full-width block layout.
    expect(field.textAlign, TextAlign.start);
    expect(tester.getSize(find.byType(Wrap).first).width, greaterThan(700));
  });

  testWidgets('null alignment opts into fit-content so blocks hug', (
    tester,
  ) async {
    const data = '# heading\n\nthey/them';
    await tester.pumpWidget(hostWithAlignment(data, null));

    final field = tester.widget<FieldInlineMarkdownText>(
      find.byType(FieldInlineMarkdownText),
    );
    expect(field.textAlign, isNull);
    // Opt-in: the block container hugs its text instead of filling the width.
    expect(tester.getSize(find.byType(Wrap).first).width, lessThan(400));
  });

  group('custom field value at extreme text scale', () {
    testWidgets('grows at 3.375x and keeps its mention tappable', (
      tester,
    ) async {
      const bobId = '99999999-8888-7777-6666-555555555555';
      final bob = Member(id: bobId, name: 'Bob', createdAt: DateTime(2026));
      const data = 'we met @[$bobId] at the market and talked for a while';

      // A 1x baseline in the same host, so growth is measured against this
      // value rather than against a hard-coded line height.
      await _pumpFieldInRouter(tester, data, members: [bob]);
      final baseHeight = tester
          .getSize(find.byType(FieldInlineMarkdownText))
          .height;
      final baseRect = _mentionSelectionRect(
        tester,
        find.textContaining('@Bob'),
        '@Bob',
      );

      // Direct linear 3.375x is equivalent at every size to the production
      // composition PrismTextScaler(TextScaler.linear(2.25), 1.5). The separate
      // nonlinear case checks that composition cannot generally be reduced
      // to one scale factor when the platform curve varies per font size.
      final pushedMemberIds = await _pumpFieldInRouter(
        tester,
        data,
        members: [bob],
        textScaler: const TextScaler.linear(3.375),
      );

      final field = find.byType(FieldInlineMarkdownText);
      final bodySize =
          Theme.of(tester.element(field)).textTheme.bodyMedium?.fontSize ?? 14;
      final scaler = MediaQuery.textScalerOf(tester.element(field));
      expect(
        scaler.scale(bodySize),
        closeTo(bodySize * 3.375, 0.001),
        reason: 'the field itself, not an ancestor wrapper, sees 3.375x',
      );

      // The value grows onto several lines instead of clipping to one.
      final scaledHeight = tester.getSize(field).height;
      expect(scaledHeight, greaterThan(baseHeight));
      expect(
        scaledHeight,
        greaterThan(scaler.scale(bodySize) * 2),
        reason: 'a 3.375x value must occupy several lines of the field',
      );

      // The authored text survives and the raw mention token never leaks.
      final richTexts = tester
          .widgetList<RichText>(
            find.descendant(of: field, matching: find.byType(RichText)),
          )
          .toList();
      final rendered = richTexts
          .map((richText) => richText.text.toPlainText())
          .join();
      expect(rendered, contains('we met'));
      expect(rendered, contains('talked for a while'));
      expect(rendered, contains('@Bob'));
      expect(rendered, isNot(contains('@[$bobId]')));
      for (final richText in richTexts) {
        expect(richText.maxLines, isNull);
        expect(richText.overflow, isNot(TextOverflow.ellipsis));
      }

      final mention = find.textContaining('@Bob');
      expect(mention, findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(mention)
            .textScaler
            .scale(bodySize),
        closeTo(bodySize * 3.375, 0.001),
        reason: 'the mention paragraph layout uses the same scaler',
      );
      final rect = _mentionSelectionRect(tester, mention, '@Bob');
      expect(
        rect.height / baseRect.height,
        closeTo(3.375, 3.375 * 0.1),
        reason:
            'the mention selection-run box layout box must scale, not just its parent',
      );
      final fieldRect = tester.getRect(field);
      expect(
        fieldRect.contains(rect.center),
        isTrue,
        reason: 'the mention selection-run point must be inside the field',
      );
      expect(rect.right, lessThanOrEqualTo(fieldRect.right + 0.5));

      await _tapMentionSelection(tester, mention, '@Bob');

      expect(pushedMemberIds, [bobId]);
      expect(find.text('member-$bobId'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('taps the second mention of a wrapped value, not the first', (
      tester,
    ) async {
      const bobId = '99999999-8888-7777-6666-555555555555';
      const caraId = '77777777-1111-2222-3333-444444444444';
      final bob = Member(id: bobId, name: 'Bob', createdAt: DateTime(2026));
      final cara = Member(id: caraId, name: 'Cara', createdAt: DateTime(2026));
      const data = '@[$bobId] and @[$caraId] were both at the market';

      final pushedMemberIds = await _pumpFieldInRouter(
        tester,
        data,
        members: [bob, cara],
        textScaler: const TextScaler.linear(3.375),
      );

      // Both labels resolve from the real member list, so neither tap can pass
      // through an unresolved 'Unknown' mention.
      expect(find.text('@Bob'), findsOneWidget);
      expect(find.text('@Cara'), findsOneWidget);
      final bobRect = _mentionSelectionRect(tester, find.text('@Bob'), '@Bob');
      final caraRect = _mentionSelectionRect(
        tester,
        find.text('@Cara'),
        '@Cara',
      );
      expect(caraRect.center, isNot(bobRect.center));
      expect(
        caraRect.top,
        greaterThan(bobRect.top + 0.5),
        reason: 'this second-mention case must exercise distinct wrapped runs',
      );

      await _tapMentionSelection(tester, find.text('@Cara'), '@Cara');

      expect(pushedMemberIds, [caraId]);
      expect(find.text('member-$caraId'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grows and stays tappable under the composed scaler', (
      tester,
    ) async {
      const bobId = '99999999-8888-7777-6666-555555555555';
      final bob = Member(id: bobId, name: 'Bob', createdAt: DateTime(2026));
      const data = 'we met @[$bobId] at the market and talked for a while';
      // PrismTextScaler(platform scaler, font-size factor) is what app.dart
      // installs; with a nonlinear platform curve the composition is not a
      // single factor: 3x at 14 pt and 2.1x at 24 pt.
      const composedScaler = PrismTextScaler(_StepNonlinearTextScaler(), 1.5);

      await _pumpFieldInRouter(tester, data, members: [bob]);
      final baseHeight = tester
          .getSize(find.byType(FieldInlineMarkdownText))
          .height;

      final pushedMemberIds = await _pumpFieldInRouter(
        tester,
        data,
        members: [bob],
        textScaler: composedScaler,
      );

      final field = find.byType(FieldInlineMarkdownText);
      final scaler = MediaQuery.textScalerOf(tester.element(field));
      expect(scaler, composedScaler);
      expect(scaler.scale(14), closeTo(42, 0.001));
      expect(scaler.scale(24), closeTo(50.4, 0.001));
      expect(
        scaler.scale(24),
        lessThan(24 * scaler.scale(14) / 14),
        reason: 'the composed provider scaler is nonlinear, not a flat ratio',
      );

      final scaledHeight = tester.getSize(field).height;
      expect(scaledHeight, greaterThan(baseHeight));
      expect(
        scaledHeight,
        greaterThan(scaler.scale(14) * 2),
        reason: 'the composed 42 pt body role must wrap onto several lines',
      );

      final mention = find.textContaining('@Bob');
      expect(mention, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(mention).textScaler,
        composedScaler,
      );

      await _tapMentionSelection(tester, mention, '@Bob');

      expect(pushedMemberIds, [bobId]);
      expect(find.text('member-$bobId'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The selection-run layout box of [label] inside the mention matched by [mention], in
/// global coordinates.
/// These are selection/layout bounds, not raster glyph-ink measurements.
/// Bundled-font painting is not covered by this default-test-font fixture.
///
/// The mention builder emits its label as its own `Text.rich`, so that
/// paragraph holds exactly the label and its selection boxes locate a point for a real pointer
/// tap. The enclosing paragraph's centre would land on other text in the
/// value.
Rect _mentionSelectionRect(WidgetTester tester, Finder mention, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(mention);
  final start = paragraph.text.toPlainText().indexOf(label);
  expect(
    start,
    isNonNegative,
    reason: '$label must belong to its mention paragraph',
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + label.length),
  );
  expect(boxes, isNotEmpty, reason: '$label must have selection boxes');
  final local = boxes.first.toRect();
  return Rect.fromPoints(
    paragraph.localToGlobal(local.topLeft),
    paragraph.localToGlobal(local.bottomRight),
  );
}

/// Scrolls [mention] into view and taps the centre of its [label] selection-run box.
Future<void> _tapMentionSelection(
  WidgetTester tester,
  Finder mention,
  String label,
) async {
  await tester.ensureVisible(mention);
  await tester.pump();
  final point = _mentionSelectionRect(tester, mention, label).center;
  final paragraph = tester.renderObject<RenderParagraph>(mention);
  expect(
    tester
        .hitTestOnBinding(point)
        .path
        .any((entry) => identical(entry.target, paragraph)),
    isTrue,
    reason: 'the selected mention layout point must hit its real paragraph',
  );
  await tester.tapAt(point);
  await tester.pumpAndSettle();
}

/// Pumps a custom field value the way the member detail page shows it —
/// inside a real router and a scrollable column, at [textScaler] — and returns
/// the member ids its mention taps pushed.
Future<List<String>> _pumpFieldInRouter(
  WidgetTester tester,
  String data, {
  List<Member> members = const [],
  TextScaler textScaler = TextScaler.noScaling,
  double width = 390,
}) async {
  final pushedMemberIds = <String>[];
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: FieldInlineMarkdownText(data)),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.members,
        builder: (_, _) => const Scaffold(body: Text('members')),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) {
              final id = state.pathParameters['id']!;
              pushedMemberIds.add(id);
              return Scaffold(body: Text('member-$id'));
            },
          ),
        ],
      ),
    ],
  );
  final appPrefs = FakeAppPreferenceRepository();
  var databaseReads = 0;
  addTearDown(() async {
    // ProviderScope owns its container: unmounting cancels its subscriptions
    // before the router and the fake preference stream controllers are closed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
    await tester.runAsync(
      () => appPrefs.close().timeout(const Duration(seconds: 5)),
    );
    // AsyncValue fallback must not mask an accidental DB-provider read.
    expect(
      databaseReads,
      0,
      reason: 'this fixture must never read the real DB',
    );
  });

  await tester.pumpWidget(
    ProviderScope(
      // A fresh owned container for each baseline/scaled pump, not an override
      // update on the previous fixture's container.
      key: UniqueKey(),
      overrides: [
        memberNamePreferDisplayProvider.overrideWithValue(true),
        memberNamePresentationProvider.overrideWithValue(
          MemberNamePresentation.fullName,
        ),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        frontingTermsSettingProvider.overrideWithValue(null),
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        databaseProvider.overrideWith((ref) {
          databaseReads += 1;
          throw StateError(
            'Pronoun regression fixtures must not open a database',
          );
        }),
        activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
      ],
      child: MaterialApp.router(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return pushedMemberIds;
}

/// A platform-like nonlinear scaler: it reports 1.5, doubles body sizes and
/// grows larger sizes by 1.4, the way a nonlinear accessibility curve does.
class _StepNonlinearTextScaler extends TextScaler {
  const _StepNonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.4;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.5;
}
