import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
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
    await syncRecordCreate(
      _table,
      conversation.id,
      _conversationFields(conversation),
    );
  }

  @override
  Future<void> updateConversation(domain.Conversation conversation) async {
    final companion = ConversationMapper.toCompanion(conversation);
    await _dao.updateConversation(companion);
    await syncRecordUpdate(
      _table,
      conversation.id,
      _conversationFields(conversation),
    );
  }

  @override
  Future<void> addParticipantId(String conversationId, String memberId) async {
    final row = await _dao.getConversationById(conversationId);
    if (row == null) return;
    final conv = ConversationMapper.toDomain(row);
    if (conv.participantIds.contains(memberId)) return;
    final updatedIds = [...conv.participantIds, memberId];
    final json = jsonEncode(updatedIds);
    await _dao.updateParticipantIds(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {'participant_ids': json});
  }

  @override
  Future<void> addParticipantIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    if (memberIds.isEmpty) return;
    final row = await _dao.getConversationById(conversationId);
    if (row == null) return;
    final conv = ConversationMapper.toDomain(row);
    final existingIds = conv.participantIds.toSet();
    final newIds = memberIds.where((id) => !existingIds.contains(id)).toList();
    if (newIds.isEmpty) return;
    final updatedIds = [...conv.participantIds, ...newIds];
    final json = jsonEncode(updatedIds);
    await _dao.updateParticipantIds(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {'participant_ids': json});
  }

  @override
  Future<void> removeParticipantId(
    String conversationId,
    String memberId,
  ) async {
    final row = await _dao.getConversationById(conversationId);
    if (row == null) return;
    final conv = ConversationMapper.toDomain(row);
    if (!conv.participantIds.contains(memberId)) return;
    final updatedIds = conv.participantIds
        .where((id) => id != memberId)
        .toList();
    final json = jsonEncode(updatedIds);
    await _dao.updateParticipantIds(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {'participant_ids': json});
  }

  @override
  Future<void> setArchivedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    final json = jsonEncode(memberIds);
    await _dao.updateArchivedByMemberIds(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {
      'archived_by_member_ids': json,
    });
  }

  @override
  Future<void> setMutedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    final json = jsonEncode(memberIds);
    await _dao.updateMutedByMemberIds(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {
      'muted_by_member_ids': json,
    });
  }

  @override
  Future<void> setLastReadTimestamps(
    String conversationId,
    Map<String, DateTime> timestamps,
  ) async {
    // Normalize to UTC before serializing — local DateTimes emit no offset/Z,
    // so a peer in a different timezone would parse the value as local and
    // shift the absolute moment by the timezone delta on every sync.
    final json = jsonEncode(
      timestamps.map((k, v) => MapEntry(k, toSyncUtc(v))),
    );
    await _dao.updateLastReadTimestamps(conversationId, json);
    await syncRecordUpdate(_table, conversationId, {
      'last_read_timestamps': json,
    });
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

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed (with a leading `$` so it
  /// stays clearly internal) so a regression test can assert that every
  /// DateTime ends up Z-suffixed UTC — see drift_conversation_repository_test.
  /// The TZ-drift bug Agent O caught in `setLastReadTimestamps` had
  /// matching siblings here; the test pins the contract for all of them.
  @visibleForTesting
  Map<String, dynamic> debugConversationFields(domain.Conversation c) =>
      _conversationFields(c);

  Map<String, dynamic> _conversationFields(domain.Conversation c) {
    final lastReadTimestampsJson = jsonEncode(
      c.lastReadTimestamps.map((k, v) => MapEntry(k, toSyncUtc(v))),
    );
    return {
      'created_at': toSyncUtc(c.createdAt),
      'last_activity_at': toSyncUtc(c.lastActivityAt),
      'title': c.title,
      'emoji': c.emoji,
      'is_direct_message': c.isDirectMessage,
      'creator_id': c.creatorId,
      'participant_ids': jsonEncode(c.participantIds),
      'archived_by_member_ids': jsonEncode(c.archivedByMemberIds),
      'muted_by_member_ids': jsonEncode(c.mutedByMemberIds),
      'last_read_timestamps': lastReadTimestampsJson,
      'description': c.description,
      'category_id': c.categoryId,
      'display_order': c.displayOrder,
      'is_deleted': false,
    };
  }
}
