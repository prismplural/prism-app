import 'package:prism_plurality/domain/models/conversation.dart' as domain;

abstract class ConversationRepository {
  Future<List<domain.Conversation>> getAllConversations();
  Stream<List<domain.Conversation>> watchAllConversations();
  Future<domain.Conversation?> getConversationById(String id);
  Stream<domain.Conversation?> watchConversationById(String id);
  Future<List<domain.Conversation>> getConversationsForMember(String memberId);
  Future<void> createConversation(domain.Conversation conversation);
  Future<void> updateConversation(domain.Conversation conversation);
  Future<void> deleteConversation(String id);
  Future<void> updateLastActivity(String id);
  Future<int> getCount();
}
