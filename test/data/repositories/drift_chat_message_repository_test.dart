// test/data/repositories/drift_chat_message_repository_test.dart
//
// Patch-style `updateMessage` (item #5 of the drift-repo migration plan,
// `docs/plans/2026-05-25-drift-repo-patch-update-migration.md`).
//
// Asserts that `updateMessage` emits only changed fields, no-ops on
// unchanged input, refuses tombstoned / missing rows, and never emits
// `is_deleted` through the diff path. The `reactions` column is an
// *ordered* JSON list (display order / time-of-reaction sequence), so
// these tests do not assert canonicalization on it.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/message_reaction.dart';

void main() {
  late AppDatabase db;
  late ChatMessagesDao dao;
  late DriftChatMessageRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ChatMessagesDao(db);
    // Null sync handle — repository code uses the capture sink in tests.
    repo = DriftChatMessageRepository(dao, null);
  });

  tearDown(() => db.close());

  group('updateMessage (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    domain.ChatMessage makeMessage({
      String id = 'm1',
      String content = 'Original content',
      DateTime? timestamp,
      bool isSystemMessage = false,
      DateTime? editedAt,
      String? authorId = 'author-1',
      String conversationId = 'conv-1',
      List<MessageReaction> reactions = const [],
      String? replyToId,
      String? replyToAuthorId,
      String? replyToContent,
    }) {
      return domain.ChatMessage(
        id: id,
        content: content,
        timestamp: timestamp ?? baseTime,
        isSystemMessage: isSystemMessage,
        editedAt: editedAt,
        authorId: authorId,
        conversationId: conversationId,
        reactions: reactions,
        replyToId: replyToId,
        replyToAuthorId: replyToAuthorId,
        replyToContent: replyToContent,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createMessage(makeMessage());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMessage(makeMessage(content: 'Updated content'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'chat_messages');
      expect(captured.single.entityId, 'm1');
      expect(captured.single.fields.keys.toSet(), {'content'});
      expect(captured.single.fields['content'], 'Updated content');
      expect(captured.single.fields['is_deleted'], isNull);
    });

    test(
      'emits nothing when the domain object matches the stored row',
      () async {
        await repo.createMessage(makeMessage());
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateMessage(makeMessage());

        expect(captured, isEmpty);
      },
    );

    test('preserves untouched columns in the database', () async {
      await repo.createMessage(
        makeMessage(
          authorId: 'author-1',
          replyToId: 'parent-1',
          replyToAuthorId: 'author-0',
          replyToContent: 'Parent text',
        ),
      );

      await repo.updateMessage(
        makeMessage(
          content: 'Updated content',
          authorId: 'author-1',
          replyToId: 'parent-1',
          replyToAuthorId: 'author-0',
          replyToContent: 'Parent text',
        ),
      );

      final row = await dao.getMessageById('m1');
      expect(row, isNotNull);
      expect(row!.content, 'Updated content');
      expect(row.authorId, 'author-1');
      expect(row.conversationId, 'conv-1');
      expect(row.replyToId, 'parent-1');
      expect(row.replyToAuthorId, 'author-0');
      expect(row.replyToContent, 'Parent text');
      expect(row.isSystemMessage, isFalse);
      expect(row.isDeleted, isFalse);
    });

    test(
      'null-clearing emits the null and writes it to the database',
      () async {
        final editedTime = baseTime.add(const Duration(minutes: 5));
        await repo.createMessage(makeMessage(editedAt: editedTime));

        // Sanity: created row stores the editedAt value.
        final beforeRow = await dao.getMessageById('m1');
        expect(beforeRow!.editedAt, isNotNull);

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateMessage(makeMessage(editedAt: null));

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.containsKey('edited_at'), isTrue);
        expect(patch['edited_at'], isNull);

        final row = await dao.getMessageById('m1');
        expect(row!.editedAt, isNull);
      },
    );

    test('silently no-ops on a tombstoned row (does not emit, '
        'does not resurrect)', () async {
      await repo.createMessage(makeMessage());
      await repo.deleteMessage('m1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMessage(makeMessage(content: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await dao.getMessageById('m1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.content, 'Original content');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMessage(makeMessage(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getMessageById('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.createMessage(makeMessage());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMessage(makeMessage(content: 'Updated content'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test(
      'deleteMessage tombstones message attachments and syncs deletes',
      () async {
        await repo.createMessage(makeMessage());
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: 'att-1',
                messageId: const Value('m1'),
                mediaId: const Value('media-1'),
                mediaType: const Value('image'),
              ),
            );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.deleteMessage('m1');

        final message = await dao.getMessageById('m1');
        final attachment = await db.mediaAttachmentsDao.getById('att-1');
        final chatMedia = await db.mediaAttachmentsDao
            .watchAllChatMedia()
            .first;
        expect(message!.isDeleted, isTrue);
        expect(attachment!.isDeleted, isTrue);
        expect(chatMedia, isEmpty);
        expect(
          captured.map((op) => (op.table, op.entityId, op.opType)).toList(),
          [
            ('chat_messages', 'm1', SyncRecordOpType.delete),
            ('media_attachments', 'att-1', SyncRecordOpType.delete),
          ],
        );
      },
    );

    test(
      'deleteMessage ignores empty ids without tombstoning sentinel media',
      () async {
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: 'att-bio',
                messageId: const Value(''),
                memberId: const Value('member-1'),
                mediaId: const Value('media-bio'),
                mediaType: const Value('image'),
              ),
            );
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: 'att-library',
                messageId: const Value(''),
                tag: const Value('logo'),
                mediaId: const Value('media-library'),
                mediaType: const Value('image'),
              ),
            );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.deleteMessage('');

        final bio = await db.mediaAttachmentsDao.getById('att-bio');
        final library = await db.mediaAttachmentsDao.getById('att-library');
        expect(bio!.isDeleted, isFalse);
        expect(library!.isDeleted, isFalse);
        expect(captured, isEmpty);
      },
    );

    test(
      'deleteMessage does not tombstone orphan attachments for missing ids',
      () async {
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: 'att-orphan',
                messageId: const Value('missing-message'),
                mediaId: const Value('media-orphan'),
                mediaType: const Value('image'),
              ),
            );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.deleteMessage('missing-message');

        final orphan = await db.mediaAttachmentsDao.getById('att-orphan');
        expect(orphan!.isDeleted, isFalse);
        expect(captured, isEmpty);
      },
    );

    test(
      'deleteMessage cleans up attachments for already-deleted messages',
      () async {
        await repo.createMessage(makeMessage());
        await dao.softDeleteMessage('m1');
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: 'att-stale-child',
                messageId: const Value('m1'),
                mediaId: const Value('media-stale-child'),
                mediaType: const Value('image'),
              ),
            );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.deleteMessage('m1');

        final attachment = await db.mediaAttachmentsDao.getById(
          'att-stale-child',
        );
        expect(attachment!.isDeleted, isTrue);
        expect(
          captured.map((op) => (op.table, op.entityId, op.opType)).toList(),
          [('media_attachments', 'att-stale-child', SyncRecordOpType.delete)],
        );
      },
    );

    test('deleteMessage tombstones every attachment for the message', () async {
      await repo.createMessage(makeMessage());
      for (final id in ['att-1', 'att-2']) {
        await db
            .into(db.mediaAttachments)
            .insert(
              MediaAttachmentsCompanion.insert(
                id: id,
                messageId: const Value('m1'),
                mediaId: Value('media-$id'),
                mediaType: const Value('image'),
              ),
            );
      }

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.deleteMessage('m1');

      final first = await db.mediaAttachmentsDao.getById('att-1');
      final second = await db.mediaAttachmentsDao.getById('att-2');
      expect(first!.isDeleted, isTrue);
      expect(second!.isDeleted, isTrue);
      expect(
        captured.map((op) => (op.table, op.entityId, op.opType)).toList(),
        [
          ('chat_messages', 'm1', SyncRecordOpType.delete),
          ('media_attachments', 'att-1', SyncRecordOpType.delete),
          ('media_attachments', 'att-2', SyncRecordOpType.delete),
        ],
      );
    });

    test('watchAllChatMedia hides stale media for deleted messages', () async {
      await repo.createMessage(makeMessage());
      await db
          .into(db.mediaAttachments)
          .insert(
            MediaAttachmentsCompanion.insert(
              id: 'att-stale',
              messageId: const Value('m1'),
              mediaId: const Value('media-stale'),
              mediaType: const Value('image'),
            ),
          );
      await dao.softDeleteMessage('m1');

      final chatMedia = await db.mediaAttachmentsDao.watchAllChatMedia().first;

      expect(chatMedia, isEmpty);
    });

    test('watchAllChatMedia preserves orphan attachment visibility', () async {
      await db
          .into(db.mediaAttachments)
          .insert(
            MediaAttachmentsCompanion.insert(
              id: 'att-orphan',
              messageId: const Value('missing-message'),
              mediaId: const Value('media-orphan'),
              mediaType: const Value('image'),
            ),
          );

      final chatMedia = await db.mediaAttachmentsDao.watchAllChatMedia().first;

      expect(chatMedia.map((a) => a.id), ['att-orphan']);
    });

    test('reordering reactions produces a reactions patch (order is '
        'semantically meaningful)', () async {
      final r1 = MessageReaction(
        id: 'r1',
        emoji: 'thumbs_up',
        memberId: 'member-1',
        timestamp: baseTime,
      );
      final r2 = MessageReaction(
        id: 'r2',
        emoji: 'heart',
        memberId: 'member-2',
        timestamp: baseTime.add(const Duration(seconds: 1)),
      );

      await repo.createMessage(makeMessage(reactions: [r1, r2]));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Same elements, swapped order — must show up as a reactions edit
      // because order is semantically meaningful (display order).
      await repo.updateMessage(makeMessage(reactions: [r2, r1]));

      expect(captured, hasLength(1));
      expect(captured.single.fields.keys.toSet().contains('reactions'), isTrue);
      final reactionsPatch = captured.single.fields['reactions'] as String;
      final decoded = (jsonDecode(reactionsPatch) as List)
          .map((e) => (e as Map<String, dynamic>)['id'])
          .toList();
      expect(decoded, ['r2', 'r1']);
    });
  });
}
