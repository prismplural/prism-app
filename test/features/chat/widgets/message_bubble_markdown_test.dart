/// Tests for the Task 6 wiring: ChatMessageText in MessageBubble, markdown
/// stripping in _ReplyQuote, and ChatMarkdownEditingController in the edit
/// dialog.
///
/// Because MessageBubble is a ConsumerStatefulWidget that requires a large
/// Riverpod provider tree, these tests focus on the units that MessageBubble
/// delegates to:
///   - ChatMessageText for body rendering (bold, MarkdownBody presence).
///   - stripChatMarkdown for the reply-quote preview.
///   - ChatMarkdownEditingController as the edit-dialog controller type.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/markdown_utils.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const _kMentionId = '11111111-2222-3333-4444-555555555555';
const _kBaseStyle = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w400);
const _kDefaultColor = Colors.black;

Member _makeMember({
  String id = _kMentionId,
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

Widget _wrapText(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

Widget _chatText({
  required String content,
  Map<String, Member>? authorMap,
}) =>
    _wrapText(
      ChatMessageText(
        content: content,
        authorMap: authorMap,
        baseStyle: _kBaseStyle,
        defaultColor: _kDefaultColor,
      ),
    );

// ---------------------------------------------------------------------------
// 1. Body rendering: bold text uses MarkdownBody
// ---------------------------------------------------------------------------

void main() {
  // Reset the stylesheet cache between tests to avoid cross-test pollution.
  setUp(debugResetChatStylesheetCache);

  group('1. bold rendering via ChatMessageText', () {
    testWidgets('**bold** uses MarkdownBody and renders "bold"',
        (tester) async {
      await tester.pumpWidget(_chatText(content: '**bold**'));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('bold'), findsAtLeastNWidgets(1));
    });

    testWidgets('plain text does not use MarkdownBody', (tester) async {
      await tester.pumpWidget(_chatText(content: 'hello world'));
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.textContaining('hello world'), findsAtLeastNWidgets(1));
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Edit dialog controller type
  // ---------------------------------------------------------------------------

  group('2. ChatMarkdownEditingController usable as TextEditingController',
      () {
    test('is a subtype of TextEditingController', () {
      final controller = ChatMarkdownEditingController(text: 'hello **world**');
      expect(controller, isA<TextEditingController>());
    });

    test('initial text is preserved', () {
      const content = 'hello **world**';
      final controller = ChatMarkdownEditingController(text: content);
      expect(controller.text, content);
    });

    testWidgets('can be assigned to a TextField without error', (tester) async {
      final controller = ChatMarkdownEditingController(text: '**test**');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ));
      // updateTheme requires a valid BuildContext with Theme.
      final context = tester.element(find.byType(TextField));
      controller.updateTheme(context);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. _ReplyQuote strips markdown (tested via stripChatMarkdown unit tests)
  // ---------------------------------------------------------------------------

  group('3. stripChatMarkdown for _ReplyQuote preview', () {
    test('strips **bold** markers, leaving plain text', () {
      expect(stripChatMarkdown('**hello**', null), 'hello');
    });

    test('strips *italic* markers', () {
      expect(stripChatMarkdown('*hi*', null), 'hi');
    });

    test('strips _italic_ markers', () {
      expect(stripChatMarkdown('_world_', null), 'world');
    });

    test('strips inline code markers', () {
      expect(stripChatMarkdown('`code`', null), 'code');
    });

    test('strips markdown link, keeps label', () {
      expect(stripChatMarkdown('[label](https://example.com)', null), 'label');
    });

    test('plain text passes through unchanged', () {
      expect(stripChatMarkdown('hello world', null), 'hello world');
    });
  });

  // ---------------------------------------------------------------------------
  // 4. _ReplyQuote resolves mentions (tested via stripChatMarkdown unit tests)
  // ---------------------------------------------------------------------------

  group('4. _ReplyQuote mention resolution via stripChatMarkdown', () {
    test('resolves mention UUID to @Name', () {
      final authorMap = {_kMentionId: _makeMember()};
      final result = stripChatMarkdown('hi @[$_kMentionId]', authorMap);
      expect(result, 'hi @Alice');
    });

    test('unknown UUID falls back to @Unknown', () {
      final result = stripChatMarkdown('hi @[$_kMentionId]', {});
      expect(result, 'hi @Unknown');
    });

    test('strips markdown AND resolves mention in same string', () {
      final authorMap = {_kMentionId: _makeMember()};
      final result =
          stripChatMarkdown('**hey** @[$_kMentionId]', authorMap);
      expect(result, 'hey @Alice');
    });

    test('null authorMap falls back to @Unknown for all mentions', () {
      final result = stripChatMarkdown('@[$_kMentionId]', null);
      expect(result, '@Unknown');
    });
  });

  // ---------------------------------------------------------------------------
  // 5. _ReplyQuote redacts spoilers (Task 7).
  //
  // MessageBubble requires a heavy Riverpod provider tree (ProviderScope plus
  // mocked providers for members, messages, permissions, media, voice, and
  // more), so mounting the full widget solely to exercise the reply-quote
  // preview isn't tractable in this suite. The reply quote builds its preview
  // by calling `stripChatMarkdown(redactSpoilers(content), authorMap)`, so we
  // exercise that exact composition directly — matching the pattern the
  // earlier groups in this file use for _ReplyQuote coverage.
  // ---------------------------------------------------------------------------

  group('5. _ReplyQuote redacts spoilers before stripping markdown', () {
    test('||hidden ending|| is redacted in the reply-quote preview', () {
      final preview = stripChatMarkdown(
        redactSpoilers('plot: ||hidden ending|| whoa'),
        {},
      );
      expect(preview.contains('ending'), isFalse,
          reason: 'spoiler content must not leak into the reply preview');
      expect(preview.contains('hidden'), isFalse);
      expect(preview.contains('▮'), isTrue,
          reason: 'redacted span should render as ▮ block characters');
    });

    test('redaction survives markdown stripping when mixed with **bold**', () {
      final preview = stripChatMarkdown(
        redactSpoilers('**spoiler:** ||the butler did it||'),
        {},
      );
      expect(preview.contains('butler'), isFalse);
      expect(preview.contains('▮'), isTrue);
      // The surrounding bold markers still strip cleanly.
      expect(preview.contains('spoiler:'), isTrue);
    });

    test('plain text without spoilers is unchanged', () {
      expect(
        stripChatMarkdown(redactSpoilers('nothing to hide'), {}),
        'nothing to hide',
      );
    });
  });
}
