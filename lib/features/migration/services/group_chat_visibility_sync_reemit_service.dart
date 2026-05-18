import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';

typedef GroupChatVisibilityRecordUpdate =
    Future<void> Function({
      required String table,
      required String entityId,
      required Map<String, dynamic> fields,
    });

class GroupChatVisibilitySyncReemitResult {
  const GroupChatVisibilitySyncReemitResult({
    this.conversationsReemitted = 0,
    this.alreadyCompleted = false,
    this.error,
  });

  final int conversationsReemitted;
  final bool alreadyCompleted;
  final String? error;

  bool get hasError => error != null;
}

class GroupChatVisibilitySyncReemitService {
  const GroupChatVisibilitySyncReemitService({
    required AppDatabase db,
    required GroupChatVisibilityRecordUpdate recordUpdate,
    SharedPreferences? preferences,
  }) : _db = db,
       _recordUpdate = recordUpdate,
       _preferences = preferences;

  static const flagKey = 'sync.group_chat_visibility_reemit_v1';
  static const _conversationTable = 'conversations';

  final AppDatabase _db;
  final GroupChatVisibilityRecordUpdate _recordUpdate;
  final SharedPreferences? _preferences;

  static Future<bool> hasCandidates(AppDatabase db) async {
    final rows = await db
        .customSelect(
          '''
          SELECT 1
          FROM conversations
          WHERE is_direct_message = 0
            AND is_deleted = 0
            AND includes_all_members = 1
          LIMIT 1
          ''',
          readsFrom: {db.conversations},
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<GroupChatVisibilitySyncReemitResult> runOnce() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) == true) {
      return const GroupChatVisibilitySyncReemitResult(alreadyCompleted: true);
    }

    try {
      final candidates = await _loadCandidates();
      var emitted = 0;

      for (final candidate in candidates) {
        await _recordUpdate(
          table: _conversationTable,
          entityId: candidate.id,
          fields: candidate.syncFields,
        );
        emitted++;
      }

      await prefs.setBool(flagKey, true);
      if (emitted > 0) {
        debugPrint(
          '[CHAT_VISIBILITY_SYNC] Re-emitted $emitted group visibility flag(s).',
        );
      }
      return GroupChatVisibilitySyncReemitResult(
        conversationsReemitted: emitted,
      );
    } catch (error) {
      debugPrint('[CHAT_VISIBILITY_SYNC] re-emit failed: $error');
      return GroupChatVisibilitySyncReemitResult(error: error.toString());
    }
  }

  Future<List<_GroupChatVisibilityCandidate>> _loadCandidates() async {
    final rows = await _db
        .customSelect(
          '''
          SELECT id, creator_id, participant_ids
          FROM conversations
          WHERE is_direct_message = 0
            AND is_deleted = 0
            AND includes_all_members = 1
          ORDER BY id ASC
          ''',
          readsFrom: {_db.conversations},
        )
        .get();

    return rows
        .map(
          (row) => _GroupChatVisibilityCandidate(
            id: row.read<String>('id'),
            creatorId: row.readNullable<String>('creator_id'),
            participantIdsJson: row.read<String>('participant_ids'),
          ),
        )
        .toList(growable: false);
  }
}

class _GroupChatVisibilityCandidate {
  const _GroupChatVisibilityCandidate({
    required this.id,
    required this.creatorId,
    required this.participantIdsJson,
  });

  final String id;
  final String? creatorId;
  final String participantIdsJson;

  Map<String, dynamic> get syncFields {
    final fields = <String, dynamic>{'includes_all_members': true};
    if (_hasSingleCreatorParticipant) {
      fields['creator_id'] = creatorId;
      fields['participant_ids'] = participantIdsJson;
    }
    return fields;
  }

  bool get _hasSingleCreatorParticipant {
    final creator = creatorId;
    if (creator == null || creator.isEmpty) return false;

    final Object? decoded;
    try {
      decoded = jsonDecode(participantIdsJson);
    } on FormatException {
      return false;
    }
    if (decoded is! List || decoded.length != 1) return false;
    return decoded.single == creator;
  }
}
