import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/conversation.dart' as domain;
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';

class DriftConversationRepository
    with SyncRecordMixin
    implements ConversationRepository {
  final ConversationsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'conversations';

  DriftConversationRepository(this._dao, this._syncHandle);

  @override
  Future<List<domain.Conversation>> getAllConversations() async {
    final rows = await _dao.getAllConversations();
    return rows.map(ConversationMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.Conversation>> watchAllConversations() {
    return _dao.watchAllConversations().map(
      (rows) => rows.map(ConversationMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.Conversation?> getConversationById(String id) async {
    final row = await _dao.getConversationById(id);
    return row != null ? ConversationMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.Conversation?> watchConversationById(String id) {
    return _dao
        .watchConversationById(id)
        .map((row) => row != null ? ConversationMapper.toDomain(row) : null);
  }

  @override
  Future<List<domain.Conversation>> getConversationsForMember(
    String memberId,
  ) async {
    final rows = await _dao.getConversationsForMember(memberId);
    return rows.map(ConversationMapper.toDomain).toList();
  }

  @override
  Future<void> createConversation(domain.Conversation conversation) async {
    final companion = ConversationMapper.toCompanion(conversation);
    await _dao.insertConversation(companion);
    await syncRecordCreate(_table, conversation.id, _conversationFields(conversation));
  }

  @override
  Future<void> updateConversation(domain.Conversation conversation) async {
    final companion = ConversationMapper.toCompanion(conversation);
    await _dao.updateConversation(companion);
    await syncRecordUpdate(_table, conversation.id, _conversationFields(conversation));
  }

  @override
  Future<void> deleteConversation(String id) async {
    await _dao.softDeleteConversation(id);
    await syncRecordDelete(_table, id);
  }

  @override
  Future<int> getCount() => _dao.getCount();

  @override
  Future<void> updateLastActivity(String id) async {
    await _dao.updateLastActivity(id);
    // Fetch the updated conversation to build a full field map.
    final row = await _dao.getConversationById(id);
    if (row != null) {
      final conversation = ConversationMapper.toDomain(row);
      await syncRecordUpdate(_table, id, _conversationFields(conversation));
    }
  }

  Map<String, dynamic> _conversationFields(domain.Conversation c) {
    final lastReadTimestampsJson = jsonEncode(
      c.lastReadTimestamps.map((k, v) => MapEntry(k, v.toIso8601String())),
    );
    return {
      'created_at': c.createdAt.toIso8601String(),
      'last_activity_at': c.lastActivityAt.toIso8601String(),
      'title': c.title,
      'emoji': c.emoji,
      'is_direct_message': c.isDirectMessage,
      'creator_id': c.creatorId,
      'participant_ids': jsonEncode(c.participantIds),
      'archived_by_member_ids': jsonEncode(c.archivedByMemberIds),
      'last_read_timestamps': lastReadTimestampsJson,
      'description': c.description,
      'category_id': c.categoryId,
      'display_order': c.displayOrder,
      'is_deleted': false,
    };
  }
}
