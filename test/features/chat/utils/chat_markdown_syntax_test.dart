import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

void main() {
  group('MentionSyntax', () {
    test('parses a valid mention and emits a mention element', () {
      const input = 'hi @[11111111-2222-3333-4444-555555555555]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes.whereType<md.Element>().where((e) => e.tag == 'mention').toList();
      expect(mentions, hasLength(1));
      expect(mentions.first.attributes['id'], '11111111-2222-3333-4444-555555555555');
    });

    test('does not emit mention for malformed uuid', () {
      const input = '@[not-a-uuid]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes.whereType<md.Element>().where((e) => e.tag == 'mention').toList();
      expect(mentions, isEmpty);
    });

    test('does not emit mention for empty brackets', () {
      const input = '@[]';
      final nodes = md.Document(
        inlineSyntaxes: [MentionSyntax()],
        encodeHtml: false,
      ).parseInline(input);
      final mentions = nodes.whereType<md.Element>().where((e) => e.tag == 'mention').toList();
      expect(mentions, isEmpty);
    });
  });

  group('escapeLeadingHeadings', () {
    test('escapes single hash heading', () {
      expect(escapeLeadingHeadings('# foo'), '\\# foo');
    });

    test('escapes double hash heading', () {
      expect(escapeLeadingHeadings('## bar'), '\\## bar');
    });

    test('escapes six-level heading', () {
      expect(escapeLeadingHeadings('###### deep'), '\\###### deep');
    });

    test('does not escape indented hash', () {
      expect(escapeLeadingHeadings('  # foo'), '  # foo');
    });

    test('does not escape hash with no space', () {
      expect(escapeLeadingHeadings('#foo'), '#foo');
    });

    test('escapes multiple heading lines in multi-line string', () {
      expect(escapeLeadingHeadings('# a\n## b\ntext'), '\\# a\n\\## b\ntext');
    });

    test('returns empty string unchanged', () {
      expect(escapeLeadingHeadings(''), '');
    });

    test('returns plain text unchanged', () {
      expect(escapeLeadingHeadings('no hash here'), 'no hash here');
    });
  });

  group('hasMarkdownChars', () {
    test('returns false for plain text', () {
      expect(hasMarkdownChars('hello world'), isFalse);
    });

    test('returns true when bold markers present', () {
      expect(hasMarkdownChars('hello **world**'), isTrue);
    });

    test('returns true when italic underscore present', () {
      expect(hasMarkdownChars('hello _world_'), isTrue);
    });

    test('returns true when mention token present', () {
      expect(hasMarkdownChars('hello @[uuid]'), isTrue);
    });

    test("returns false for apostrophe in don't", () {
      expect(hasMarkdownChars("don't"), isFalse);
    });

    test('returns false for empty string', () {
      expect(hasMarkdownChars(''), isFalse);
    });

    test('returns true for inline code backtick', () {
      expect(hasMarkdownChars('`code`'), isTrue);
    });

    test('returns true for link bracket', () {
      expect(hasMarkdownChars('link [text](url)'), isTrue);
    });
  });
}
