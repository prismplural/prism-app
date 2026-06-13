import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
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

  @override
  db.AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

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
  Future<List<domain.Conversation>> getConversationsByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const <domain.Conversation>[];
    final rows = await _dao.getConversationsByIds(ids);
    return rows.map(ConversationMapper.toDomain).toList();
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
  Future<List<ConversationActivity>> getConversationActivityForMember(
    String memberId, {
    int? limit,
  }) async {
    final rows = await _dao.getConversationActivityForMember(
      memberId,
      limit: limit,
    );
    return rows
        .map(
          (row) => (
            conversation: ConversationMapper.toDomain(row.conversation),
            messageCount: row.messageCount,
          ),
        )
        .toList();
  }

  // Every mutation below wraps its DAO write and its sync-op emission in
  // `runSyncedWrite`, so the data row and the durable outbox row(s) commit
  // atomically and the FFI dispatch happens strictly post-commit (the
  // reverted-revert invariant). Reached from the member-delete cascade these
  // run under an active suppress/capture context, where `runSyncedWrite` defers
  // to the outer seam (no nested transaction, emissions captured by the cascade).
  @override
  Future<void> createConversation(domain.Conversation conversation) async {
    await runSyncedWrite(() async {
      final companion = ConversationMapper.toCompanion(conversation);
      await _dao.insertConversation(companion);
      final fields = _conversationFields(conversation);
      // Sparse-emit for pre-v25 peers — kept outside `_conversationFields`
      // because diffSyncFields can't represent sparse semantics. Inline-emit
      // only when true (matches the pre-migration `conversationFields`
      // contract for new rows).
      if (conversation.includesAllMembers) {
        fields['includes_all_members'] = true;
      }
      if (conversation.archivedForEveryone) {
        fields['archived_for_everyone'] = true;
      }
      await syncRecordCreate(_table, conversation.id, fields);
    });
  }

  @override
  Future<void> updateConversation(domain.Conversation conversation) async {
    await runSyncedWrite(() async {
      final existingRow = await _dao.getConversationById(conversation.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _conversationFieldsFromRow(existingRow),
        _conversationFields(conversation),
      );

      // Sparse-emit for pre-schema peers — kept outside the diff helper because
      // diffSyncFields can't represent sparse semantics. `_conversationFields`
      // and `_conversationFieldsFromRow` both omit `includes_all_members` and
      // `archived_for_everyone`, so the diff can never surface either
      // transition; emit each inline whenever its boolean changes, mirroring
      // the setters.
      final previousIncludesAll = existingRow.includesAllMembers;
      final nextIncludesAll = conversation.includesAllMembers;
      if (previousIncludesAll != nextIncludesAll) {
        changedFields['includes_all_members'] = nextIncludesAll;
      }
      final previousArchivedForEveryone = existingRow.archivedForEveryone;
      final nextArchivedForEveryone = conversation.archivedForEveryone;
      if (previousArchivedForEveryone != nextArchivedForEveryone) {
        changedFields['archived_for_everyone'] = nextArchivedForEveryone;
      }

      if (changedFields.isEmpty) return;

      final companion = _partialConversationCompanion(
        conversation.id,
        changedFields,
        includesAllMembers: previousIncludesAll != nextIncludesAll
            ? nextIncludesAll
            : null,
        archivedForEveryone:
            previousArchivedForEveryone != nextArchivedForEveryone
            ? nextArchivedForEveryone
            : null,
      );
      await _dao.updateConversation(companion);
      await syncRecordUpdate(_table, conversation.id, changedFields);
    });
  }

  @override
  Future<void> addParticipantId(String conversationId, String memberId) async {
    await runSyncedWrite(() async {
      final row = await _dao.getConversationById(conversationId);
      if (row == null) return;
      final conv = ConversationMapper.toDomain(row);
      if (conv.participantIds.contains(memberId)) return;
      final updatedIds = [...conv.participantIds, memberId];
      final json = jsonEncode(updatedIds);
      await _dao.updateParticipantIds(conversationId, json);
      await syncRecordUpdate(_table, conversationId, {'participant_ids': json});
    });
  }

  @override
  Future<void> addParticipantIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    if (memberIds.isEmpty) return;
    await runSyncedWrite(() async {
      final row = await _dao.getConversationById(conversationId);
      if (row == null) return;
      final conv = ConversationMapper.toDomain(row);
      final existingIds = conv.participantIds.toSet();
      final newIds = memberIds
          .where((id) => !existingIds.contains(id))
          .toList();
      if (newIds.isEmpty) return;
      final updatedIds = [...conv.participantIds, ...newIds];
      final json = jsonEncode(updatedIds);
      await _dao.updateParticipantIds(conversationId, json);
      await syncRecordUpdate(_table, conversationId, {'participant_ids': json});
    });
  }

  @override
  Future<void> removeParticipantId(
    String conversationId,
    String memberId,
  ) async {
    await runSyncedWrite(() async {
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
    });
  }

  @override
  Future<void> setIncludesAllMembers(String conversationId, bool value) async {
    await runSyncedWrite(() async {
      await _dao.updateIncludesAllMembers(conversationId, value);
      await syncRecordUpdate(_table, conversationId, {
        'includes_all_members': value,
      });
    });
  }

  @override
  Future<void> setArchivedForEveryone(String conversationId, bool value) async {
    await runSyncedWrite(() async {
      await _dao.updateArchivedForEveryone(conversationId, value);
      await syncRecordUpdate(_table, conversationId, {
        'archived_for_everyone': value,
      });
    });
  }

  @override
  Future<void> setArchivedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    await runSyncedWrite(() async {
      final json = jsonEncode(memberIds);
      await _dao.updateArchivedByMemberIds(conversationId, json);
      await syncRecordUpdate(_table, conversationId, {
        'archived_by_member_ids': json,
      });
    });
  }

  @override
  Future<void> setMutedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {
    await runSyncedWrite(() async {
      final json = jsonEncode(memberIds);
      await _dao.updateMutedByMemberIds(conversationId, json);
      await syncRecordUpdate(_table, conversationId, {
        'muted_by_member_ids': json,
      });
    });
  }

  @override
  Future<void> setLastReadTimestamps(
    String conversationId,
    Map<String, DateTime> timestamps,
  ) async {
    await runSyncedWrite(() async {
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
    });
  }

  @override
  Future<void> deleteConversation(String id) async {
    // Tombstone path (unrecoverable): soft-delete + delete-op intent
    // commit atomically; dispatch post-commit (FFI outside the txn).
    await runSyncedWrite(() async {
      await _dao.softDeleteConversation(id);
      await syncRecordDelete(_table, id);
    });
  }

  @override
  Future<int> getCount() => _dao.getCount();

  @override
  Future<void> updateLastActivity(String id) async {
    await runSyncedWrite(() async {
      // Read BEFORE the DAO write so the diff sees the pre-bump state.
      // Refetching after the write would over-emit every column (see the
      // read-after-write trap in the migration plan).
      final existingRow = await _dao.getConversationById(id);
      if (existingRow == null || existingRow.isDeleted) return;

      final bumped = ConversationMapper.toDomain(
        existingRow,
      ).copyWith(lastActivityAt: DateTime.now());
      final changedFields = diffSyncFields(
        _conversationFieldsFromRow(existingRow),
        _conversationFields(bumped),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialConversationCompanion(id, changedFields);
      await _dao.updateConversation(companion);
      await syncRecordUpdate(_table, id, changedFields);
    });
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

  Map<String, dynamic> _conversationFields(domain.Conversation c) =>
      conversationFields(c);

  /// Mirror of [conversationFields] built from a Drift row. Used by the
  /// patch-style update flow as the "previous" side of the diff.
  ///
  /// **Carve-out**: `includes_all_members` and `archived_for_everyone` are
  /// intentionally absent from both this helper and [conversationFields]. Each
  /// on-wire field is sparse-emitted (only present when `true`) for pre-schema
  /// peers, and [diffSyncFields] can't represent sparse semantics — see
  /// `updateConversation` for the inline emit handling the false→true /
  /// true→false transition.
  ///
  /// The "previous" side must encode through the same pipeline as the
  /// "next" side ([conversationFields]). `lastReadTimestamps` is stored as
  /// raw JSON via [ConversationMapper.toCompanion] (`.toIso8601String()` with
  /// no UTC normalization) but emitted via [toSyncUtc] (`.toUtc()`). To keep
  /// the diff symmetric, parse the stored JSON back through the domain
  /// mapper and re-encode through `conversationFields`'s timestamp path.
  Map<String, dynamic> _conversationFieldsFromRow(db.Conversation row) {
    // Round-trip the row through the domain mapper so the wire encoding
    // matches `_conversationFields(domain)` exactly. The mapper already
    // tolerates malformed JSON (logs + falls back to empty), so this is no
    // worse than the prior whole-row emit path which also went through the
    // mapper.
    final domainView = ConversationMapper.toDomain(row);
    final fields = _conversationFields(domainView);
    // Override is_deleted from the raw row — `_conversationFields` hard-codes
    // `false` (it's a "new state" emit), and the previous-side map must
    // carry the actual stored tombstone bit so a soft-delete diff doesn't
    // spuriously match `false`. The early-return on `existingRow.isDeleted`
    // makes this defensive; documenting the contract anyway.
    fields['is_deleted'] = row.isDeleted;
    return fields;
  }

  /// Build a sparse [db.ConversationsCompanion] from a patch map.
  ///
  /// [id] is required because the DAO's `updateConversation` asserts
  /// `companion.id.present`. [includesAllMembers] and [archivedForEveryone]
  /// are plumbed separately because they live outside the diff map
  /// (sparse-field carve-outs).
  db.ConversationsCompanion _partialConversationCompanion(
    String id,
    Map<String, dynamic> fields, {
    bool? includesAllMembers,
    bool? archivedForEveryone,
  }) {
    return db.ConversationsCompanion(
      id: Value(id),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      lastActivityAt: fields.containsKey('last_activity_at')
          ? Value(parseSyncDateTime(fields['last_activity_at']))
          : const Value.absent(),
      title: fields.containsKey('title')
          ? Value(fields['title'] as String?)
          : const Value.absent(),
      emoji: fields.containsKey('emoji')
          ? Value(fields['emoji'] as String?)
          : const Value.absent(),
      isDirectMessage: fields.containsKey('is_direct_message')
          ? Value(fields['is_direct_message'] as bool)
          : const Value.absent(),
      creatorId: fields.containsKey('creator_id')
          ? Value(fields['creator_id'] as String?)
          : const Value.absent(),
      participantIds: fields.containsKey('participant_ids')
          ? Value(fields['participant_ids'] as String)
          : const Value.absent(),
      archivedByMemberIds: fields.containsKey('archived_by_member_ids')
          ? Value(fields['archived_by_member_ids'] as String)
          : const Value.absent(),
      mutedByMemberIds: fields.containsKey('muted_by_member_ids')
          ? Value(fields['muted_by_member_ids'] as String)
          : const Value.absent(),
      lastReadTimestamps: fields.containsKey('last_read_timestamps')
          ? Value(fields['last_read_timestamps'] as String)
          : const Value.absent(),
      description: fields.containsKey('description')
          ? Value(fields['description'] as String?)
          : const Value.absent(),
      categoryId: fields.containsKey('category_id')
          ? Value(fields['category_id'] as String?)
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      includesAllMembers: includesAllMembers != null
          ? Value(includesAllMembers)
          : const Value.absent(),
      archivedForEveryone: archivedForEveryone != null
          ? Value(archivedForEveryone)
          : const Value.absent(),
    );
  }

  /// Field-map builder for conversation sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createConversation()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  ///
  /// **Note**: `includes_all_members` and `archived_for_everyone` are *not*
  /// included here. Each is sparse-emitted (only when `true`) directly by
  /// `createConversation` and its setter, and inline-emitted on transitions by
  /// `updateConversation`. See `_conversationFieldsFromRow` for the rationale.
  static Map<String, dynamic> conversationFields(domain.Conversation c) {
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
