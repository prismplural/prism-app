import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_markdown_segments.dart';

void main() {
  group('parseHexColor', () {
    test('parses #RRGGBB (opaque)', () {
      expect(parseHexColor('#FF8800'), const Color(0xFFFF8800));
    });
    test('parses #RGB shorthand', () {
      expect(parseHexColor('#F80'), const Color(0xFFFF8800));
    });
    test('parses #AARRGGBB', () {
      expect(parseHexColor('#80FF8800'), const Color(0x80FF8800));
    });
    test('returns null for invalid', () {
      expect(parseHexColor('plain'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor('#FF88'), isNull);
      expect(parseHexColor('FF8800'), isNull); // missing #
    });
  });

  group('parseStyledSegments', () {
    test('no fences → single default segment with full content', () {
      const md = 'just text\n\nmore text';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.content, md);
      expect(segs.first.isDefault, isTrue);
    });

    test('plain fence → borderless segment, markers stripped', () {
      const md = ':::plain\n| a | b |\n| - | - |\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.borderless, isTrue);
      expect(segs.first.borderColor, isNull);
      expect(segs.first.content, '| a | b |\n| - | - |');
    });

    test('hex fence → colored border segment', () {
      const md = ':::#FF8800\n| a | b |\n| - | - |\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.borderless, isFalse);
      expect(segs.first.borderColor, const Color(0xFFFF8800));
    });

    test('alignment fences strip markers and preserve content', () {
      const md = ':::center\n# Title\n\nCentered **body**\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.textAlign, TextAlign.center);
      expect(segs.first.borderless, isFalse);
      expect(segs.first.borderColor, isNull);
      expect(segs.first.content, '# Title\n\nCentered **body**');
    });

    test('all alignment directives are recognized case-insensitively', () {
      final alignments = {
        'left': TextAlign.left,
        'CENTER': TextAlign.center,
        'Right': TextAlign.right,
        'justify': TextAlign.justify,
      };

      for (final entry in alignments.entries) {
        final segs = parseStyledSegments(':::${entry.key}\ntext\n:::');
        expect(segs.single.textAlign, entry.value, reason: entry.key);
        expect(segs.single.content, 'text', reason: entry.key);
      }
    });

    test('directives inside markdown code fences stay literal', () {
      const md =
          '```\n'
          ':::center\n'
          'literal\n'
          ':::\n'
          '```';

      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, md);
    });

    test('bare ::: inside fenced code does not close an alignment fence', () {
      const md =
          ':::center\n'
          '```\n'
          ':::\n'
          '```\n'
          'still centered\n'
          ':::';

      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.textAlign, TextAlign.center);
      expect(segs.first.content, '```\n:::\n```\nstill centered');
    });

    test('prose + fenced + prose → three ordered segments', () {
      const md = 'intro\n\n:::plain\n| a | b |\n:::\n\noutro';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(3));
      expect(segs[0].isDefault, isTrue);
      expect(segs[0].content.trim(), 'intro');
      expect(segs[1].borderless, isTrue);
      expect(segs[1].content.trim(), '| a | b |');
      expect(segs[2].isDefault, isTrue);
      expect(segs[2].content.trim(), 'outro');
    });

    test('unknown spec no longer opens a fence; markers kept as literal', () {
      const md = ':::wat\n| a |\n:::';
      final segs = parseStyledSegments(md);
      // `:::wat` is not a recognized directive, so nothing opens a fence and
      // the trailing bare ::: is a stray marker outside any fence — both are
      // preserved verbatim alongside the table row.
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, ':::wat\n| a |\n:::');
    });

    test('unclosed fence runs to end of text', () {
      const md = 'intro\n:::plain\n| a |';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(2));
      expect(segs[0].content.trim(), 'intro');
      expect(segs[1].borderless, isTrue);
      expect(segs[1].content.trim(), '| a |');
    });

    test('bare ::: outside a fence is preserved as literal content', () {
      const md = 'a\n:::\nb';
      final segs = parseStyledSegments(md);
      // The stray ::: opens no fence and is kept verbatim in the content.
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, 'a\n:::\nb');
    });

    test('unrecognized directive is preserved literally (no fence)', () {
      const md = ':::notadirective';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, contains(':::notadirective'));
      expect(segs.first.content, ':::notadirective');
    });

    test('invalid hex spec is preserved literally (no fence)', () {
      const md = ':::#zzz';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, ':::#zzz');
    });

    test('plain fence still yields a single borderless segment', () {
      const md = ':::plain\nhello\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.borderless, isTrue);
      expect(segs.first.borderColor, isNull);
      expect(segs.first.content, 'hello');
    });

    test('valid hex fence still yields its border color', () {
      const md = ':::#FF8800\nhello\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.borderColor, const Color(0xFFFF8800));
      expect(segs.first.borderless, isFalse);
      expect(segs.first.content, 'hello');
    });

    test('a valid open fence is still closed by a following bare :::', () {
      const md = ':::plain\ninside\n:::\noutside';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(2));
      expect(segs[0].borderless, isTrue);
      expect(segs[0].content, 'inside');
      expect(segs[1].isDefault, isTrue);
      expect(segs[1].content, 'outside');
    });

    test(
      'closing fence with trailing CR (CRLF line ending) closes the fence',
      () {
        const md = ':::plain\n| a | b |\n| - | - |\n:::\r\n\noutside';
        final segs = parseStyledSegments(md);
        expect(segs, hasLength(2));
        expect(segs[0].borderless, isTrue);
        expect(segs[1].isDefault, isTrue);
        expect(segs[1].content.trim(), 'outside');
      },
    );

    test(
      'opening fence with trailing CR (CRLF line ending) opens the fence',
      () {
        const md = ':::plain\r\n| a | b |\n| - | - |\n:::';
        final segs = parseStyledSegments(md);
        expect(segs, hasLength(1));
        expect(segs[0].borderless, isTrue);
      },
    );

    test('hex fence with trailing CR opens and closes correctly', () {
      const md = ':::#FF8800\r\n| a | b |\n| - | - |\n:::\r\n\noutside';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(2));
      expect(segs[0].borderColor?.toARGB32(), 0xFFFF8800);
      expect(segs[1].isDefault, isTrue);
    });

    test(
      'two consecutive fenced blocks → two separate borderless segments',
      () {
        const md = ':::plain\nA\n:::\n:::plain\nB\n:::';
        final segs = parseStyledSegments(md);
        expect(segs, hasLength(2));
        expect(segs[0].borderless, isTrue);
        expect(segs[0].content, 'A');
        expect(segs[1].borderless, isTrue);
        expect(segs[1].content, 'B');
      },
    );

    test('non-empty spec inside open fence is literal content', () {
      const md = ':::plain\n:::another\nsome text\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs[0].borderless, isTrue);
      expect(segs[0].content, ':::another\nsome text');
    });

    test('indented fence markers are recognized', () {
      const md = '  :::plain\ncontent\n  :::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs[0].borderless, isTrue);
      expect(segs[0].content, 'content');
    });

    test('completely empty fence falls back to a single default segment', () {
      // Nothing is flushed, so the segments-empty fallback returns the full markdown.
      const md = ':::plain\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content, md);
    });

    test(
      'fenced table followed by default table: second segment is default',
      () {
        const rows = '| a | b |\n| - | - |';
        const md = ':::plain\n$rows\n:::\n\n$rows';
        final segs = parseStyledSegments(md);
        expect(segs, hasLength(2));
        expect(segs[0].borderless, isTrue);
        expect(segs[1].isDefault, isTrue);
      },
    );
  });
}
