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

    test('single blank line becomes a spacer line', () {
      expect(preserveBlankLines('A\n\nB'), 'A\n$nbsp\nB');
    });

    test('two blank lines become two spacer lines', () {
      expect(preserveBlankLines('A\n\n\nB'), 'A\n$nbsp\n$nbsp\nB');
    });

    test('three blank lines become three spacer lines', () {
      expect(preserveBlankLines('A\n\n\n\nB'), 'A\n$nbsp\n$nbsp\n$nbsp\nB');
    });

    test('preserves long blank line runs', () {
      final input = 'A\n${'\n' * 20}B';
      final result = preserveBlankLines(input);
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 20);
    });

    test('multiple separate blank line runs', () {
      const input = 'A\n\n\nB\n\n\n\nC';
      final result = preserveBlankLines(input);
      expect(result, 'A\n$nbsp\n$nbsp\nB\n$nbsp\n$nbsp\n$nbsp\nC');
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
      expect(
        result,
        'before\n$nbsp\n$nbsp\n```\ncode\n\n\n```\n$nbsp\n$nbsp\nafter',
      );
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
      expect(preserveBlankLines('A\n\n  \nB'), 'A\n$nbsp\n$nbsp\nB');
      expect(preserveBlankLines('A\n\n\t\nB'), 'A\n$nbsp\n$nbsp\nB');
    });

    test('trailing blank lines produce spacers', () {
      final result = preserveBlankLines('A\n\n\n');
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 3);
    });

    test('leading blank lines produce spacers', () {
      final result = preserveBlankLines('\n\n\nA');
      final spacerCount = RegExp(RegExp.escape(nbsp)).allMatches(result).length;
      expect(spacerCount, 3);
    });

    test('does not modify single newlines (soft line breaks)', () {
      expect(preserveBlankLines('A\nB\nC'), 'A\nB\nC');
    });

    test('blank line after blockquote remains a real terminator', () {
      expect(preserveBlankLines('> warning\n\nnormal'), '> warning\n\nnormal');
    });

    test('blank line after unordered list remains a real terminator', () {
      expect(preserveBlankLines('- warning\n\nnormal'), '- warning\n\nnormal');
    });

    test('blank line after ordered list remains a real terminator', () {
      expect(
        preserveBlankLines('1. warning\n\nnormal'),
        '1. warning\n\nnormal',
      );
    });

    test(
      'extra blank lines after list keep only the first real terminator',
      () {
        expect(
          preserveBlankLines('- warning\n\n\nnormal'),
          '- warning\n\n$nbsp\nnormal',
        );
      },
    );

    test('CRLF blank lines are treated as blank', () {
      expect(preserveBlankLines('A\r\n\r\n\r\nB'), 'A\r\n$nbsp\n$nbsp\nB');
    });

    test('indented fences after normalization are still detected', () {
      // After _normalizeDiscordLikeIndentation strips 4-space indent,
      // fences are at column 0. preserveBlankLines must detect them.
      const input = '```\ncode\n\n\nmore\n```';
      expect(preserveBlankLines(input), input);
    });

    // An NBSP spacer above `---` makes it a setext heading instead of a divider,
    // so a real blank line must stay adjacent to the break.
    test('blank line before --- stays real (no setext heading)', () {
      expect(
        preserveBlankLines('**Day:**\n\n---\n\n**Next:**'),
        '**Day:**\n\n---\n\n**Next:**',
      );
    });

    test('*** and ___ thematic breaks keep a real blank terminator', () {
      expect(preserveBlankLines('A\n\n***\n\nB'), 'A\n\n***\n\nB');
      expect(preserveBlankLines('A\n\n___\n\nB'), 'A\n\n___\n\nB');
    });

    test('a spacer never sits directly above a thematic break', () {
      final lines = preserveBlankLines('A\n\n\n\n---\n\n\n\nB').split('\n');
      final hrIndex = lines.indexOf('---');
      expect(hrIndex, greaterThan(0));
      expect(lines[hrIndex - 1], '', reason: 'real blank line above the break');
    });

    test('extra blanks before a break become spacers above the terminator', () {
      // 3 blanks -> 2 NBSP spacers, then 1 real blank adjacent to ---.
      expect(preserveBlankLines('A\n\n\n\n---'), 'A\n$nbsp\n$nbsp\n\n---');
    });

    test('extra blanks after a break become spacers below the terminator', () {
      expect(preserveBlankLines('---\n\n\n\nB'), '---\n\n$nbsp\n$nbsp\nB');
    });

    test('divider exception does not change ordinary paragraph spacing', () {
      expect(preserveBlankLines('A\n\n\nB'), 'A\n$nbsp\n$nbsp\nB');
    });

    // Break detection must match the parser grammar (CRLF, indentation), not
    // just a column-0 `---`, or these silently regress to the heading bug.
    test('CRLF thematic break keeps a real blank terminator', () {
      expect(preserveBlankLines('A\r\n\r\n---\r\nB'), 'A\r\n\r\n---\r\nB');
    });

    test('up-to-3-space indented break is detected', () {
      expect(preserveBlankLines('A\n\n   ---\nB'), 'A\n\n   ---\nB');
    });

    test('spaced thematic breaks (- - -, * * *) are detected', () {
      expect(preserveBlankLines('A\n\n- - -\nB'), 'A\n\n- - -\nB');
      expect(preserveBlankLines('A\n\n* * *\nB'), 'A\n\n* * *\nB');
    });

    test('setext underline (=== / lone -) gets no NBSP directly above it', () {
      expect(preserveBlankLines('A\n\n===\nB'), 'A\n\n===\nB');
      expect(preserveBlankLines('A\n\n-\nB'), 'A\n\n-\nB');
    });
  });

  group('MarkdownText blank line rendering', () {
    testWidgets('extra blank lines render taller than a single blank line', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 24, height: 1.25);

      final extraHeight = await _renderedHeightFor(
        tester,
        const MarkdownText(data: 'First\n\n\nSecond', baseStyle: style),
      );
      final singleHeight = await _renderedHeightFor(
        tester,
        const MarkdownText(data: 'First\n\nSecond', baseStyle: style),
      );

      expect(extraHeight, greaterThan(singleHeight));
    });

    testWidgets('more blank lines produce a larger rendered height', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 24, height: 1.25);

      final twoBlankLineHeight = await _renderedHeightFor(
        tester,
        const MarkdownText(data: 'A\n\n\nB', baseStyle: style),
      );
      final threeBlankLineHeight = await _renderedHeightFor(
        tester,
        const MarkdownText(data: 'A\n\n\n\nB', baseStyle: style),
      );

      expect(threeBlankLineHeight, greaterThan(twoBlankLineHeight));
    });

    testWidgets('blank line runs match plain text height', (tester) async {
      const data =
          'the line breaks,\n\n\nwhich you have requested\n\n\n\n'
          'are now functional\n\nseperation, anxiety, abounds.';
      const style = TextStyle(fontSize: 24, height: 1.25);

      final plainHeight = await _renderedHeightFor(
        tester,
        const Text(data, style: style),
      );
      final markdownHeight = await _renderedHeightFor(
        tester,
        const MarkdownText(data: data, baseStyle: style),
      );

      expect(markdownHeight, closeTo(plainHeight, 1));
    });

    testWidgets('single blank line renders a spacer line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: 'A\n\nB')),
        ),
      );

      final rendered = _allRenderedText(tester).join('\n');
      expect(rendered, contains('A'));
      expect(rendered, contains('B'));
      expect(rendered, contains(nbsp));
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

      expect(_allRenderedText(tester).join('\n'), isNot(contains(nbsp)));
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

      expect(_allRenderedText(tester).join('\n'), isNot(contains(nbsp)));
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

      final text = _allRenderedText(tester).join('\n');
      expect(text, contains('bold'));
      expect(text, contains('italic'));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('*italic*')));
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

      final text = _allRenderedText(tester).join('\n');
      expect(text, contains('Title'));
      expect(text, contains('Content here'));
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

      final text = _allRenderedText(tester).join('\n');
      expect(text, contains('item one'));
      expect(text, contains('item two'));
    });

    testWidgets('--- renders a divider, not a setext heading title', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '**Day:**\n\n---\n\n**Self-Harm:**'),
          ),
        ),
      );

      // The horizontal rule renders as a Container with a border decoration.
      // No other block in this input is decorated, so its presence proves the
      // `---` parsed as a divider — not a setext heading underline, which would
      // emit no <hr> and promote "Day:" to an <h2>.
      final hrContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MarkdownText),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.decoration != null);
      expect(
        hrContainers,
        isNotEmpty,
        reason: '--- should render a horizontal divider',
      );

      final text = _allRenderedText(tester).join('\n');
      expect(text, contains('Day:'));
      expect(text, contains('Self-Harm:'));
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

Future<double> _renderedHeightFor(WidgetTester tester, Widget child) async {
  final key = UniqueKey();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(key: key, width: 500, child: child),
        ),
      ),
    ),
  );

  return tester.getSize(find.byKey(key)).height;
}
