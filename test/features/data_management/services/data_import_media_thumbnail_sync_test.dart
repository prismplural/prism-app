import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show debugDisposeOutboxDrainForTesting;
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataImportService _makeImport(AppDatabase db) => DataImportService(
  db: db,
  memberRepository: DriftMemberRepository(db.membersDao, null),
  frontingSessionRepository: DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
  ),
  conversationRepository: DriftConversationRepository(
    db.conversationsDao,
    null,
  ),
  chatMessageRepository: DriftChatMessageRepository(db.chatMessagesDao, null),
  pollRepository: DriftPollRepository(
    db.pollsDao,
    db.pollOptionsDao,
    db.pollVotesDao,
    null,
  ),
  systemSettingsRepository: DriftSystemSettingsRepository(
    db.systemSettingsDao,
    null,
  ),
  habitRepository: DriftHabitRepository(db.habitsDao, null),
  pluralKitSyncDao: db.pluralKitSyncDao,
  memberGroupsRepository: DriftMemberGroupsRepository(db.memberGroupsDao, null),
  customFieldsRepository: DriftCustomFieldsRepository(db.customFieldsDao, null),
  notesRepository: DriftNotesRepository(db.notesDao, null),
  frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
    db.frontSessionCommentsDao,
    null,
  ),
  conversationCategoriesRepository: DriftConversationCategoriesRepository(
    db.conversationCategoriesDao,
    null,
  ),
  remindersRepository: DriftRemindersRepository(db.remindersDao, null),
  friendsRepository: DriftFriendsRepository(db.friendsDao, null),
);

/// A import file with two restored media attachments:
///
/// * `att-thumb` carries a real thumbnail identity AND its crypto material —
///   the shape every image attachment created on a modern build has.
/// * `att-plain` has no thumbnail at all (legacy/URL-only shape); its three
///   thumbnail columns must stay empty end to end.
String _exportWithThumbnailHashes() {
  const now = '2026-01-15T10:00:00.000Z';
  return jsonEncode({
    'formatVersion': '1.0',
    'version': '1.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': 3,
    'headmates': [
      {
        'id': 'm-1',
        'name': 'Author',
        'isActive': true,
        'createdAt': now,
        'displayOrder': 0,
        'isAdmin': false,
        'customColorEnabled': false,
      },
    ],
    'frontSessions': [],
    'sleepSessions': [],
    'conversations': [
      {
        'id': 'conv-1',
        'createdAt': now,
        'lastActivityAt': now,
        'title': 'Chat',
        'type': 'group',
        'isDirectMessage': false,
        'participantIds': <String>[],
        'lastReadTimestamps': <String, dynamic>{},
      },
    ],
    'messages': [
      {
        'id': 'msg-1',
        'content': 'see attachment',
        'timestamp': now,
        'isSystemMessage': false,
        'authorId': 'm-1',
        'conversationId': 'conv-1',
      },
    ],
    'polls': [],
    'pollOptions': [],
    'systemSettings': [],
    'habits': [],
    'habitCompletions': [],
    'mediaAttachments': [
      {
        'id': 'att-thumb',
        'messageId': 'msg-1',
        'memberId': 'm-1',
        'tag': 'inline',
        'mediaId': 'media-1',
        'mediaType': 'image',
        'encryptionKeyB64': 'key-b64',
        'contentHash': 'chash',
        'plaintextHash': 'phash',
        'mimeType': 'image/webp',
        'sizeBytes': 1234,
        'width': 64,
        'height': 48,
        'blurhash': 'bh',
        'thumbnailMediaId': 'thumb-media-1',
        'thumbnailContentHash': 'thumb-cipher-hash',
        'thumbnailPlaintextHash': 'thumb-plaintext-hash',
        'sourceUrl': 'src',
        'previewUrl': 'prev',
        'isDeleted': false,
      },
      {
        'id': 'att-plain',
        'messageId': 'msg-1',
        'mediaId': '',
        'mediaType': 'image',
        'encryptionKeyB64': '',
        'contentHash': '',
        'plaintextHash': '',
        'mimeType': 'image/png',
        'sizeBytes': 0,
        'sourceUrl': 'https://example.invalid/pic.png',
        'previewUrl': '',
        'isDeleted': false,
      },
    ],
  });
}

