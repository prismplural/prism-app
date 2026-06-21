import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

Future<Table> _pumpTable(
  WidgetTester tester,
  String data, {
  List<Member> members = const [],
}) async {
  await _pumpPrismMarkdown(tester, data, members: members);
  await tester.pumpAndSettle();
  return tester.widget<Table>(find.byType(Table));
}

Future<void> _pumpPrismMarkdown(
  WidgetTester tester,
  String data, {
  List<Member> members = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageLibraryProvider.overrideWith(
          (ref) => Stream<List<MediaAttachment>>.value(const []),
        ),
        activeMemberListProvider.overrideWithValue(AsyncValue.data(members)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 500, child: PrismMarkdownText(data: data)),
        ),
      ),
    ),
  );
}

void main() {
  group('PrismMarkdownText alignment fences', () {
    testWidgets('center fence strips markers and aligns rendered markdown', (
      tester,
    ) async {
      await _pumpPrismMarkdown(
        tester,
        ':::center\n# Hello\n\nCentered **body**\n\n-# quiet aside\n:::',
      );
      await tester.pumpAndSettle();

      final rendered = _allRenderedText(tester).join('\n');
      expect(rendered, contains('Hello'));
      expect(rendered, contains('Centered body'));
      expect(rendered, contains('quiet aside'));
      expect(rendered, isNot(contains(':::')));

      expect(
        _richTextContaining(tester, 'Centered body').textAlign,
        TextAlign.center,
      );
      expect(
        _textContaining(tester, 'quiet aside').textAlign,
        TextAlign.center,
      );
    });

    testWidgets('justify fence applies justify alignment to formatted prose', (
      tester,
    ) async {
      await _pumpPrismMarkdown(
        tester,
        ':::justify\nJustified **body** text with enough words to wrap.\n:::',
      );
      await tester.pumpAndSettle();

      expect(
        _richTextContaining(tester, 'Justified body text').textAlign,
        TextAlign.justify,
      );
    });

    testWidgets(
      'default prose around an aligned fence keeps default alignment',
      (tester) async {
        await _pumpPrismMarkdown(
          tester,
          'Before **default**\n\n'
          ':::center\n'
          'Inside **centered**\n'
          ':::\n\n'
          'After **default**',
        );
        await tester.pumpAndSettle();

        _expectRenderedAlign(tester, 'Before default', TextAlign.start);
        _expectRenderedAlign(tester, 'Inside centered', TextAlign.center);
        _expectRenderedAlign(tester, 'After default', TextAlign.start);
      },
    );

    testWidgets('alignment fences apply to blockquote content', (tester) async {
      await _pumpPrismMarkdown(tester, ':::right\n> Quoted **body**\n:::');
      await tester.pumpAndSettle();

      _expectRenderedAlign(tester, 'Quoted body', TextAlign.end);
    });

    testWidgets('alignment fence provides table cell fallback alignment', (
      tester,
    ) async {
      await _pumpPrismMarkdown(
        tester,
        ':::center\n'
        '| Alpha | Beta |\n'
        '| - | - |\n'
        '| Fallback alpha | **Fallback beta** |\n'
        ':::',
      );
      await tester.pumpAndSettle();

      _expectRenderedAlign(tester, 'Fallback alpha', TextAlign.center);
      _expectRenderedAlign(tester, 'Fallback beta', TextAlign.center);
    });

    testWidgets('GFM table alignment overrides alignment fence fallback', (
      tester,
    ) async {
      await _pumpPrismMarkdown(
        tester,
        ':::right\n'
        '| Left column | Center column | Fallback column |\n'
        '| :-- | :-: | - |\n'
        '| explicit left | explicit center | fallback right |\n'
        ':::',
      );
      await tester.pumpAndSettle();

      _expectRenderedAlign(tester, 'explicit left', TextAlign.start);
      _expectRenderedAlign(tester, 'explicit center', TextAlign.center);
      _expectRenderedAlign(tester, 'fallback right', TextAlign.end);
    });
  });

  group('PrismMarkdownTable column widths', () {
    testWidgets('image in left column hugs, text column flexes', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| pic | name |\n| - | - |\n| ![](sometag) | Alice |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('image in right column hugs, text column flexes', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| name | pic |\n| - | - |\n| Alice | ![](sometag) |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('header-only layout table: image col hugs (no body rows)', (
      tester,
    ) async {
      // The common image-beside-text shape: content lives in the header row
      // (a row + separator, no body). The image column must still hug.
      final table = await _pumpTable(
        tester,
        '| ![](sometag) | They/them. Caretaker. |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('header-only layout table: image on the right hugs', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| They/them. Caretaker. | ![](sometag) |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('text-only table → both columns flex', (tester) async {
      final table = await _pumpTable(tester, '| a | b |\n| - | - |\n| c | d |');
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('spoilers inside a one-column table render as spoiler pills', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| Project Alpha |\n'
        '| --- |\n'
        '| Status: ||internal draft|| |\n'
        '| Notes: ready for review |',
      );

      expect(table.columnWidths, hasLength(1));
      expect(find.byType(SpoilerPill), findsOneWidget);
      final pill = tester.widget<SpoilerPill>(find.byType(SpoilerPill));
      expect(pill.text, 'internal draft');
    });

    testWidgets('member mentions inside table cells resolve to display names', (
      tester,
    ) async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      final alice = Member(
        id: aliceId,
        name: 'Alice',
        createdAt: DateTime(2026),
      );

      final table = await _pumpTable(
        tester,
        '| Owner | Notes |\n'
        '| --- | --- |\n'
        '| @[$aliceId] | paired with @[$aliceId] |',
        members: [alice],
      );

      expect(table.children, hasLength(2));
      expect(find.textContaining('@Alice'), findsWidgets);
      expect(find.textContaining('@[$aliceId]'), findsNothing);
    });
  });
}

RichText _richTextContaining(WidgetTester tester, String value) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .singleWhere((widget) => widget.text.toPlainText().contains(value));
}

Text _textContaining(WidgetTester tester, String value) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .singleWhere(
        (widget) => (widget.data ?? widget.textSpan?.toPlainText() ?? '')
            .contains(value),
      );
}

void _expectRenderedAlign(
  WidgetTester tester,
  String value,
  TextAlign expected,
) {
  final alignments = _textAlignmentsContaining(tester, value);
  expect(alignments, isNotEmpty, reason: value);
  expect(
    alignments.any((actual) => _matchesAlignment(actual, expected)),
    isTrue,
    reason: '$value alignments were $alignments, expected $expected',
  );
}

List<TextAlign?> _textAlignmentsContaining(WidgetTester tester, String value) {
  final alignments = <TextAlign?>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final content = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (content.contains(value)) alignments.add(text.textAlign);
  }
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final content = richText.text.toPlainText();
    if (content.contains(value)) alignments.add(richText.textAlign);
  }
  return alignments;
}

bool _matchesAlignment(TextAlign? actual, TextAlign expected) {
  switch (expected) {
    case TextAlign.left:
    case TextAlign.start:
      return actual == TextAlign.left || actual == TextAlign.start;
    case TextAlign.right:
    case TextAlign.end:
      return actual == TextAlign.right || actual == TextAlign.end;
    case TextAlign.center:
      return actual == TextAlign.center;
    case TextAlign.justify:
      return actual == TextAlign.justify;
  }
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
