import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  const nbsp = ' ';

  group('preserveBlankLines (pure function)', () {
    test('empty input', () {
      expect(preserveBlankLines(''), '');
    });

    test('no blank lines', () {
      expect(preserveBlankLines('hello\nworld'), 'hello\nworld');
    });

    test('single blank line (normal paragraph break) unchanged', () {
      expect(preserveBlankLines('A\n\nB'), 'A\n\nB');
    });

    test('two blank lines inserts one spacer', () {
      expect(preserveBlankLines('A\n\n\nB'), 'A\n\n$nbsp\n\nB');
    });

    test('three blank lines inserts two spacers', () {
      expect(preserveBlankLines('A\n\n\n\nB'), 'A\n\n$nbsp\n\n$nbsp\n\nB');
    });

    test('caps spacers at 10', () {
      // 20 blank lines in a row — only 10 spacers should be emitted.
      final input = 'A\n${'\n' * 20}B';
      final result = preserveBlankLines(input);
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 10);
    });

    test('multiple separate blank line runs', () {
      const input = 'A\n\n\nB\n\n\n\nC';
      final result = preserveBlankLines(input);
      expect(result, 'A\n\n$nbsp\n\nB\n\n$nbsp\n\n$nbsp\n\nC');
    });

    test('blank lines inside backtick fence are untouched', () {
      const input = '```\nA\n\n\nB\n```';
      expect(preserveBlankLines(input), input);
    });

    test('blank lines inside tilde fence are untouched', () {
      const input = '~~~\nA\n\n\nB\n~~~';
      expect(preserveBlankLines(input), input);
    });

    test('fence with info string', () {
      const input = '```dart\nA\n\n\nB\n```';
      expect(preserveBlankLines(input), input);
    });

    test('blank lines before and after fence are processed', () {
      const input = 'before\n\n\n```\ncode\n\n\n```\n\n\nafter';
      final result = preserveBlankLines(input);
      expect(result, 'before\n\n$nbsp\n\n```\ncode\n\n\n```\n\n$nbsp\n\nafter');
    });

    test('longer closing fence matches', () {
      const input = '```\nA\n\n\nB\n`````';
      expect(preserveBlankLines(input), input);
    });

    test('mismatched fence character does not close', () {
      const input = '```\nA\n\n\nB\n~~~\nC\n```';
      expect(preserveBlankLines(input), input);
    });

    test('lines with only spaces/tabs count as blank', () {
      expect(preserveBlankLines('A\n\n  \nB'), 'A\n\n$nbsp\n\nB');
      expect(preserveBlankLines('A\n\n\t\nB'), 'A\n\n$nbsp\n\nB');
    });

    test('trailing blank lines produce spacers', () {
      // 'A\n\n\n' splits to ['A', '', '', ''] — 3 blanks → 2 spacers.
      final result = preserveBlankLines('A\n\n\n');
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 2);
    });

    test('leading blank lines produce spacers', () {
      // '\n\n\nA' splits to ['', '', '', 'A'] — 3 blanks → 2 spacers.
      final result = preserveBlankLines('\n\n\nA');
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 2);
    });

    test('does not modify single newlines (soft line breaks)', () {
      expect(preserveBlankLines('A\nB\nC'), 'A\nB\nC');
    });

    test('CRLF blank lines are treated as blank', () {
      expect(preserveBlankLines('A\r\n\r\n\r\nB'), 'A\r\n\n$nbsp\n\nB');
    });

    test('indented fences after normalization are still detected', () {
      // After _normalizeDiscordLikeIndentation strips 4-space indent,
      // fences are at column 0. preserveBlankLines must detect them.
      const input = '```\ncode\n\n\nmore\n```';
      expect(preserveBlankLines(input), input);
    });
  });

  group('MarkdownText blank line rendering', () {
    testWidgets('extra blank lines produce more block spacers than normal', (
      tester,
    ) async {
      // With extra blank lines — should have more spacer widgets.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'First\n\n\nSecond')),
        ),
      );
      final withBlanks = _countBlockSpacers(tester);

      // Without extra blank lines — normal paragraph break.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'First\n\nSecond')),
        ),
      );
      final withoutBlanks = _countBlockSpacers(tester);

      expect(
        withBlanks,
        greaterThan(withoutBlanks),
        reason: 'extra blank line should produce additional block spacing',
      );
    });

    testWidgets('more blank lines produce proportionally more spacers', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\n\nB')),
        ),
      );
      final oneExtra = _countBlockSpacers(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\n\n\nB')),
        ),
      );
      final twoExtra = _countBlockSpacers(tester);

      expect(twoExtra, greaterThan(oneExtra));
    });

    testWidgets('more blank lines produce a larger visual gap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\n\nB')),
        ),
      );
      final twoBlankLineGap = _verticalGapBetween(tester, 'A', 'B');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\n\n\nB')),
        ),
      );
      final threeBlankLineGap = _verticalGapBetween(tester, 'A', 'B');

      expect(threeBlankLineGap, greaterThan(twoBlankLineGap));
    });

    testWidgets('single blank line (normal paragraph) has baseline spacers', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\nB')),
        ),
      );

      // Normal paragraph break still renders — just no EXTRA spacers.
      final rendered = _allRenderedText(tester);
      expect(rendered, contains('A'));
      expect(rendered, contains('B'));
    });

    testWidgets('blank lines in fenced code blocks are not spacer-ized', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '```\nline1\n\n\nline2\n```'),
          ),
        ),
      );

      expect(_allRenderedText(tester).where((t) => t == nbsp), isEmpty);
    });

    testWidgets('indented fences from SP bios do not get spacers injected', (
      tester,
    ) async {
      // Discord/SP bios use 4-space indented fences. The indentation
      // normalizer strips the indent before blank-line preservation runs,
      // so the fence is detected and blank lines inside are left alone.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data: '    ```\n    code\n\n\n    more\n    ```',
            ),
          ),
        ),
      );

      expect(_allRenderedText(tester).where((t) => t == nbsp), isEmpty);
    });

    testWidgets('soft line breaks still work with blank line preservation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'line one\nline two')),
        ),
      );

      expect(_allRenderedText(tester), contains('line one\nline two'));
    });

    testWidgets('markdown formatting survives blank line insertion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '**bold**\n\n\n*italic*'),
          ),
        ),
      );

      final texts = _allRenderedText(tester);
      expect(texts, contains('bold'));
      expect(texts, contains('italic'));
      expect(texts.join(), isNot(contains('**')));
      expect(texts.join(), isNot(contains('*italic*')));
    });

    testWidgets('headings separated by blank lines render correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '# Title\n\n\nContent here'),
          ),
        ),
      );

      final texts = _allRenderedText(tester);
      expect(texts, contains('Title'));
      expect(texts, contains('Content here'));
    });

    testWidgets('list items separated by blank lines stay as list', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '- item one\n\n\n- item two'),
          ),
        ),
      );

      final texts = _allRenderedText(tester);
      expect(texts, contains('item one'));
      expect(texts, contains('item two'));
    });
  });
}

/// Extracts text from both Text and RichText widgets.
List<String> _allRenderedText(WidgetTester tester) {
  final result = <String>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final content = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (content.isNotEmpty) result.add(content);
  }
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final content = rt.text.toPlainText();
    if (content.isNotEmpty) result.add(content);
  }
  return result;
}

/// Counts SizedBox widgets used as block spacers by flutter_markdown.
/// Each block element pair gets a SizedBox(height: blockSpacing) between them.
int _countBlockSpacers(WidgetTester tester) {
  return tester
      .widgetList<SizedBox>(find.byType(SizedBox))
      .where((sb) => sb.height != null && sb.height! > 0 && sb.width == null)
      .length;
}

double _verticalGapBetween(WidgetTester tester, String upper, String lower) {
  final upperFinder = find.text(upper);
  final lowerFinder = find.text(lower);
  expect(upperFinder, findsOneWidget);
  expect(lowerFinder, findsOneWidget);
  return tester.getTopLeft(lowerFinder).dy -
      tester.getBottomLeft(upperFinder).dy;
}