void main() {
  // Restoring a media attachment inserts the Drift row directly, so the
  // importer has to emit the create op itself. That emission must carry the
  // SAME thumbnail crypto material the row holds: `MediaAttachment`'s
  // `@Default('')` silently substitutes empty strings for any field the
  // payload builder is not given, so a peer would persist `thumbnail_media_id`
  // with empty hashes while the importing device kept the real ones. That
  // half-populated shape is what stops thumbnail healing (the hydrator skips
  // rows with an empty hash) and makes a PluralPort export fabricate a
  // dangling thumbnail asset.
  group('DataImportService restores media thumbnail crypto material', () {
    late AppDatabase db;
    late DataImportService importService;

    setUp(() {
      db = _makeDb();
      importService = _makeImport(db);
      // Paired device, so the captured emissions are persisted to the outbox
      // where this test can read the exact wire payload.
      syncCredentialsPersisted.value = true;
    });

    tearDown(() async {
      syncCredentialsPersisted.value = false;
      syncCurrentHandle.value = null;
      debugDisposeOutboxDrainForTesting();
      await db.close();
    });

    Future<Map<String, Object?>> outboxFieldsFor(String entityId) async {
      final rows = await db.syncOutboxDao.allInIdOrder();
      final row = rows.singleWhere(
        (r) => r.entityTable == 'media_attachments' && r.entityId == entityId,
      );
      expect(row.opType, 'create');
      return jsonDecode(row.fieldsJson) as Map<String, Object?>;
    }

    test(
      'thumbnail hashes in the emitted create op equal the inserted row',
      () async {
        final result = await importService.importData(
          _exportWithThumbnailHashes(),
        );
        expect(result.mediaAttachmentsCreated, 2);

        // The row is restored with the full thumbnail identity + material.
        final restored = await db.mediaAttachmentsDao.getById('att-thumb');
        expect(restored, isNotNull);
        final row = restored!;
        expect(row.thumbnailMediaId, 'thumb-media-1');
        expect(row.thumbnailContentHash, 'thumb-cipher-hash');
        expect(row.thumbnailPlaintextHash, 'thumb-plaintext-hash');

        final fields = await outboxFieldsFor('att-thumb');
        // Regression: these were '' because the payload builder was handed a
        // `MediaAttachment` without the two hash arguments, whose defaults are
        // empty. The local row was already correct, so only the wire payload
        // (and every peer that applied it) lost the material.
        expect(fields['thumbnail_media_id'], 'thumb-media-1');
        expect(fields['thumbnail_content_hash'], 'thumb-cipher-hash');
        expect(fields['thumbnail_plaintext_hash'], 'thumb-plaintext-hash');

        // The record id travels outside fieldsJson; the payload preserves the
        // media identity that the hashes belong to for verification/hydration.
        expect(fields['media_id'], row.mediaId);
      },
    );

    test('an attachment with no thumbnail stays empty on the wire', () async {
      await importService.importData(_exportWithThumbnailHashes());

      final restored = await db.mediaAttachmentsDao.getById('att-plain');
      expect(restored, isNotNull);
      final row = restored!;
      expect(row.thumbnailMediaId, '');
      expect(row.thumbnailContentHash, '');
      expect(row.thumbnailPlaintextHash, '');

      final fields = await outboxFieldsFor('att-plain');
      // Absence is carried by the shared builder as empty values (it always
      // emits the keys, exactly like a repository-created row). This pins that
      // the fix supplies the row's values rather than inventing or omitting
      // anything for attachments that never had a thumbnail.
      expect(fields.containsKey('thumbnail_content_hash'), isTrue);
      expect(fields.containsKey('thumbnail_plaintext_hash'), isTrue);
      expect(fields['thumbnail_media_id'], '');
      expect(fields['thumbnail_content_hash'], '');
      expect(fields['thumbnail_plaintext_hash'], '');
      expect(fields['media_id'], row.mediaId);
    });
  });
}
