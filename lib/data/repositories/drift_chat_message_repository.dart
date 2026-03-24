import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/data/mappers/chat_message_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';

class DriftChatMessageRepository
    with SyncRecordMixin
    implements ChatMessageRepository {
  final ChatMessagesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'chat_messages';

  DriftChatMessageRepository(this._dao, this._syncHandle);

  @override
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    final rows = await _dao.getMessagesForConversation(
      conversationId,
      limit: limit,
      offset: offset,
    );
    return rows.map(ChatMessageMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) {
    return _dao
        .watchMessagesForConversation(conversationId)
        .map((rows) => rows.map(ChatMessageMapper.toDomain).toList());
  }

  @override
  Future<List<domain.ChatMessage>> getAllMessages() async {
    final rows = await _dao.getAllMessages();
    return rows.map(ChatMessageMapper.toDomain).toList();
  }

  @override
  Future<domain.ChatMessage?> getMessageById(String id) async {
    final row = await _dao.getMessageById(id);
    return row != null ? ChatMessageMapper.toDomain(row) : null;
  }

  @override
  Future<void> createMessage(domain.ChatMessage message) async {
    final companion = ChatMessageMapper.toCompanion(message);
    await _dao.insertMessage(companion);
    await syncRecordCreate(_table, message.id, _messageFields(message));
  }

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {
    final companion = ChatMessageMapper.toCompanion(message);
    await _dao.updateMessage(companion);
    await syncRecordUpdate(_table, message.id, _messageFields(message));
  }

  @override
  Future<void> deleteMessage(String id) async {
    await _dao.softDeleteMessage(id);
    await syncRecordDelete(_table, id);
  }

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async {
    final row = await _dao.getLatestMessage(conversationId);
    return row != null ? ChatMessageMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) {
    return _dao.watchLatestMessage(conversationId).map(
      (row) => row != null ? ChatMessageMapper.toDomain(row) : null,
    );
  }

  @override
  Future<List<({String messageId, String conversationId, String snippet, DateTime timestamp, String? authorId})>> searchMessages(String query, {int limit = 50}) async {
    final rows = await _dao.searchMessages(query, limit: limit);
    return rows.map((row) {
      return (
        messageId: row.read<String>('message_id'),
        conversationId: row.read<String>('conversation_id'),
        snippet: row.read<String>('snippet'),
        timestamp: DateTime.fromMillisecondsSinceEpoch(row.read<int>('timestamp') * 1000),
        authorId: row.readNullable<String>('author_id'),
      );
    }).toList();
  }

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) {
    return _dao.watchUnreadCount(conversationId, since);
  }

  @override
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) {
    return _dao.watchUnreadMentionCount(conversationId, since, memberId);
  }

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) {
    return _dao.watchAllUnreadCounts(conversationSince);
  }

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) {
    return _dao.watchConversationsWithMentions(conversationSince, memberId);
  }

  Map<String, dynamic> _messageFields(domain.ChatMessage m) {
    final reactionsJson = jsonEncode(
      m.reactions.map((r) => r.toJson()).toList(),
    );
    return {
      'content': m.content,
      'timestamp': m.timestamp.toIso8601String(),
      'is_system_message': m.isSystemMessage,
      'edited_at': m.editedAt?.toIso8601String(),
      'author_id': m.authorId,
      'conversation_id': m.conversationId,
      'reactions': reactionsJson,
      'reply_to_id': m.replyToId,
      'reply_to_author_id': m.replyToAuthorId,
      'reply_to_content': m.replyToContent,
      'is_deleted': false,
    };
  }
}
