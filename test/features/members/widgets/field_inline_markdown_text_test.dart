import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';

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
}
