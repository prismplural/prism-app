import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/members/services/bio_markdown_segments.dart';
import 'package:prism_plurality/features/members/services/markdown_table_builder.dart';
import 'package:prism_plurality/features/members/services/markdown_table_parser.dart';

void main() {
  group('buildTableMarkdown — exact output', () {
    test('bare GFM, header on (2x2 => header + 2 body)', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 2,
        headerRow: true,
        showBorders: true,
      );
      expect(
        md,
        '|  |  |\n'
        '| --- | --- |\n'
        '|  |  |\n'
        '|  |  |',
      );
    });

    test('header off drops the dedicated header (2x2 => 2 rows total)', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 2,
        headerRow: false,
        showBorders: true,
      );
      expect(
        md,
        '|  |  |\n'
        '| --- | --- |\n'
        '|  |  |',
      );
    });

    test('borders off wraps in :::plain', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 1,
        headerRow: true,
        showBorders: false,
      );
      expect(
        md,
        ':::plain\n'
        '|  |  |\n'
        '| --- | --- |\n'
        '|  |  |\n'
        ':::',
      );
    });

    test('border color wraps in :::#RRGGBB (uppercased, hash added)', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 1,
        headerRow: true,
        showBorders: true,
        borderColorHex: 'ff8800',
      );
      expect(md.startsWith(':::#FF8800\n'), isTrue);
      expect(md.endsWith('\n:::'), isTrue);
    });

    test('border color ignored when borders are off (=> :::plain)', () {
      final md = buildTableMarkdown(
        columns: 1,
        rows: 1,
        headerRow: true,
        showBorders: false,
        borderColorHex: '#FF8800',
      );
      expect(md.startsWith(':::plain\n'), isTrue);
    });

    test('clamps columns and rows to a minimum of 1', () {
      final md = buildTableMarkdown(
        columns: 0,
        rows: 0,
        headerRow: true,
        showBorders: true,
      );
      // 1 col, 1 body row, header on => header + 1 body
      expect(md, '|  |\n| --- |\n|  |');
    });
  });

  group('buildTableMarkdown — round-trips through the renderer parsers', () {
    test('bare GFM parses to one empty table with the right dimensions', () {
      final md = buildTableMarkdown(
        columns: 3,
        rows: 2,
        headerRow: true,
        showBorders: true,
      );
      final blocks = splitMarkdownBlocks(md);
      expect(blocks.length, 1);
      expect(blocks.single.isTable, isTrue);
      final table = blocks.single.table!;
      expect(table.rows.length, 3); // header + 2 body
      expect(
        table.rows.every((r) => r.length == 3 && r.every((c) => c.isEmpty)),
        isTrue,
      );
    });

    test(':::plain round-trips to a borderless segment containing one table', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 2,
        headerRow: true,
        showBorders: false,
      );
      final segments = parseStyledSegments(md);
      expect(segments.length, 1);
      expect(segments.single.borderless, isTrue);
      final blocks = splitMarkdownBlocks(segments.single.content);
      expect(blocks.single.isTable, isTrue);
    });

    test(':::#hex round-trips to a colored segment containing one table', () {
      final md = buildTableMarkdown(
        columns: 2,
        rows: 1,
        headerRow: true,
        showBorders: true,
        borderColorHex: '#FF8800',
      );
      final segments = parseStyledSegments(md);
      expect(segments.length, 1);
      expect(segments.single.borderColor, const Color(0xFFFF8800));
      expect(segments.single.borderless, isFalse);
      final blocks = splitMarkdownBlocks(segments.single.content);
      expect(blocks.single.isTable, isTrue);
    });
  });
}
