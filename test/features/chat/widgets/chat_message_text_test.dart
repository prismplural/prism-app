import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';

Member _makeMember({
  String id = '11111111-2222-3333-4444-555555555555',
  String name = 'Alice',
  bool customColorEnabled = false,
  String? customColorHex,
}) {
  return Member(
    id: id,
    name: name,
    createdAt: DateTime(2024),
    customColorEnabled: customColorEnabled,
    customColorHex: customColorHex,
  );
}

const _kBaseStyle = TextStyle(fontSize: 15.5);
const _kDefaultColor = Colors.black;
const _kMentionId = '11111111-2222-3333-4444-555555555555';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Builder(builder: (ctx) => child)),
);

Widget _widget({required String content, Map<String, Member>? authorMap}) {
  return _wrap(
    ChatMessageText(
      content: content,
      authorMap: authorMap,
      baseStyle: _kBaseStyle,
      defaultColor: _kDefaultColor,
    ),
  );
}

double? _renderedFontSize(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  final span = widget.textSpan;
  if (span is TextSpan) {
    final spanSize = _fontSizeForText(span, text);
    if (spanSize != null) return spanSize;
  }
  return widget.style?.fontSize ??
      (span is TextSpan ? span.style?.fontSize : null);
}

double? _renderedLineHeight(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  final span = widget.textSpan;
  return widget.style?.height ?? (span is TextSpan ? span.style?.height : null);
}

List<String>? _renderedFontFamilyFallback(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  final span = widget.textSpan;
  if (span is TextSpan) {
    final spanFallback = _fontFallbackForText(span, text);
    if (spanFallback != null) return spanFallback;
  }
  return widget.style?.fontFamilyFallback ??
      (span is TextSpan ? span.style?.fontFamilyFallback : null);
}

double? _fontSizeForText(
  TextSpan span,
  String text, [
  TextStyle? inheritedStyle,
]) {
  final style =
      inheritedStyle?.merge(span.style) ?? span.style ?? inheritedStyle;
  if (span.text == text) return style?.fontSize;

  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) {
      final result = _fontSizeForText(child, text, style);
      if (result != null) return result;
    }
  }
  return null;
}

List<String>? _fontFallbackForText(
  TextSpan span,
  String text, [
  TextStyle? inheritedStyle,
]) {
  final style =
      inheritedStyle?.merge(span.style) ?? span.style ?? inheritedStyle;
  if (span.text == text) return style?.fontFamilyFallback;

  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) {
      final result = _fontFallbackForText(child, text, style);
      if (result != null) return result;
    }
  }
  return null;
}

