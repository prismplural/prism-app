import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/markdown_utils.dart';

void main() {
  const uuid = '11111111-2222-3333-4444-555555555555';

  Member makeMember(String name) => Member(
        id: uuid,
        name: name,
        createdAt: DateTime(2026, 4, 16),
      );

  group('stripMarkdownMarkers — leaves mentions intact', () {
    test('strips bold but leaves @[uuid] token', () {
      expect(
        stripMarkdownMarkers('**hi** @[$uuid]'),
        'hi @[$uuid]',
      );
    });

    test('strips leading `-#` but leaves mention token on the same line', () {
      expect(
        stripMarkdownMarkers('-# noted @[$uuid]'),
        'noted @[$uuid]',
      );
    });

    test('strips link label, leaves mention token', () {
      expect(
        stripMarkdownMarkers('[click](https://x) for @[$uuid]'),
        'click for @[$uuid]',
      );
    });

    test('idempotent on text with no markers', () {
      expect(stripMarkdownMarkers('plain text'), 'plain text');
    });
  });

  group('stripMarkdownMarkers — flanking rules', () {
    test('does not strip intra-word underscores', () {
      // `snake_case_value` is a literal identifier, not emphasis.
      expect(
        stripMarkdownMarkers('snake_case_value'),
        'snake_case_value',
      );
    });

    test('does not strip asterisks with whitespace neighbors', () {
      // Arithmetic / loose asterisks should pass through untouched.
      expect(stripMarkdownMarkers('2 * 3 * 4'), '2 * 3 * 4');
      expect(stripMarkdownMarkers('* leading'), '* leading');
      expect(stripMarkdownMarkers('trailing *'), 'trailing *');
    });

    test('still strips well-formed emphasis', () {
      expect(stripMarkdownMarkers('*italic*'), 'italic');
      expect(stripMarkdownMarkers('_italic_'), 'italic');
      expect(
        stripMarkdownMarkers('hi *world* bye'),
        'hi world bye',
      );
      expect(
        stripMarkdownMarkers('hi _world_ bye'),
        'hi world bye',
      );
    });

    test('handles bold + emphasis combos without over-stripping', () {
      expect(stripMarkdownMarkers('**bold**'), 'bold');
      expect(
        stripMarkdownMarkers('**bold with _inner_ italic**'),
        'bold with inner italic',
      );
    });

    test('does not strip intra-word underscores in non-Latin scripts', () {
      // Dart's `\w` is ASCII-only — Cyrillic, Greek, CJK letters wouldn't
      // count as word chars under a naive flanking rule. Unicode-aware
      // `\p{L}\p{N}_` keeps these identifiers literal.
      expect(
        stripMarkdownMarkers('привет_мир_знач'),
        'привет_мир_знач',
      );
      expect(
        stripMarkdownMarkers('日本語_テスト_値'),
        '日本語_テスト_値',
      );
      expect(
        stripMarkdownMarkers('Ω_λ_φ'),
        'Ω_λ_φ',
      );
    });

    test('strips well-formed underscore emphasis in non-Latin scripts', () {
      // When `_` IS true emphasis (whitespace flanking), it strips even
      // around non-Latin text.
      expect(
        stripMarkdownMarkers('hi _мир_ bye'),
        'hi мир bye',
      );
    });
  });

  group('stripMarkdownMarkers — mention token protection', () {
    test('does not match `@[uuid](text)` as a link', () {
      // The `[uuid](text)` portion looks like a CommonMark link, but the
      // leading `@` marks it as a mention followed by parenthetical text
      // (e.g. pronouns). Stripping the brackets would break downstream
      // `replaceMentionsWithNames`.
      const memberId = '11111111-2222-3333-4444-555555555555';
      expect(
        stripMarkdownMarkers('@[$memberId](she/her)'),
        '@[$memberId](she/her)',
      );
    });

    test('still strips genuine links elsewhere in the same string', () {
      const memberId = '11111111-2222-3333-4444-555555555555';
      expect(
        stripMarkdownMarkers('hi @[$memberId] check [docs](https://x)'),
        'hi @[$memberId] check docs',
      );
    });
  });

  group('stripChatMarkdown — markdown stripping', () {
    test('strips bold', () {
      expect(stripChatMarkdown('**bold**', null), 'bold');
    });

    test('strips italic (star)', () {
      expect(stripChatMarkdown('*italic*', null), 'italic');
    });

    test('strips italic (underscore)', () {
      expect(stripChatMarkdown('_italic_', null), 'italic');
    });

    test('strips inline code', () {
      expect(stripChatMarkdown('`code`', null), 'code');
    });

    test('strips link, keeps label', () {
      expect(stripChatMarkdown('[link text](https://x)', null), 'link text');
    });

    test('strips small text marker at line start', () {
      expect(stripChatMarkdown('-# im smol', null), 'im smol');
      expect(stripChatMarkdown('hi\n-# im smol', null), 'hi\nim smol');
    });

    test('leaves small text marker inside a line', () {
      expect(stripChatMarkdown('hi -# im smol', null), 'hi -# im smol');
    });

    test('leaves unclosed bold as-is', () {
      expect(stripChatMarkdown('**un', null), '**un');
    });

    test('strips nested bold + italic', () {
      expect(
        stripChatMarkdown('**bold with _italic_ inside**', null),
        'bold with italic inside',
      );
    });

    test('empty string returns empty string', () {
      expect(stripChatMarkdown('', null), '');
    });
  });

  group('stripChatMarkdown — mention resolution', () {
    test('resolves mention from authorMap', () {
      final authorMap = {uuid: makeMember('Alice')};
      expect(
        stripChatMarkdown('hi @[$uuid]', authorMap),
        'hi @Alice',
      );
    });

    test('falls back to @Unknown for missing ID', () {
      expect(
        stripChatMarkdown('hi @[$uuid]', {}),
        'hi @Unknown',
      );
    });

    test('falls back to @Unknown when authorMap is null', () {
      expect(
        stripChatMarkdown('hi @[$uuid]', null),
        'hi @Unknown',
      );
    });

    test('complex: bold + mention + inline code', () {
      final authorMap = {uuid: makeMember('Alice')};
      expect(
        stripChatMarkdown('**Hey @[$uuid], check `this`**', authorMap),
        'Hey @Alice, check this',
      );
    });
  });
}
