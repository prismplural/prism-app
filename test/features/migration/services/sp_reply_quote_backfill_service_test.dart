import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/migration/services/sp_reply_quote_backfill_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _insertMessage(
  AppDatabase db, {
  required String id,
  required String content,
  String conversationId = 'conv-1',
  String? authorId,
  String? replyToId,
  String? replyToAuthorId,
  String? replyToContent,
  DateTime? timestamp,
  bool isDeleted = false,
}) async {
  await db.chatMessagesDao.insertMessage(
    ChatMessagesCompanion.insert(
      id: id,
      content: content,
      timestamp: timestamp ?? DateTime.utc(2025, 1, 1, 12),
      conversationId: conversationId,
      authorId: Value(authorId),
      replyToId: Value(replyToId),
      replyToAuthorId: Value(replyToAuthorId),
      replyToContent: Value(replyToContent),
      isDeleted: Value(isDeleted),
    ),
  );
}

void main() {
  late AppDatabase db;
  late SpReplyQuoteBackfillService service;

  setUp(() {
    db = _makeDb();
    service = SpReplyQuoteBackfillService(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('repairs imported replies with missing quote snapshots', () async {
    await _insertMessage(
      db,
      id: 'original',
      content: 'Original message',
      authorId: 'member-a',
    );
    await _insertMessage(
      db,
      id: 'reply',
      content: 'Reply message',
      authorId: 'member-b',
      replyToId: 'original',
    );

    expect(await SpReplyQuoteBackfillService.hasCandidates(db), isTrue);

    final result = await service.run();
    expect(result.messagesRepaired, 1);

    final reply = await db.chatMessagesDao.getMessageById('reply');
    expect(reply!.replyToId, 'original');
    expect(reply.replyToAuthorId, 'member-a');
    expect(reply.replyToContent, 'Original message');
    expect(await SpReplyQuoteBackfillService.hasCandidates(db), isFalse);
  });

  test('is idempotent after a reply has been repaired', () async {
    await _insertMessage(
      db,
      id: 'original',
      content: 'Original message',
      authorId: 'member-a',
    );
    await _insertMessage(
      db,
      id: 'reply',
      content: 'Reply message',
      authorId: 'member-b',
      replyToId: 'original',
    );

    expect((await service.run()).messagesRepaired, 1);
    expect((await service.run()).messagesRepaired, 0);
  });

  test('repairs newest replies first when batch-limited', () async {
    await _insertMessage(
      db,
      id: 'old-original',
      content: 'Old original',
      authorId: 'member-a',
      timestamp: DateTime.utc(2025, 1, 1, 10),
    );
    await _insertMessage(
      db,
      id: 'old-reply',
      content: 'Old reply',
      authorId: 'member-b',
      replyToId: 'old-original',
      timestamp: DateTime.utc(2025, 1, 1, 11),
    );
    await _insertMessage(
      db,
      id: 'new-original',
      content: 'New original',
      authorId: 'member-c',
      timestamp: DateTime.utc(2025, 1, 2, 10),
    );
    await _insertMessage(
      db,
      id: 'new-reply',
      content: 'New reply',
      authorId: 'member-d',
      replyToId: 'new-original',
      timestamp: DateTime.utc(2025, 1, 2, 11),
    );

    final firstBatch = await service.run(
      batchSize: 1,
      maxBatches: 1,
      interBatchDelay: Duration.zero,
    );
    expect(firstBatch.messagesRepaired, 1);
    expect(firstBatch.batchesProcessed, 1);
    expect(firstBatch.hasRemainingCandidates, isTrue);

    final newReply = await db.chatMessagesDao.getMessageById('new-reply');
    final oldReply = await db.chatMessagesDao.getMessageById('old-reply');
    expect(newReply!.replyToContent, 'New original');
    expect(newReply.replyToAuthorId, 'member-c');
    expect(oldReply!.replyToContent, isNull);

    final secondBatch = await service.run(
      batchSize: 1,
      interBatchDelay: Duration.zero,
    );
    expect(secondBatch.messagesRepaired, 1);
    expect(secondBatch.hasRemainingCandidates, isFalse);
    expect(await SpReplyQuoteBackfillService.hasCandidates(db), isFalse);
  });

  test('does not repair replies whose parent is missing or deleted', () async {
    await _insertMessage(
      db,
      id: 'deleted-parent',
      content: 'Deleted parent',
      authorId: 'member-a',
      isDeleted: true,
    );
    await _insertMessage(
      db,
      id: 'reply-to-missing',
      content: 'Reply message',
      authorId: 'member-b',
      replyToId: 'missing-parent',
    );
    await _insertMessage(
      db,
      id: 'reply-to-deleted',
      content: 'Reply message',
      authorId: 'member-b',
      replyToId: 'deleted-parent',
    );

    final result = await service.run();
    expect(result.messagesRepaired, 0);

    final missing = await db.chatMessagesDao.getMessageById('reply-to-missing');
    final deleted = await db.chatMessagesDao.getMessageById('reply-to-deleted');
    expect(missing!.replyToContent, isNull);
    expect(deleted!.replyToContent, isNull);
  });

  test(
    'does not overwrite existing quoted content when only author is missing',
    () async {
      await _insertMessage(
        db,
        id: 'original',
        content: 'Edited parent content',
        authorId: 'member-a',
      );
      await _insertMessage(
        db,
        id: 'reply',
        content: 'Reply message',
        authorId: 'member-b',
        replyToId: 'original',
        replyToContent: 'Original snapshot',
      );

      final result = await service.run();
      expect(result.messagesRepaired, 1);

      final reply = await db.chatMessagesDao.getMessageById('reply');
      expect(reply!.replyToAuthorId, 'member-a');
      expect(reply.replyToContent, 'Original snapshot');
    },
  );
}
