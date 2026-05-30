import 'dart:convert' show LineSplitter;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

void main() {
  group('redactSpoilers', () {
    test('returns empty string unchanged', () {
      expect(redactSpoilers(''), '');
    });
    test('redacts a single spoiler span', () {
      expect(redactSpoilers('before ||hi|| after'), 'before ▮▮ after');
    });
    test('redacts multiple spoilers in one string', () {
      expect(redactSpoilers('||a|| plain ||bb||'), '▮ plain ▮▮');
    });
    test('clamps long spoilers to 8 blocks', () {
      expect(redactSpoilers('||${'x' * 50}||'), '▮' * 8);
    });
    test('leaves unclosed || markers literal', () {
      expect(redactSpoilers('text with || only'), 'text with || only');
    });
    test('redacts mid-word spoilers', () {
      expect(redactSpoilers('foo||bar||baz'), 'foo▮▮▮baz');
    });
  });

  group('hasMarkdownChars', () {
    test('detects | as a markdown trigger', () {
      expect(hasMarkdownChars('||hi||'), isTrue);
    });
    test('still detects existing triggers', () {
      expect(hasMarkdownChars('**bold**'), isTrue);
      expect(hasMarkdownChars('@[abc]'), isTrue);
    });
    test('plain text is false', () {
      expect(hasMarkdownChars('plain text'), isFalse);
    });
  });

  group('SpoilerSyntax parsing', () {
    // Use the markdown package directly to verify the AST shape.
    test('emits a spoiler element with matching text', () {
      final doc = md.Document(
        inlineSyntaxes: [SpoilerSyntax()],
        extensionSet: md.ExtensionSet.none,
      );
      final lines = const LineSplitter().convert('hi ||secret|| ok');
      final nodes = doc.parseLines(lines);
      final visitor = _SpoilerCollector();
      for (final n in nodes) {
        n.accept(visitor);
      }
      expect(visitor.spoilers, hasLength(1));
      expect(visitor.spoilers.first.textContent, 'secret');
      // Reveal identity is assigned downstream by SpoilerBuilder in document
      // order, not stamped here as a block-local offset.
      expect(visitor.spoilers.first.attributes['start'], isNull);
    });

    test('emits one element per spoiler with its inner text', () {
      final doc = md.Document(
        inlineSyntaxes: [SpoilerSyntax()],
        extensionSet: md.ExtensionSet.none,
      );
      final nodes = doc.parseLines(['a ||b|| c ||d||']);
      final visitor = _SpoilerCollector();
      for (final n in nodes) {
        n.accept(visitor);
      }
      expect(
        visitor.spoilers.map((e) => e.textContent).toList(),
        ['b', 'd'],
      );
    });
  });
}

class _SpoilerCollector implements md.NodeVisitor {
  final spoilers = <md.Element>[];

  @override
  bool visitElementBefore(md.Element e) {
    if (e.tag == 'spoiler') spoilers.add(e);
    return true;
  }

  @override
  void visitElementAfter(md.Element e) {}

  @override
  void visitText(md.Text t) {}
}
