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
    test('emits a spoiler element with matching text and start offset', () {
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
      expect(visitor.spoilers.first.attributes['start'], '3');
    });

    test('emits distinct start offsets for multiple spoilers', () {
      final doc = md.Document(
        inlineSyntaxes: [SpoilerSyntax()],
        extensionSet: md.ExtensionSet.none,
      );
      final nodes = doc.parseLines(['a ||b|| c ||d||']);
      final visitor = _SpoilerCollector();
      for (final n in nodes) {
        n.accept(visitor);
      }
      expect(visitor.spoilers.map((e) => e.attributes['start']).toList(),
          ['2', '10']);
    });

    test('parsing the same string twice yields the same offsets', () {
      final doc = md.Document(
        inlineSyntaxes: [SpoilerSyntax()],
        extensionSet: md.ExtensionSet.none,
      );
      final v1 = _SpoilerCollector();
      for (final n in doc.parseLines(['hi ||x||'])) {
        n.accept(v1);
      }
      final v2 = _SpoilerCollector();
      for (final n in doc.parseLines(['hi ||x||'])) {
        n.accept(v2);
      }
      expect(v1.spoilers.first.attributes['start'],
          v2.spoilers.first.attributes['start']);
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
