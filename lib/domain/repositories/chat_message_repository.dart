import 'package:prism_plurality/domain/models/chat_message.dart' as domain;

abstract class ChatMessageRepository {
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  });
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
      String conversationId);
  Future<domain.ChatMessage?> getMessageById(String id);
  Future<void> createMessage(domain.ChatMessage message);
  Future<void> updateMessage(domain.ChatMessage message);
  Future<void> deleteMessage(String id);
  Future<domain.ChatMessage?> getLatestMessage(String conversationId);
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId);
  Future<List<({String messageId, String conversationId, String snippet, DateTime timestamp, String? authorId})>> searchMessages(String query, {int limit});
  Stream<int> watchUnreadCount(String conversationId, DateTime since);
  Stream<int> watchUnreadMentionCount(String conversationId, DateTime since, String memberId);
  Stream<Map<String, int>> watchAllUnreadCounts(Map<String, DateTime> conversationSince);
  Stream<Set<String>> watchConversationsWithMentions(Map<String, DateTime> conversationSince, String memberId);
}
