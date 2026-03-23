import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/features/chat/widgets/prism_message_group.dart';

void main() {
  group('MessageGroupBuilder', () {
    final now = DateTime(2026, 3, 18, 12, 0, 0);

    test('groups consecutive messages from the same author', () {
      final messages = [
        ChatMessage(
          id: '2',
          content: 'world',
          timestamp: now.add(const Duration(seconds: 30)),
          conversationId: 'c',
          authorId: 'a',
        ),
        ChatMessage(
          id: '1',
          content: 'hello',
          timestamp: now,
          conversationId: 'c',
          authorId: 'a',
        ),
      ];
      final groups = const MessageGroupBuilder().build(messages);
      final messageGroups = groups.whereType<MessageGroup>().toList();
      expect(messageGroups.length, 1);
      expect(messageGroups.first.messages.length, 2);
    });

    test('reply message always breaks the group even with same author', () {
      final messages = [
        ChatMessage(
          id: '2',
          content: 'I am replying',
          timestamp: now.add(const Duration(seconds: 10)),
          conversationId: 'c',
          authorId: 'a',
          replyToId: '1',
          replyToAuthorId: 'a',
          replyToContent: 'hello',
        ),
        ChatMessage(
          id: '1',
          content: 'hello',
          timestamp: now,
          conversationId: 'c',
          authorId: 'a',
        ),
      ];
      final groups = const MessageGroupBuilder().build(messages);
      final messageGroups = groups.whereType<MessageGroup>().toList();
      // Should produce 2 separate groups, not 1
      expect(messageGroups.length, 2);
    });
  });
}
