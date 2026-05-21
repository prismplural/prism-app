import 'package:prism_plurality/domain/models/conversation.dart' as domain;

abstract class ConversationRepository {
  Future<List<domain.Conversation>> getAllConversations();
  Stream<List<domain.Conversation>> watchAllConversations();
  Future<domain.Conversation?> getConversationById(String id);
  Future<List<domain.Conversation>> getConversationsByIds(List<String> ids);
  Future<domain.Conversation?> getMentionConversationById(String id);
  Stream<List<domain.Conversation>> watchMentionConversationsByIds(
    List<String> ids,
  );
  Future<List<domain.Conversation>> searchMentionCandidates(
    String filter, {
    int limit = 12,
    List<String> activeFronterIds = const [],
    bool includeAdminGroups = false,
  });
  Stream<domain.Conversation?> watchConversationById(String id);
  Future<List<domain.Conversation>> getConversationsForMember(String memberId);
  Future<void> createConversation(domain.Conversation conversation);
  Future<void> updateConversation(domain.Conversation conversation);
  Future<void> deleteConversation(String id);
  Future<void> addParticipantId(String conversationId, String memberId);
  Future<void> addParticipantIds(String conversationId, List<String> memberIds);
  Future<void> removeParticipantId(String conversationId, String memberId);
  Future<void> setIncludesAllMembers(String conversationId, bool value);
  Future<void> setArchivedByMemberIds(
    String conversationId,
    List<String> memberIds,
  );
  Future<void> setMutedByMemberIds(
    String conversationId,
    List<String> memberIds,
  );
  Future<void> setLastReadTimestamps(
    String conversationId,
    Map<String, DateTime> timestamps,
  );
  Future<void> updateLastActivity(String id);
  Future<int> getCount();
}
