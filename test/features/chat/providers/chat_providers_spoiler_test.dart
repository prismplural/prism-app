// Targeted integration test for spoiler redaction in the conversation-list
// preview. Calls the production `buildTilePreviewContent` directly so a
// refactor of the composition order inside that function breaks this test.
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

void main() {
  group('conversation-list preview spoiler redaction', () {
    test('last message content with spoiler does not leak plaintext', () {
      final displayContent = buildTilePreviewContent(
        'spoiler: ||the ending||',
        const {},
      );

      expect(displayContent, isNot(contains('ending')));
      expect(displayContent, contains('\u25AE'));
    });

    test('spoiler redaction preserves surrounding text', () {
      final displayContent = buildTilePreviewContent(
        'hey ||secret|| look',
        const {},
      );

      expect(displayContent, startsWith('hey '));
      expect(displayContent, endsWith(' look'));
      expect(displayContent, isNot(contains('secret')));
    });

    test('mention + spoiler: mentions resolve BEFORE redaction (order matters)',
        () {
      // `redactSpoilers` clamps its block count to 8, so:
      //   content = '||@[uuid]||'      (inner is 39 chars)
      //   correct: resolve → redact   → 6 blocks (`@Alice` inner = 6)
      //   reverse: redact  → resolve  → 8 blocks (clamp on the raw token)
      // Swapping the calls produces a different-length string, so this
      // assertion catches an ordering regression inside
      // `buildTilePreviewContent`.
      const memberId = '01234567-89ab-cdef-0123-456789abcdef';
      const rawContent = '||@[$memberId]||';
      final nameMap = <String, String>{memberId: 'Alice'};

      final correct = buildTilePreviewContent(rawContent, nameMap);
      expect(
        correct,
        '▮' * 6,
        reason: 'mentions must resolve first so redaction clamps on the '
            'display-length of `@Alice` (6), not the raw `@[uuid]` token',
      );

      final reversed = replaceMentionsWithNames(
        redactSpoilers(rawContent),
        nameMap,
      );
      expect(reversed, '▮' * 8);
      expect(correct, isNot(equals(reversed)));
    });

    test('message without spoilers is unchanged', () {
      expect(
        buildTilePreviewContent('just a normal message', const {}),
        'just a normal message',
      );
    });
  });
}
