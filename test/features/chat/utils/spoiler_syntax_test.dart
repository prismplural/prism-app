import 'package:flutter_test/flutter_test.dart';
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
}
