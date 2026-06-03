import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  group('MarkdownText conformance fixtures', () {
    // Fixture shapes are curated from CommonMark's conformance examples and
    // GitHub Flavored Markdown's extension sections, then asserted against
    // Prism's Flutter rendering instead of HTML output.
    testWidgets('block containers terminate before following paragraph', (
      tester,
    ) async {
      const cases = [
        _BlockBoundaryCase(
          name: 'blockquote',
          markdown: '> quoted',
          insideText: 'quoted',
        ),
        _BlockBoundaryCase(
          name: 'unordered list',
          markdown: '- item',
          insideText: 'item',
        ),
        _BlockBoundaryCase(
          name: 'ordered list',
          markdown: '1. item',
          insideText: 'item',
        ),
        _BlockBoundaryCase(
          name: 'task list',
          markdown: '- [ ] item',
          insideText: 'item',
        ),
      ];

      for (final fixture in cases) {
        await tester.pumpMarkdown(
          '# heading\n\n${fixture.markdown}\n\noutside paragraph',
        );

        final headingLeft = tester.leftOfText('heading');
        final insideLeft = tester.leftOfText(fixture.insideText);
        final outsideLeft = tester.leftOfText('outside paragraph');

        expect(
          outsideLeft,
          closeTo(headingLeft, 1),
          reason: '${fixture.name} should not capture the following paragraph',
        );
        expect(
          outsideLeft,
          lessThan(insideLeft),
          reason: '${fixture.name} content should remain visually nested',
        );
      }
    });

    testWidgets('loose list items separated by blank lines stay in the list', (
      tester,
    ) async {
      await tester.pumpMarkdown('- alpha\n\n- bravo\n\n- charlie');

      expect(tester.renderedText, contains('alpha'));
      expect(tester.renderedText, contains('bravo'));
      expect(tester.renderedText, contains('charlie'));

      final alphaLeft = tester.leftOfText('alpha');
      final bravoLeft = tester.leftOfText('bravo');
      final charlieLeft = tester.leftOfText('charlie');

      expect(bravoLeft, closeTo(alphaLeft, 1));
      expect(charlieLeft, closeTo(alphaLeft, 1));
    });

    testWidgets('GFM task list markers become semantic checkboxes', (
      tester,
    ) async {
      await tester.pumpMarkdown('- [ ] todo\n- [x] done\n- [X] loud done');

      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsNWidgets(2));
      expect(tester.renderedText, contains('todo'));
      expect(tester.renderedText, contains('done'));
      expect(tester.renderedText, contains('loud done'));
      expect(tester.renderedText, isNot(contains('[ ]')));
      expect(tester.renderedText, isNot(contains('[x]')));
      expect(tester.renderedText, isNot(contains('[X]')));
    });

    testWidgets('GFM table cells render without pipe syntax', (tester) async {
      await tester.pumpMarkdown(
        '| Animal | Sound |\n'
        '| --- | --- |\n'
        '| cat | meow |\n'
        '| dog | woof |',
      );

      final text = tester.renderedText;
      expect(text, contains('Animal'));
      expect(text, contains('Sound'));
      expect(text, contains('cat'));
      expect(text, contains('meow'));
      expect(text, contains('dog'));
      expect(text, contains('woof'));
      expect(text, isNot(contains('|')));
    });

    testWidgets('inline constructs render as formatted text, not source', (
      tester,
    ) async {
      await tester.pumpMarkdown(
        r'Escaped \* marker, `literal **code**`, **bold**, *italic*, '
        '~~gone~~, [docs](https://example.com), &amp; entity',
      );

      final text = tester.renderedText;
      expect(text, contains('Escaped * marker'));
      expect(text, contains('literal **code**'));
      expect(text, contains('bold'));
      expect(text, contains('italic'));
      expect(text, contains('gone'));
      expect(text, contains('docs'));
      expect(text, contains('& entity'));
      expect(text, isNot(contains(r'\*')));
      expect(text, isNot(contains('~~')));
      expect(text, isNot(contains('&amp;')));
    });

    testWidgets('raw HTML stays literal instead of rendering as markup', (
      tester,
    ) async {
      await tester.pumpMarkdown('before <script>alert(1)</script> after');

      final text = tester.renderedText;
      expect(text, contains('before <script>alert(1)</script> after'));
    });
  });
}

class _BlockBoundaryCase {
  const _BlockBoundaryCase({
    required this.name,
    required this.markdown,
    required this.insideText,
  });

  final String name;
  final String markdown;
  final String insideText;
}

extension _MarkdownPump on WidgetTester {
  Future<void> pumpMarkdown(String data) async {
    await pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 500, child: MarkdownText(data: data)),
          ),
        ),
      ),
    );
  }

  String get renderedText => _allRenderedText(this).join('\n');

  double leftOfText(String text) => getTopLeft(find.text(text)).dx;
}

List<String> _allRenderedText(WidgetTester tester) {
  final result = <String>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final content = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (content.isNotEmpty) result.add(content);
  }
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final content = richText.text.toPlainText();
    if (content.isNotEmpty) result.add(content);
  }
  return result;
}
