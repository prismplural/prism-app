import 'dart:math';

import 'package:flutter/material.dart';
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
      home: Scaffold(
        body: Builder(builder: (ctx) => child),
      ),
    );

Widget _widget({
  required String content,
  Map<String, Member>? authorMap,
}) {
  return _wrap(
    ChatMessageText(
      content: content,
      authorMap: authorMap,
      baseStyle: _kBaseStyle,
      defaultColor: _kDefaultColor,
    ),
  );
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

    testWidgets('2. plain text uses fast path (no MarkdownBody)', (tester) async {
      await tester.pumpWidget(_widget(content: 'hello world'));
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(Text), findsAtLeastNWidgets(1));
    });

    testWidgets(
        '3. text with mention goes through slow path (@ triggers markdown char check) and shows @Alice',
        (tester) async {
      final map = {_kMentionId: _makeMember()};
      await tester.pumpWidget(_widget(
        content: 'hi @[$_kMentionId]',
        authorMap: map,
      ));
      // '@' is in hasMarkdownChars, so content with mentions takes the slow path.
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('@Alice'), findsOneWidget);
    });

    testWidgets('4. bold text uses slow path (MarkdownBody present)',
        (tester) async {
      await tester.pumpWidget(_widget(content: '**hello**'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('hello'), findsOneWidget);
    });

    testWidgets('5. italic text uses slow path', (tester) async {
      await tester.pumpWidget(_widget(content: '*hi*'));
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('6. bold + mention uses slow path and shows @Alice',
        (tester) async {
      final map = {_kMentionId: _makeMember()};
      await tester.pumpWidget(_widget(
        content: '**@[$_kMentionId]**',
        authorMap: map,
      ));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('@Alice'), findsOneWidget);
    });

    testWidgets('7. inline code uses slow path', (tester) async {
      await tester.pumpWidget(_widget(content: '`code`'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('code'), findsOneWidget);
    });

    testWidgets('8. content > 2000 chars with markdown uses fast path',
        (tester) async {
      // Build a 2500-char string that contains **bold** markdown.
      final long = 'a' * 2490 + '**bold**';
      expect(long.length, greaterThan(2000));
      await tester.pumpWidget(_widget(content: long));
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets(
        '9. leading # without markdown chars takes fast path and renders literally',
        (tester) async {
      // '#' is not in hasMarkdownChars (only *, _, `, [, @ are checked).
      // So '# hello' → fast path → rendered as plain Text, not MarkdownBody.
      await tester.pumpWidget(_widget(content: '# hello'));
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.textContaining('# hello'), findsOneWidget);
    });

    testWidgets(
        '10. javascript link renders text without GestureDetector', (tester) async {
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

    testWidgets('11. http link renders GestureDetector for "click"',
        (tester) async {
      await tester.pumpWidget(_widget(
          content: '[click](https://example.com)'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('click'),
          matching: find.byType(GestureDetector),
        ),
        findsAtLeastNWidgets(1),
      );
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
    testWidgets('Arabic text with inline bold renders without error',
        (tester) async {
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