void main() {
  // Reset the stylesheet cache between tests to avoid cross-test pollution.
  setUp(debugResetChatStylesheetCache);

  group('ChatMessageText', () {
    testWidgets('1. empty content renders SizedBox.shrink', (tester) async {
      await tester.pumpWidget(_widget(content: ''));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets('2. plain text uses fast path (no MarkdownBody)', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: 'hello world'));
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(Text), findsAtLeastNWidgets(1));
    });

    testWidgets(
      '3. text with mention goes through slow path (@ triggers markdown char check) and shows @Alice',
      (tester) async {
        final map = {_kMentionId: _makeMember()};
        await tester.pumpWidget(
          _widget(content: 'hi @[$_kMentionId]', authorMap: map),
        );
        // '@' is in hasMarkdownChars, so content with mentions takes the slow path.
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.textContaining('@Alice'), findsOneWidget);
      },
    );

    testWidgets('3b. broadcast mentions render through markdown path', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: 'hi @everyone and @all'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.textContaining('@everyone', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('@all', findRichText: true), findsOneWidget);
    });

    testWidgets('3c. broadcast false positives render as plain text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _widget(content: 'not@all @alliance @everyoneish'),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.textContaining('not@all', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('@all'), findsNothing);
      expect(find.text('@everyone'), findsNothing);
    });

    testWidgets('4. bold text uses slow path (MarkdownBody present)', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '**hello**'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('hello'), findsOneWidget);
    });

    testWidgets('5. italic text uses slow path', (tester) async {
      await tester.pumpWidget(_widget(content: '*hi*'));
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets(
      '5b. small text marker renders without marker at smaller size',
      (tester) async {
        await tester.pumpWidget(_widget(content: '-# im smol'));

        expect(find.textContaining('-#'), findsNothing);
        expect(find.text('im smol'), findsOneWidget);
        expect(_renderedFontSize(tester, 'im smol'), lessThan(15.5));
      },
    );

    testWidgets('5c. small text keeps markdown small after normal markdown', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '**normal**\n-# **smol**'));

      expect(find.text('normal'), findsOneWidget);
      expect(find.text('smol'), findsOneWidget);
      expect(_renderedFontSize(tester, 'smol'), lessThan(15.5));
    });

    testWidgets('5d. repeated small text lines do not duplicate keys', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '-# foo\n-# foo'));
      expect(tester.takeException(), isNull);
      expect(find.text('foo'), findsNWidgets(2));

      await tester.pumpWidget(_widget(content: '-# foo\n-# foo'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. bold + mention uses slow path and shows @Alice', (
      tester,
    ) async {
      final map = {_kMentionId: _makeMember()};
      await tester.pumpWidget(
        _widget(content: '**@[$_kMentionId]**', authorMap: map),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('@Alice'), findsOneWidget);
    });

    testWidgets('7. inline code uses slow path', (tester) async {
      await tester.pumpWidget(_widget(content: '`code`'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('code'), findsOneWidget);
    });

    testWidgets('8. content > 2000 chars with markdown uses fast path', (
      tester,
    ) async {
      // Build a 2500-char string that contains **bold** markdown.
      final long = 'a' * 2490 + '**bold**';
      expect(long.length, greaterThan(2000));
      await tester.pumpWidget(_widget(content: long));
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets('8b. fast path redacts spoilers so plaintext cannot leak', (
      tester,
    ) async {
      // A >2000 char message with an embedded spoiler takes the fast path.
      // Without redaction the plaintext would render visibly.
      final long = 'a' * 2490 + ' ||secret|| tail';
      expect(long.length, greaterThan(2000));
      await tester.pumpWidget(_widget(content: long));
      expect(find.byType(MarkdownBody), findsNothing);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? ''))
          .join(' | ');
      expect(texts, isNot(contains('secret')));
      expect(texts, contains('\u25AE'));
    });

    testWidgets(
      '9. leading # without markdown chars takes fast path and renders literally',
      (tester) async {
        // '#' is not in hasMarkdownChars. So '# hello' → fast path → rendered as
        // plain Text, not MarkdownBody. (Chat does not support headings — they
        // would otherwise be escaped by escapeLeadingHeadings on the slow path.)
        await tester.pumpWidget(_widget(content: '# hello'));
        expect(find.byType(MarkdownBody), findsNothing);
        expect(find.textContaining('# hello'), findsOneWidget);
      },
    );

    testWidgets(
      '9b. blockquote enters slow path and does not render literal `> ` prefix',
      (tester) async {
        // Regression: '>' was missing from hasMarkdownChars, so '> test' used to
        // fast-path and render the literal '> test' string.
        await tester.pumpWidget(_widget(content: '> hello'));
        expect(find.byType(MarkdownBody), findsOneWidget);
        // The rendered text should be just 'hello' — the '>' marker is consumed
        // by the block parser, not echoed as a character.
        expect(find.text('hello'), findsOneWidget);
        expect(find.textContaining('> hello'), findsNothing);
      },
    );

    testWidgets('10. javascript link renders text without GestureDetector', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '[x](javascript:alert(1))'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('x'), findsOneWidget);
      // SafeLinkBuilder renders plain Text for non-http links — no GestureDetector.
      expect(
        find.ancestor(
          of: find.textContaining('x'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('11. http link renders GestureDetector for "click"', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '[click](https://example.com)'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('click'),
          matching: find.byType(GestureDetector),
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets(
      '11b. dangerous-scheme chat links never reach the platform launcher',
      (tester) async {
        // Peer-supplied dangerous-scheme links must never reach launchUrl:
        // SafeLinkBuilder renders them inert and _openExternal's allowlist is
        // the backstop.
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        final launched = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'launch') {
              final args = call.arguments as Map<Object?, Object?>;
              launched.add(args['url']! as String);
              return true;
            }
            return false;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );

        for (final href in const [
          'javascript:alert(1)',
          'file:///etc/passwd',
          'intent://scan/#Intent;scheme=zxing;end',
        ]) {
          await tester.pumpWidget(_widget(content: '[tap]($href)'));
          // No tappable affordance is rendered for non-http(s) schemes.
          expect(
            find.ancestor(
              of: find.textContaining('tap'),
              matching: find.byType(GestureDetector),
            ),
            findsNothing,
            reason: '$href must not render a tappable link',
          );
          // Belt-and-suspenders: tapping the label is a no-op, not a launch.
          await tester.tap(find.textContaining('tap'));
          await tester.pump();
        }

        expect(launched, isEmpty);
      },
    );

    testWidgets(
      '12. visible mention re-renders when authorMap loads after first paint',
      (tester) async {
        await tester.pumpWidget(
          _widget(content: 'hi @[$_kMentionId]', authorMap: const {}),
        );
        expect(
          find.textContaining('@Unknown', findRichText: true),
          findsOneWidget,
        );

        await tester.pumpWidget(
          _widget(
            content: 'hi @[$_kMentionId]',
            authorMap: {_kMentionId: _makeMember()},
          ),
        );
        await tester.pump();

        expect(
          find.textContaining('@Unknown', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('@Alice', findRichText: true),
          findsOneWidget,
        );
      },
    );

    testWidgets('13. single emoji-only message renders sticker-sized', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '🥴'));
      expect(find.byType(MarkdownBody), findsNothing);

      expect(_renderedFontSize(tester, '🥴'), 48);
      expect(_renderedLineHeight(tester, '🥴'), 1.0);
      expect(
        _renderedFontFamilyFallback(tester, '🥴') ?? const <String>[],
        isNot(contains('Noto Sans Symbols')),
      );
    });

    testWidgets('14. emoji-only message with whitespace is enlarged', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: '  ✨ ✨  '));

      expect(_renderedFontSize(tester, '✨ ✨'), 40);
      expect(_renderedLineHeight(tester, '✨ ✨'), 1.0);
    });

    testWidgets('15. mixed text with emoji stays normal chat size', (
      tester,
    ) async {
      await tester.pumpWidget(_widget(content: 'hey 🥴'));

      expect(_renderedFontSize(tester, 'hey 🥴'), _kBaseStyle.fontSize);
    });

    testWidgets('16. seven emoji falls back to normal chat size', (
      tester,
    ) async {
      const content = '✨✨✨✨✨✨✨';
      await tester.pumpWidget(_widget(content: content));

      expect(_renderedFontSize(tester, content), _kBaseStyle.fontSize);
      expect(
        _renderedFontFamilyFallback(tester, content) ?? const <String>[],
        isNot(contains('Noto Sans Symbols')),
      );
    });

    testWidgets('17. text-presentation symbol stays normal chat size', (
      tester,
    ) async {
      const content = '\u231B\uFE0E';
      await tester.pumpWidget(_widget(content: content));

      expect(_renderedFontSize(tester, content), _kBaseStyle.fontSize);
      expect(
        _renderedFontFamilyFallback(tester, content),
        contains('Noto Sans Symbols'),
      );
    });
  });

  group('emojiStickerFontSize', () {
    test('classifies emoji-only content by grapheme count', () {
      expect(emojiStickerFontSize('🥴', _kBaseStyle), 48);
      expect(emojiStickerFontSize('✨✨', _kBaseStyle), 40);
      expect(emojiStickerFontSize('🌸🌙✨', _kBaseStyle), 40);
      expect(emojiStickerFontSize('🌸🌙✨💫', _kBaseStyle), 32);
      expect(emojiStickerFontSize('🌸🌙✨💫⭐️🫧', _kBaseStyle), 32);
    });

    test('handles composed emoji as one displayed emoji', () {
      expect(emojiStickerFontSize('👍🏽', _kBaseStyle), 48);
      expect(emojiStickerFontSize('👨‍👩‍👧‍👦', _kBaseStyle), 48);
      expect(emojiStickerFontSize('🇨🇷', _kBaseStyle), 48);
      expect(emojiStickerFontSize('1️⃣', _kBaseStyle), 48);
    });

    test('rejects non-emoji and long emoji runs', () {
      expect(emojiStickerFontSize('', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('   ', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('hey 🥴', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('🥴!', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('||🥴||', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('\u231B\uFE0E', _kBaseStyle), isNull);
      expect(emojiStickerFontSize('✨✨✨✨✨✨✨', _kBaseStyle), isNull);
    });

    test('allows whitespace between emoji', () {
      expect(emojiStickerFontSize('✨ ✨', _kBaseStyle), 40);
      expect(emojiStickerFontSize('🌸\n🌙\t✨', _kBaseStyle), 40);
    });
  });

  group('buildMentionSpan unit tests', () {
    test('no mentions: flattened text equals input', () {
      final theme = ThemeData.light();
      final span = buildMentionSpan(
        content: 'hello world',
        authorMap: null,
        theme: theme,
        defaultColor: Colors.black,
        baseStyle: _kBaseStyle,
      );
      // Flatten the span.
      final buf = StringBuffer();
      span.visitChildren((child) {
        if (child is TextSpan) buf.write(child.text ?? '');
        return true;
      });
      final text = span.text ?? buf.toString();
      expect(text, 'hello world');
    });

    test('with mention: fontWeight w600 and text contains @Alice', () {
      final theme = ThemeData.light();
      final map = {_kMentionId: _makeMember()};
      final span = buildMentionSpan(
        content: 'hi @[$_kMentionId]',
        authorMap: map,
        theme: theme,
        defaultColor: Colors.black,
        baseStyle: _kBaseStyle,
      );

      TextSpan? mentionSpan;
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text != null &&
            child.text!.startsWith('@')) {
          mentionSpan = child;
        }
        return true;
      });

      expect(mentionSpan, isNotNull);
      expect(mentionSpan!.text, '@Alice');
      expect(mentionSpan!.style?.fontWeight, FontWeight.w600);
    });

    test('missing member: text contains @Unknown', () {
      final theme = ThemeData.light();
      // authorMap is empty — member not found.
      final span = buildMentionSpan(
        content: '@[$_kMentionId]',
        authorMap: {},
        theme: theme,
        defaultColor: Colors.black,
        baseStyle: _kBaseStyle,
      );

      TextSpan? mentionSpan;
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text != null &&
            child.text!.startsWith('@')) {
          mentionSpan = child;
        }
        return true;
      });

      expect(mentionSpan, isNotNull);
      expect(mentionSpan!.text, '@Unknown');
    });

    test('broadcast aliases keep typed text and mention styling', () {
      final theme = ThemeData.light();
      final span = buildMentionSpan(
        content: 'hi @everyone and @all',
        authorMap: {},
        theme: theme,
        defaultColor: Colors.black,
        baseStyle: _kBaseStyle,
      );

      final mentionTexts = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text != null &&
            child.text!.startsWith('@')) {
          mentionTexts.add(child.text!);
          expect(child.style?.fontWeight, FontWeight.w600);
        }
        return true;
      });

      expect(mentionTexts, ['@everyone', '@all']);
    });

    test('broadcast false positives are not split into mention spans', () {
      final theme = ThemeData.light();
      final span = buildMentionSpan(
        content: 'not@all @alliance @everyoneish',
        authorMap: {},
        theme: theme,
        defaultColor: Colors.black,
        baseStyle: _kBaseStyle,
      );

      expect(span.children, isNull);
      expect(span.text, 'not@all @alliance @everyoneish');
    });
  });

  group('fuzz', () {
    testWidgets('1000 random strings do not throw', (tester) async {
      final rng = Random(1337);
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789 *_`[]()@#\\\n';
      for (var i = 0; i < 1000; i++) {
        final len = 1 + rng.nextInt(300);
        final sb = StringBuffer();
        for (var j = 0; j < len; j++) {
          sb.write(chars[rng.nextInt(chars.length)]);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatMessageText(
                content: sb.toString(),
                authorMap: null,
                baseStyle: const TextStyle(fontSize: 14),
                defaultColor: Colors.black,
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'fuzz iteration $i, input: ${sb.toString()}',
        );
      }
    });
  });

  group('RTL', () {
    testWidgets('Arabic text with inline bold renders without error', (
      tester,
    ) async {
      const arabic = 'مرحبا **world** اهلا';
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ChatMessageText(
                content: arabic,
                authorMap: null,
                baseStyle: TextStyle(fontSize: 14),
                defaultColor: Colors.black,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('مرحبا'), findsOneWidget);
    });
  });
}
