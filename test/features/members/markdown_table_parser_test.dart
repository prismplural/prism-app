import 'package:flutter/material.dart' show TextAlign;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/markdown_table_parser.dart';

void main() {
  group('splitMarkdownBlocks', () {
    test('simple 2-col table with outer pipes', () {
      final blocks = splitMarkdownBlocks('| a | b |\n| - | - |\n| c | d |');
      expect(blocks, hasLength(1));
      expect(blocks.first.isTable, isTrue);
      final t = blocks.first.table!;
      expect(t.rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('table without outer pipes', () {
      final blocks = splitMarkdownBlocks('a | b\n- | -\nc | d');
      expect(blocks, hasLength(1));
      final t = blocks.first.table!;
      expect(t.rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('alignment row parsing', () {
      final blocks = splitMarkdownBlocks(
        '| a | b | c | d |\n| :-- | :-: | --: | - |',
      );
      final t = blocks.first.table!;
      expect(t.aligns, [
        TextAlign.left,
        TextAlign.center,
        TextAlign.right,
        null,
      ]);
    });

    test('escaped pipe in a cell is not a column separator', () {
      final blocks = splitMarkdownBlocks(
        r'| a \| b | c |'
        '\n| - | - |\n'
        r'| x | y |',
      );
      final t = blocks.first.table!;
      expect(t.rows[0], [r'a \| b', 'c']);
      expect(t.rows[1], ['x', 'y']);
    });

    test('table sandwiched between prose → 3 blocks in order', () {
      const md =
          'intro line\n'
          '| a | b |\n| - | - |\n| c | d |\n'
          'outro line';
      final blocks = splitMarkdownBlocks(md);
      expect(blocks, hasLength(3));
      expect(blocks[0].text, 'intro line');
      expect(blocks[1].isTable, isTrue);
      expect(blocks[2].text, 'outro line');
    });

    test('ragged rows are tolerated', () {
      final blocks = splitMarkdownBlocks('| a | b | c |\n| - | - | - |\n| x |');
      final t = blocks.first.table!;
      expect(t.rows[0], ['a', 'b', 'c']);
      expect(t.rows[1], ['x']);
    });

    test('spoiler delimiters inside cells do not create columns', () {
      const source =
          '| Project Alpha |\n'
          '| --- |\n'
          '| Status: ||internal draft|| |\n'
          '| Notes: ready for review |';
      final blocks = splitMarkdownBlocks(source);
      final t = blocks.single.table!;
      expect(t.rows, [
        ['Project Alpha'],
        ['Status: ||internal draft||'],
        ['Notes: ready for review'],
      ]);
    });

    test(
      'spoiler delimiters before a real separator stay in the same cell',
      () {
        const source =
            '| item | note |\n'
            '| - | - |\n'
            '| roadmap ||draft|| | publish after review |';
        final blocks = splitMarkdownBlocks(source);
        final t = blocks.single.table!;
        expect(t.rows, [
          ['item', 'note'],
          ['roadmap ||draft||', 'publish after review'],
        ]);
      },
    );

    test('single `a | b` line with no separator stays text', () {
      final blocks = splitMarkdownBlocks('a | b');
      expect(blocks, hasLength(1));
      expect(blocks.first.isTable, isFalse);
      expect(blocks.first.text, 'a | b');
    });

    test('non-table content with pipes but no separator stays text', () {
      const md = 'a | b\nmore prose | here\nstill prose';
      final blocks = splitMarkdownBlocks(md);
      expect(blocks, hasLength(1));
      expect(blocks.first.text, md);
    });

    test('plain prose with no pipes is a single text block', () {
      const md = 'just text\n\nmore text';
      final blocks = splitMarkdownBlocks(md);
      expect(blocks, hasLength(1));
      expect(blocks.first.text, md);
    });

    test('table with no body rows (header + separator only)', () {
      final blocks = splitMarkdownBlocks('| a | b |\n| - | - |');
      expect(blocks, hasLength(1));
      final t = blocks.first.table!;
      expect(t.rows, [
        ['a', 'b'],
      ]);
    });

    test('blank line ends the table body', () {
      const md = '| a | b |\n| - | - |\n| c | d |\n\nafter';
      final blocks = splitMarkdownBlocks(md);
      // The blank line + "after" are consecutive prose lines → one text block.
      expect(blocks, hasLength(2));
      expect(blocks[0].isTable, isTrue);
      expect(blocks[1].text, '\nafter');
    });

    test('image cells retain raw markdown', () {
      final blocks = splitMarkdownBlocks(
        '| ![](sometag) | hello |\n| - | - |\n| ![](x#64) | text |',
      );
      final t = blocks.first.table!;
      expect(t.rows[1], ['![](x#64)', 'text']);
    });

    test('does not detect a table inside a ```-fenced code block', () {
      const source = '```\n| a | b |\n| - | - |\n| 1 | 2 |\n```';
      final blocks = splitMarkdownBlocks(source);
      expect(blocks.any((b) => b.isTable), isFalse);
      // The fenced content is preserved verbatim as a single prose block.
      expect(blocks, hasLength(1));
      expect(blocks.single.isTable, isFalse);
      expect(blocks.single.text, source);
    });

    test('detects a real table after a closed code fence', () {
      const source =
          '```\n| a | b |\n| - | - |\n```\n| x | y |\n| - | - |\n| 1 | 2 |';
      final blocks = splitMarkdownBlocks(source);
      final tables = blocks.where((b) => b.isTable).toList();
      expect(tables, hasLength(1));
      expect(tables.single.table!.rows, [
        ['x', 'y'],
        ['1', '2'],
      ]);
      // The fenced block stays prose.
      expect(blocks.first.isTable, isFalse);
      expect(blocks.first.text, '```\n| a | b |\n| - | - |\n```');
    });

    test('does not detect a table inside a ~~~-fenced code block', () {
      const source = '~~~\n| a | b |\n| - | - |\n| 1 | 2 |\n~~~';
      final blocks = splitMarkdownBlocks(source);
      expect(blocks.any((b) => b.isTable), isFalse);
      expect(blocks, hasLength(1));
      expect(blocks.single.text, source);
    });

    test('an unclosed ``` fence runs to EOF as prose', () {
      const source = '```\n| a | b |\n| - | - |\n| 1 | 2 |';
      final blocks = splitMarkdownBlocks(source);
      expect(blocks.any((b) => b.isTable), isFalse);
      expect(blocks, hasLength(1));
      expect(blocks.single.isTable, isFalse);
      expect(blocks.single.text, source);
    });
  });
}
