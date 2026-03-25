import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

/// Tests for mention rendering logic used by message bubbles.
///
/// The actual widget rendering requires a full Flutter test environment
/// with Riverpod providers. These tests verify the text transformation
/// logic that the widgets delegate to.
void main() {
  const id1 = '00000000-0000-0000-0000-000000000001';
  const id2 = 'abcdef12-3456-7890-abcd-ef1234567890';

  group('mention rendering text transformations', () {
    test('single mention replaced with @Name', () {
      final nameMap = {id1: 'Alice'};
      final result = replaceMentionsWithNames('Hello @[$id1]!', nameMap);
      expect(result, 'Hello @Alice!');
    });

    test('multiple mentions replaced', () {
      final nameMap = {id1: 'Alice', id2: 'Bob'};
      final result = replaceMentionsWithNames(
        '@[$id1] said hi to @[$id2]',
        nameMap,
      );
      expect(result, '@Alice said hi to @Bob');
    });

    test('unknown member shows @Unknown', () {
      final result = replaceMentionsWithNames('Hey @[$id1]', {});
      expect(result, 'Hey @Unknown');
    });

    test('content without mentions passes through unchanged', () {
      const content = 'Just a normal message';
      final result = replaceMentionsWithNames(content, {id1: 'Alice'});
      expect(result, content);
    });

    test('mentionRegex correctly splits content', () {
      const content = 'Before @[$id1] middle @[$id2] after';
      final matches = mentionRegex.allMatches(content).toList();

      expect(matches, hasLength(2));
      expect(matches[0].group(1), id1);
      expect(matches[1].group(1), id2);

      // Verify split positions for span building
      expect(content.substring(0, matches[0].start), 'Before ');
      expect(
        content.substring(matches[0].end, matches[1].start),
        ' middle ',
      );
      expect(content.substring(matches[1].end), ' after');
    });

    test('adjacent mentions have no gap', () {
      const content = '@[$id1]@[$id2]';
      final nameMap = {id1: 'A', id2: 'B'};
      expect(replaceMentionsWithNames(content, nameMap), '@A@B');
    });
  });
}
