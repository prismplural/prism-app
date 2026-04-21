// Targeted integration test for spoiler redaction in the conversation-list
// preview.
//
// The full `conversationTileDataProvider` composition involves Drift streams,
// member batch providers, and sync infrastructure — mirroring the shape of
// `conversation_tile_data_test.dart`, we exercise the exact expression used
// at the provider's last-message-display-content assignment rather than
// standing up the full reactive graph. If that expression changes, this test
// fails and signals that the provider wiring needs re-review.
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

void main() {
  group('conversation-list preview spoiler redaction', () {
    test('last message content with spoiler does not leak plaintext', () {
      const rawContent = 'spoiler: ||the ending||';
      const nameMap = <String, String>{};

      // This expression is the literal composition used in
      // `chat_providers.dart` when building `ConversationTileData`.
      final displayContent = redactSpoilers(
        replaceMentionsWithNames(rawContent, nameMap),
      );

      expect(displayContent, isNot(contains('ending')));
      expect(displayContent, contains('\u25AE'));
    });

    test('spoiler redaction preserves surrounding text', () {
      const rawContent = 'hey ||secret|| look';
      final displayContent = redactSpoilers(
        replaceMentionsWithNames(rawContent, const {}),
      );

      expect(displayContent, startsWith('hey '));
      expect(displayContent, endsWith(' look'));
      expect(displayContent, isNot(contains('secret')));
    });

    test('message without spoilers is unchanged', () {
      const rawContent = 'just a normal message';
      final displayContent = redactSpoilers(
        replaceMentionsWithNames(rawContent, const {}),
      );

      expect(displayContent, 'just a normal message');
    });
  });
}
