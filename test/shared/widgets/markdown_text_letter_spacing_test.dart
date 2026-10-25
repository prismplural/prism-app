import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

const _prose =
    'Paragraph **bold** *italic* [link](https://example.invalid)'
    '\n\n- bullet\n\n1. numbered\n\n- [ ] task'
    '\n\n-# small [smalllink](https://example.invalid)';
const _words = [
  'Paragraph',
  'bold',
  'italic',
  'link',
  'bullet',
  'numbered',
  'task',
  'small',
  'smalllink',
];

void main() {
  testWidgets('theme letter spacing reaches every prose span', (tester) async {
    await _pump(tester, data: _prose, spacing: 2);
    for (final word in _words) {
      expect(_styleFor(tester, word).letterSpacing, 2, reason: word);
    }
  });

  testWidgets('explicit base spacing wins across prose and inline styles', (
    tester,
  ) async {
    await _pump(
      tester,
      data: _prose,
      spacing: 2,
      baseStyle: const TextStyle(letterSpacing: 3, fontSize: 16),
    );
    for (final word in _words) {
      expect(_styleFor(tester, word).letterSpacing, 3, reason: word);
    }
    expect(_styleFor(tester, 'Paragraph').fontSize, 16);
    expect(_styleFor(tester, 'small').fontSize, closeTo(16 * 0.85, 0.001));
    expect(_styleFor(tester, 'bold').fontWeight, FontWeight.bold);
    expect(_styleFor(tester, 'italic').fontStyle, FontStyle.italic);
    expect(_styleFor(tester, 'link').decoration, TextDecoration.underline);
  });

  testWidgets('partial base style inherits theme spacing', (tester) async {
    await _pump(
      tester,
      data: _prose,
      spacing: 2,
      baseStyle: const TextStyle(color: Colors.orange),
    );
    for (final word in _words) {
      expect(_styleFor(tester, word).letterSpacing, 2, reason: word);
    }
    expect(_styleFor(tester, 'Paragraph').color, Colors.orange);
  });

  testWidgets('sectioned blockquotes keep explicit spacing', (tester) async {
    await _pump(
      tester,
      data: 'before\n\n> quote **quotedbold**\n\nafter',
      spacing: 2,
      baseStyle: const TextStyle(letterSpacing: 3),
    );
    for (final word in ['before', 'quote', 'quotedbold', 'after']) {
      expect(_styleFor(tester, word).letterSpacing, 3, reason: word);
    }
  });

  testWidgets('default and explicit zero preserve zero prose spacing', (
    tester,
  ) async {
    for (final baseStyle in [null, const TextStyle(letterSpacing: 0)]) {
      await _pump(tester, data: _prose, baseStyle: baseStyle);
      for (final word in _words) {
        expect(_styleFor(tester, word).letterSpacing, 0, reason: word);
      }
    }
    await _pump(
      tester,
      data: _prose,
      spacing: 2,
      baseStyle: const TextStyle(letterSpacing: 0),
    );
    for (final word in _words) {
      expect(_styleFor(tester, word).letterSpacing, 0, reason: word);
    }
  });

  testWidgets('heading caps and code metrics survive spacing changes', (
    tester,
  ) async {
    const data =
        '# first\n\n## second\n\n### third\n\n#### fourth'
        '\n\n##### fifth\n\n###### sixth\n\n`inlinecode`\n\n```\nfencedcode\n```';
    await _pump(tester, data: data);
    final originalCode = _styleFor(tester, 'fencedcode');
    final originalInline = _styleFor(tester, 'inlinecode');
    await _pump(tester, data: data, spacing: 2);
    const caps = {
      'first': 24,
      'second': 21,
      'third': 18,
      'fourth': 16,
      'fifth': 15,
      'sixth': 14,
    };
    for (final entry in caps.entries) {
      expect(_styleFor(tester, entry.key).fontSize, entry.value);
    }
    for (final entry in {
      'fencedcode': originalCode,
      'inlinecode': originalInline,
    }.entries) {
      final style = _styleFor(tester, entry.key);
      expect(style.letterSpacing, 0);
      expect(style.fontFamily, entry.value.fontFamily);
      expect(style.fontFamily, 'monospace');
      expect(style.fontSize, entry.value.fontSize);
      expect(style.height, entry.value.height);
    }
  });

  testWidgets('spaced prose wraps at narrow width with system scaling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const data = 'Words wrap naturally across a narrow profile or note viewer.';
    await _pump(tester, data: data, spacing: 2);
    final normalHeight = tester.getSize(find.byType(MarkdownBody)).height;
    await _pump(tester, data: data, spacing: 2, scale: 1.8);
    expect(tester.takeException(), isNull);
    expect(_styleFor(tester, 'Words').letterSpacing, 2);
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere((text) => text.text.toPlainText().contains('Words'));
    expect(rich.textScaler.scale(10), closeTo(18, 0.001));
    expect(
      tester.getSize(find.byType(MarkdownBody)).width,
      lessThanOrEqualTo(280),
    );
    expect(
      tester.getSize(find.byType(MarkdownBody)).height,
      greaterThan(normalHeight),
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required String data,
  double spacing = 0,
  TextStyle? baseStyle,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.withLetterSpacing(AppTheme.dark(), spacing),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownText(data: data, baseStyle: baseStyle),
          ),
        ),
      ),
    ),
  );
}

TextStyle _styleFor(WidgetTester tester, String word) {
  TextStyle? visit(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return null;
    final effective = inherited.merge(span.style);
    if ((span.text ?? '').contains(word)) return effective;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = visit(child, effective);
      if (found != null) return found;
    }
    return null;
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = visit(rich.text, const TextStyle());
    if (found != null) return found;
  }
  throw StateError('No rendered span contains "$word"');
}
