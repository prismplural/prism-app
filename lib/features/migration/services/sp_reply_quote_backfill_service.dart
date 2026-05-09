import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

class SpReplyQuoteBackfillResult {
  const SpReplyQuoteBackfillResult({required this.messagesRepaired});

  final int messagesRepaired;
}

class SpReplyQuoteBackfillService with SyncRecordMixin {
  SpReplyQuoteBackfillService({
    required AppDatabase db,
    ffi.PrismSyncHandle? syncHandle,
  }) : _db = db,
       _syncHandle = syncHandle;

  static const _syncTable = 'chat_messages';

  final AppDatabase _db;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static Future<bool> hasCandidates(AppDatabase db) async {
    final rows = await db
        .customSelect(
          '''
      SELECT 1
      FROM chat_messages AS child
      INNER JOIN chat_messages AS parent
        ON parent.id = child.reply_to_id
      WHERE child.is_deleted = 0
        AND parent.is_deleted = 0
        AND child.reply_to_id IS NOT NULL
        AND (
          child.reply_to_content IS NULL
          OR (
            child.reply_to_author_id IS NULL
            AND parent.author_id IS NOT NULL
          )
        )
      LIMIT 1
      ''',
          readsFrom: {db.chatMessages},
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<SpReplyQuoteBackfillResult> run() async {
    final candidates = await _loadCandidates();
    if (candidates.isEmpty) {
      debugPrint('[SP_REPLY_BACKFILL] No candidate replies found.');
      return const SpReplyQuoteBackfillResult(messagesRepaired: 0);
    }

    final syncUpdates = <_ReplyQuoteSyncUpdate>[];
    var repaired = 0;

    await _db.transaction(() async {
      for (final candidate in candidates) {
        final changes = <String, dynamic>{};
        final shouldSetContent = candidate.currentReplyToContent == null;
        final shouldSetAuthor =
            candidate.currentReplyToAuthorId == null &&
            candidate.parentAuthorId != null;

        if (shouldSetContent) {
          changes['reply_to_content'] = candidate.parentContent;
        }
        if (shouldSetAuthor) {
          changes['reply_to_author_id'] = candidate.parentAuthorId;
        }
        if (changes.isEmpty) continue;

        await _db.chatMessagesDao.updateMessage(
          ChatMessagesCompanion(
            id: Value(candidate.messageId),
            replyToAuthorId: shouldSetAuthor
                ? Value(candidate.parentAuthorId)
                : const Value.absent(),
            replyToContent: shouldSetContent
                ? Value(candidate.parentContent)
                : const Value.absent(),
          ),
        );

        syncUpdates.add(
          _ReplyQuoteSyncUpdate(
            messageId: candidate.messageId,
            fields: changes,
          ),
        );
        repaired++;
      }
    });

    for (final update in syncUpdates) {
      await syncRecordUpdate(_syncTable, update.messageId, update.fields);
    }

    debugPrint(
      '[SP_REPLY_BACKFILL] Repaired $repaired message reply quote(s).',
    );
    return SpReplyQuoteBackfillResult(messagesRepaired: repaired);
  }

  Future<List<_ReplyQuoteCandidate>> _loadCandidates() async {
    final rows = await _db
        .customSelect(
          '''
      SELECT
        child.id AS message_id,
        child.reply_to_author_id AS current_reply_to_author_id,
        child.reply_to_content AS current_reply_to_content,
        parent.author_id AS parent_author_id,
        parent.content AS parent_content
      FROM chat_messages AS child
      INNER JOIN chat_messages AS parent
        ON parent.id = child.reply_to_id
      WHERE child.is_deleted = 0
        AND parent.is_deleted = 0
        AND child.reply_to_id IS NOT NULL
        AND (
          child.reply_to_content IS NULL
          OR (
            child.reply_to_author_id IS NULL
            AND parent.author_id IS NOT NULL
          )
        )
      ''',
          readsFrom: {_db.chatMessages},
        )
        .get();

    return rows
        .map((row) {
          return _ReplyQuoteCandidate(
            messageId: row.read<String>('message_id'),
            currentReplyToAuthorId: row.readNullable<String>(
              'current_reply_to_author_id',
            ),
            currentReplyToContent: row.readNullable<String>(
              'current_reply_to_content',
            ),
            parentAuthorId: row.readNullable<String>('parent_author_id'),
            parentContent: row.read<String>('parent_content'),
          );
        })
        .toList(growable: false);
  }
}

class _ReplyQuoteCandidate {
  const _ReplyQuoteCandidate({
    required this.messageId,
    required this.currentReplyToAuthorId,
    required this.currentReplyToContent,
    required this.parentAuthorId,
    required this.parentContent,
  });

  final String messageId;
  final String? currentReplyToAuthorId;
  final String? currentReplyToContent;
  final String? parentAuthorId;
  final String parentContent;
}

class _ReplyQuoteSyncUpdate {
  const _ReplyQuoteSyncUpdate({required this.messageId, required this.fields});

  final String messageId;
  final Map<String, dynamic> fields;
}
