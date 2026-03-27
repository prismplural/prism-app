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
  Future<void> addParticipantId(String conversationId, String memberId);
  Future<void> addParticipantIds(String conversationId, List<String> memberIds);
  Future<void> removeParticipantId(String conversationId, String memberId);
  Future<void> setArchivedByMemberIds(String conversationId, List<String> memberIds);
  Future<void> setMutedByMemberIds(String conversationId, List<String> memberIds);
  Future<void> setLastReadTimestamps(String conversationId, Map<String, DateTime> timestamps);
  Future<void> updateLastActivity(String id);
  Future<int> getCount();
}
