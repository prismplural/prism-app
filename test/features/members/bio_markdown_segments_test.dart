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

    test('unknown spec → fenced but default styling', () {
      const md = ':::wat\n| a |\n:::';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(1));
      expect(segs.first.isDefault, isTrue);
      expect(segs.first.content.trim(), '| a |');
    });

    test('unclosed fence runs to end of text', () {
      const md = 'intro\n:::plain\n| a |';
      final segs = parseStyledSegments(md);
      expect(segs, hasLength(2));
      expect(segs[0].content.trim(), 'intro');
      expect(segs[1].borderless, isTrue);
      expect(segs[1].content.trim(), '| a |');
    });

    test('bare ::: outside a fence is dropped', () {
      const md = 'a\n:::\nb';
      final segs = parseStyledSegments(md);
      // The stray ::: produces no fence; content is the surrounding lines.
      expect(segs.map((s) => s.isDefault), everyElement(isTrue));
      final joined = segs.map((s) => s.content).join('\n');
      expect(joined.contains(':::'), isFalse);
      expect(joined.contains('a'), isTrue);
      expect(joined.contains('b'), isTrue);
    });
  });
}
