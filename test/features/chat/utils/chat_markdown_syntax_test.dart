import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

void main() {
  group('MentionSyntax', () {
    test('parses a valid mention and emits a mention element', () {
      const input = 'hi @[11111111-2222-3333-4444-555555555555]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes
          .whereType<md.Element>()
          .where((e) => e.tag == 'mention')
          .toList();
      expect(mentions, hasLength(1));
      expect(
          mentions.first.attributes['id'], '11111111-2222-3333-4444-555555555555');
    });

    test('does not emit mention for malformed uuid', () {
      const input = '@[not-a-uuid]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes
          .whereType<md.Element>()
          .where((e) => e.tag == 'mention')
          .toList();
      expect(mentions, isEmpty);
    });

    test('does not emit mention for empty brackets', () {
      const input = '@[]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes
          .whereType<md.Element>()
          .where((e) => e.tag == 'mention')
          .toList();
      expect(mentions, isEmpty);
    });
  });

  group('escapeLeadingHeadings', () {
    test('escapes single hash heading', () {
      expect(escapeLeadingHeadings('# foo'), '\\# foo');
    });

    test('escapes double hash heading', () {
      expect(escapeLeadingHeadings('## bar'), '\\## bar');
    });

    test('escapes six-level heading', () {
      expect(escapeLeadingHeadings('###### deep'), '\\###### deep');
    });

    test('does not escape indented hash', () {
      expect(escapeLeadingHeadings('  # foo'), '  # foo');
    });

    test('does not escape hash with no space', () {
      expect(escapeLeadingHeadings('#foo'), '#foo');
    });

    test('escapes multiple heading lines in multi-line string', () {
      expect(escapeLeadingHeadings('# a\n## b\ntext'), '\\# a\n\\## b\ntext');
    });

    test('returns empty string unchanged', () {
      expect(escapeLeadingHeadings(''), '');
    });

    test('returns plain text unchanged', () {
      expect(escapeLeadingHeadings('no hash here'), 'no hash here');
    });
  });

  group('hasMarkdownChars', () {
    test('returns false for plain text', () {
      expect(hasMarkdownChars('hello world'), isFalse);
    });

    test('returns true when bold markers present', () {
      expect(hasMarkdownChars('hello **world**'), isTrue);
    });

    test('returns true when italic underscore present', () {
      expect(hasMarkdownChars('hello _world_'), isTrue);
    });

    test('returns true when mention token present', () {
      expect(hasMarkdownChars('hello @[uuid]'), isTrue);
    });

    test("returns false for apostrophe in don't", () {
      expect(hasMarkdownChars("don't"), isFalse);
    });

    test('returns false for empty string', () {
      expect(hasMarkdownChars(''), isFalse);
    });

    test('returns true for inline code backtick', () {
      expect(hasMarkdownChars('`code`'), isTrue);
    });

    test('returns true for link bracket', () {
      expect(hasMarkdownChars('link [text](url)'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Member makeMember({
    required String id,
    required String name,
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

  // -------------------------------------------------------------------------
  // MentionBuilder
  // -------------------------------------------------------------------------

  group('MentionBuilder', () {
    const uuid = '11111111-2222-3333-4444-555555555555';
    const mentionData = '@[$uuid]';

    testWidgets('renders member name with primary color when customColor disabled',
        (tester) async {
      final member = makeMember(id: uuid, name: 'Alice');
      final authorMap = {uuid: member};

      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: mentionData,
                extensionSet: chatExtensionSet,
                builders: {
                  'mention': MentionBuilder(
                    authorMap: authorMap,
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('@Alice'), findsOneWidget);

      final richText = tester.widget<Text>(find.text('@Alice'));
      expect(richText.textSpan?.style?.color, capturedTheme.colorScheme.primary);
    });

    testWidgets('renders member name with custom color when customColor enabled',
        (tester) async {
      final member = makeMember(
        id: uuid,
        name: 'Alice',
        customColorEnabled: true,
        customColorHex: '#FF0000',
      );
      final authorMap = {uuid: member};

      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: mentionData,
                extensionSet: chatExtensionSet,
                builders: {
                  'mention': MentionBuilder(
                    authorMap: authorMap,
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('@Alice'), findsOneWidget);
      final richText = tester.widget<Text>(find.text('@Alice'));
      // #FF0000 → Color(0xFFFF0000)
      expect(richText.textSpan?.style?.color, const Color(0xFFFF0000));
    });

    testWidgets('renders Unknown for member not in authorMap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              return MarkdownBody(
                data: mentionData,
                extensionSet: chatExtensionSet,
                builders: {
                  'mention': MentionBuilder(
                    authorMap: const {},
                    theme: Theme.of(ctx),
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('@Unknown'), findsOneWidget);
    });

    testWidgets(
        'bold mention preserves w600 weight and mention color (parentStyle merge)',
        (tester) async {
      final member = makeMember(id: uuid, name: 'Alice');
      final authorMap = {uuid: member};

      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: '**@[$uuid]**',
                extensionSet: chatExtensionSet,
                builders: {
                  'mention': MentionBuilder(
                    authorMap: authorMap,
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('@Alice'), findsOneWidget);
      final richText = tester.widget<Text>(find.text('@Alice'));
      final weight = richText.textSpan?.style?.fontWeight;
      expect(
        weight,
        anyOf(FontWeight.w600, FontWeight.bold, FontWeight.w700),
        reason: 'Mention weight should be bold-ish (w600+)',
      );
      expect(
        richText.textSpan?.style?.color,
        capturedTheme.colorScheme.primary,
      );
    });
  });

  // -------------------------------------------------------------------------
  // SafeLinkBuilder
  // -------------------------------------------------------------------------

  group('SafeLinkBuilder', () {
    testWidgets('https link renders with underline', (tester) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: '[click](https://example.com)',
                extensionSet: chatExtensionSet,
                builders: {
                  'a': SafeLinkBuilder(
                    onTap: (_) {},
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('click'), findsOneWidget);
      final text = tester.widget<Text>(find.text('click'));
      expect(text.style?.decoration, TextDecoration.underline);
    });

    testWidgets('http link renders with underline', (tester) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: '[click](http://example.com)',
                extensionSet: chatExtensionSet,
                builders: {
                  'a': SafeLinkBuilder(
                    onTap: (_) {},
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('click'), findsOneWidget);
      final text = tester.widget<Text>(find.text('click'));
      expect(text.style?.decoration, TextDecoration.underline);
    });

    testWidgets('javascript: link renders as plain text (no GestureDetector)',
        (tester) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: '[click](javascript:alert(1))',
                extensionSet: chatExtensionSet,
                builders: {
                  'a': SafeLinkBuilder(
                    onTap: (_) {},
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('click'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('click'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('mailto: link renders as plain text (no GestureDetector)',
        (tester) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              return MarkdownBody(
                data: '[click](mailto:x@y.com)',
                extensionSet: chatExtensionSet,
                builders: {
                  'a': SafeLinkBuilder(
                    onTap: (_) {},
                    theme: capturedTheme,
                  ),
                },
              );
            }),
          ),
        ),
      );

      expect(find.text('click'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('click'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------------
  // chatStylesheet
  // -------------------------------------------------------------------------

  group('chatStylesheet', () {
    setUp(debugResetChatStylesheetCache);

    testWidgets('returns cached instance on repeated calls', (tester) async {
      debugResetChatStylesheetCache();
      late MarkdownStyleSheet first;
      late MarkdownStyleSheet second;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              const style = TextStyle(fontSize: 14);
              first = chatStylesheet(ctx, style);
              second = chatStylesheet(ctx, style);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      expect(identical(first, second), isTrue);
    });

    testWidgets('returns different instances for different theme brightness',
        (tester) async {
      debugResetChatStylesheetCache();
      late MarkdownStyleSheet lightSheet;
      late MarkdownStyleSheet darkSheet;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(builder: (ctx) {
              lightSheet = chatStylesheet(ctx, const TextStyle(fontSize: 14));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      debugResetChatStylesheetCache();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(builder: (ctx) {
              darkSheet = chatStylesheet(ctx, const TextStyle(fontSize: 14));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      expect(identical(lightSheet, darkSheet), isFalse);
    });

    testWidgets('code backgroundColor is onSurface with alpha 26',
        (tester) async {
      debugResetChatStylesheetCache();
      late MarkdownStyleSheet sheet;
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              capturedTheme = Theme.of(ctx);
              sheet = chatStylesheet(ctx, const TextStyle(fontSize: 14));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      expect(
        sheet.code?.backgroundColor,
        capturedTheme.colorScheme.onSurface.withAlpha(26),
      );
    });

    testWidgets('heading styles equal p style', (tester) async {
      debugResetChatStylesheetCache();
      late MarkdownStyleSheet sheet;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              sheet = chatStylesheet(ctx, const TextStyle(fontSize: 14));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      expect(sheet.h1, sheet.p, reason: 'h1 should equal p');
      expect(sheet.h2, sheet.p, reason: 'h2 should equal p');
      expect(sheet.h3, sheet.p, reason: 'h3 should equal p');
      expect(sheet.h4, sheet.p, reason: 'h4 should equal p');
      expect(sheet.h5, sheet.p, reason: 'h5 should equal p');
      expect(sheet.h6, sheet.p, reason: 'h6 should equal p');
    });

    testWidgets('p style has letterSpacing stripped to 0', (tester) async {
      debugResetChatStylesheetCache();
      late MarkdownStyleSheet sheet;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              sheet = chatStylesheet(ctx, const TextStyle(fontSize: 14));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      expect(sheet.p?.letterSpacing, 0);
    });
  });
}
