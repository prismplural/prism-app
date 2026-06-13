import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/data/mappers/chat_message_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';

class DriftChatMessageRepository
    with SyncRecordMixin
    implements ChatMessageRepository {
  final ChatMessagesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  @override
  db.AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

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
  Stream<List<domain.ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) {
    return _dao
        .watchRecentMessages(conversationId, limit: limit)
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
  Future<bool> isMessageDeleted(String messageId) async {
    final row = await _dao.getMessageById(messageId);
    return row?.isDeleted ?? true;
  }

  @override
  Future<void> createMessage(domain.ChatMessage message) async {
    // Insert + create-op intent commit atomically; dispatch post-commit
    // (FFI outside the txn — reverted-revert invariant).
    await runSyncedWrite(() async {
      final companion = ChatMessageMapper.toCompanion(message);
      await _dao.insertMessage(companion);
      await syncRecordCreate(_table, message.id, _messageFields(message));
    });
  }

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {
    // Read-diff-write + update-op intent in one atomic txn (dispatch
    // post-commit, FFI outside the txn).
    await runSyncedWrite(() async {
      final existingRow = await _dao.getMessageById(message.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _messageFieldsFromRow(existingRow),
        _messageFields(message),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialMessageCompanion(message.id, changedFields);
      await _dao.updateMessage(companion);
      await syncRecordUpdate(_table, message.id, changedFields);
    });
  }

  @override
  Future<void> deleteMessage(String id) async {
    // Tombstone path (unrecoverable): the message + attachment tombstones
    // and their delete-op intents commit atomically; dispatch post-commit (FFI
    // outside the txn).
    await runSyncedWrite(() async {
      final result = await _dao.softDeleteMessageAndAttachments(id);

      if (result.messageDeleted) {
        await syncRecordDelete(_table, id);
      }
      for (final attachmentId in result.attachmentIds) {
        await syncRecordDelete('media_attachments', attachmentId);
      }
    });
  }

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async {
    final row = await _dao.getLatestMessage(conversationId);
    return row != null ? ChatMessageMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) {
    return _dao
        .watchLatestMessage(conversationId)
        .map((row) => row != null ? ChatMessageMapper.toDomain(row) : null);
  }

  @override
  Future<
    List<
      ({
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId,
      })
    >
  >
  searchMessages(String query, {int limit = 50}) async {
    return _dao.searchMessages(query, limit: limit);
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

  Map<String, dynamic> _messageFields(domain.ChatMessage m) => messageFields(m);

  /// Mirror of [messageFields] but reading from the stored Drift row.
  ///
  /// Pass-through `reactions` as-is (the stored JSON string). Order in
  /// `reactions` is semantically meaningful (display order / time-of-reaction
  /// sequence), so we deliberately do NOT canonicalize. See migration plan
  /// `docs/plans/2026-05-25-drift-repo-patch-update-migration.md`.
  Map<String, dynamic> _messageFieldsFromRow(db.ChatMessage row) {
    return {
      'content': row.content,
      'timestamp': toSyncUtc(row.timestamp),
      'is_system_message': row.isSystemMessage,
      'edited_at': toSyncUtcOrNull(row.editedAt),
      'author_id': row.authorId,
      'conversation_id': row.conversationId,
      'reactions': row.reactions,
      'reply_to_id': row.replyToId,
      'reply_to_author_id': row.replyToAuthorId,
      'reply_to_content': row.replyToContent,
      'is_deleted': row.isDeleted,
    };
  }

  /// Build a sparse `ChatMessagesCompanion` from a patch map.
  ///
  /// Always sets `id` (the DAO targets the row by `companion.id`). Every
  /// other column is absent unless the patch contains its key.
  db.ChatMessagesCompanion _partialMessageCompanion(
    String id,
    Map<String, dynamic> fields,
  ) {
    return db.ChatMessagesCompanion(
      id: Value(id),
      content: fields.containsKey('content')
          ? Value(fields['content'] as String)
          : const Value.absent(),
      timestamp: fields.containsKey('timestamp')
          ? Value(parseSyncDateTime(fields['timestamp']))
          : const Value.absent(),
      isSystemMessage: fields.containsKey('is_system_message')
          ? Value(fields['is_system_message'] as bool)
          : const Value.absent(),
      editedAt: fields.containsKey('edited_at')
          ? Value(
              fields['edited_at'] == null
                  ? null
                  : parseSyncDateTime(fields['edited_at']),
            )
          : const Value.absent(),
      authorId: fields.containsKey('author_id')
          ? Value(fields['author_id'] as String?)
          : const Value.absent(),
      conversationId: fields.containsKey('conversation_id')
          ? Value(fields['conversation_id'] as String)
          : const Value.absent(),
      reactions: fields.containsKey('reactions')
          ? Value(fields['reactions'] as String)
          : const Value.absent(),
      replyToId: fields.containsKey('reply_to_id')
          ? Value(fields['reply_to_id'] as String?)
          : const Value.absent(),
      replyToAuthorId: fields.containsKey('reply_to_author_id')
          ? Value(fields['reply_to_author_id'] as String?)
          : const Value.absent(),
      replyToContent: fields.containsKey('reply_to_content')
          ? Value(fields['reply_to_content'] as String?)
          : const Value.absent(),
    );
  }

  /// Field-map builder for chat-message sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createMessage()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> messageFields(domain.ChatMessage m) {
    final reactionsJson = jsonEncode(
      m.reactions.map((r) => r.toJson()).toList(),
    );
    return {
      'content': m.content,
      'timestamp': toSyncUtc(m.timestamp),
      'is_system_message': m.isSystemMessage,
      'edited_at': toSyncUtcOrNull(m.editedAt),
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
