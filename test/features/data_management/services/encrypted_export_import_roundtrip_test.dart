import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Conversation, FrontingSession, Habit, HabitCompletion, Member;
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
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(
  AppDatabase db, {
  required Directory cacheDir,
  required Directory appSupportDir,
}) => DataExportService(
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
  mediaAttachmentsDao: db.mediaAttachmentsDao,
  cacheDirectoryProvider: () async => cacheDir,
  appSupportDirectoryProvider: () async => appSupportDir,
);

DataImportService _makeImport(
  AppDatabase db, {
  required Directory appSupportDir,
}) => DataImportService(
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
  appSupportDirectoryProvider: () async => appSupportDir,
);

void main() {
  group('generated encrypted .prism export/import roundtrip', () {
    late bool previousMultipleDbWarningSetting;
    late AppDatabase sourceDb;
    late AppDatabase targetDb;
    late Directory tempRoot;
    late Directory exportDir;
    late Directory sourceSupportDir;
    late Directory targetSupportDir;
    late DataExportService exportService;
    late DataImportService importService;

    setUpAll(() {
      previousMultipleDbWarningSetting =
          drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() {
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousMultipleDbWarningSetting;
    });

    setUp(() async {
      sourceDb = _makeDb();
      targetDb = _makeDb();
      tempRoot = await Directory.systemTemp.createTemp(
        'prism-encrypted-roundtrip-',
      );
      exportDir = Directory('${tempRoot.path}/exports')..createSync();
      sourceSupportDir = Directory('${tempRoot.path}/source_support')
        ..createSync();
      targetSupportDir = Directory('${tempRoot.path}/target_support')
        ..createSync();
      exportService = _makeExport(
        sourceDb,
        cacheDir: exportDir,
        appSupportDir: sourceSupportDir,
      );
      importService = _makeImport(targetDb, appSupportDir: targetSupportDir);
    });

    tearDown(() async {
      await sourceDb.close();
      await targetDb.close();
      await tempRoot.delete(recursive: true);
    });

    test(
      'exports encrypted file, decrypts it, imports data and media blobs',
      () async {
        const password = 'dummy-test-password';
        final now = DateTime.utc(2026, 5, 1, 10);

        final sourceSettingsRepo = DriftSystemSettingsRepository(
          sourceDb.systemSettingsDao,
          null,
        );
        await sourceSettingsRepo.getSettings();
        await sourceSettingsRepo.updateSettings(
          const SystemSettings(
            systemName: 'Encrypted Roundtrip',
            boardsEnabled: true,
            themeBrightness: ThemeBrightness.dark,
            cornerStyle: CornerStyle.angular,
            gifSearchEnabled: false,
          ),
        );

        await sourceDb.memberBoardPostsDao.createPost(
          MemberBoardPostsCompanion(
            id: const drift.Value('board-post-1'),
            targetMemberId: const drift.Value('member-target'),
            authorId: const drift.Value('member-author'),
            audience: const drift.Value('private'),
            title: const drift.Value('Encrypted path'),
            body: const drift.Value('This should survive the .prism path.'),
            createdAt: drift.Value(now),
            writtenAt: drift.Value(now.subtract(const Duration(hours: 1))),
            editedAt: const drift.Value(null),
            isDeleted: const drift.Value(false),
          ),
        );

        const mediaId = '11111111-1111-4111-8111-111111111111';
        final mediaBytes = Uint8List.fromList([1, 3, 5, 7, 9]);
        final sourceMediaDir = Directory('${sourceSupportDir.path}/prism_media')
          ..createSync();
        await File(
          '${sourceMediaDir.path}/$mediaId.enc',
        ).writeAsBytes(mediaBytes);
        await sourceDb.mediaAttachmentsDao.insertAttachment(
          const MediaAttachmentsCompanion(
            id: drift.Value('attachment-1'),
            messageId: drift.Value('message-1'),
            mediaId: drift.Value(mediaId),
            mediaType: drift.Value('image'),
            encryptionKeyB64: drift.Value('key'),
            contentHash: drift.Value('content-hash'),
            plaintextHash: drift.Value('plain-hash'),
            mimeType: drift.Value('image/png'),
            sizeBytes: drift.Value(5),
            width: drift.Value(10),
            height: drift.Value(20),
          ),
        );

        final file = await exportService.exportEncryptedData(
          password: password,
          targetDirectory: exportDir,
          fileName: 'generated.prism',
        );

        final encryptedBytes = await file.readAsBytes();
        expect(file.path, endsWith('generated.prism'));
        expect(ExportCrypto.isEncrypted(encryptedBytes), isTrue);

        final resolved = DataImportService.resolveBytes(
          encryptedBytes,
          password: password,
        );
        expect(resolved.mediaBlobs, hasLength(1));
        expect(resolved.mediaBlobs.single.mediaId, mediaId);
        expect(resolved.mediaBlobs.single.blob, mediaBytes);

        final preview = importService.parsePreview(resolved.json);
        expect(preview.systemSettings, 1);
        expect(preview.memberBoardPosts, 1);
        expect(preview.mediaAttachments, 1);

        final result = await importService.importData(
          resolved.json,
          mediaBlobs: resolved.mediaBlobs,
        );

        expect(result.settingsUpdated, isTrue);
        expect(result.memberBoardPostsCreated, 1);
        expect(result.mediaAttachmentsCreated, 1);

        final importedSettings = await DriftSystemSettingsRepository(
          targetDb.systemSettingsDao,
          null,
        ).getSettings();
        expect(importedSettings.systemName, 'Encrypted Roundtrip');
        expect(importedSettings.boardsEnabled, isTrue);
        expect(importedSettings.themeBrightness, ThemeBrightness.dark);
        expect(importedSettings.cornerStyle, CornerStyle.angular);
        expect(importedSettings.gifSearchEnabled, isFalse);

        final importedPosts = await targetDb
            .select(targetDb.memberBoardPosts)
            .get();
        expect(importedPosts, hasLength(1));
        expect(importedPosts.single.id, 'board-post-1');
        expect(importedPosts.single.audience, 'private');
        expect(
          importedPosts.single.body,
          'This should survive the .prism path.',
        );

        final importedAttachments = await targetDb.mediaAttachmentsDao.getAll();
        expect(importedAttachments, hasLength(1));
        expect(importedAttachments.single.id, 'attachment-1');
        expect(importedAttachments.single.mediaId, mediaId);

        final cachedMedia = File(
          '${targetSupportDir.path}/prism_media/$mediaId.enc',
        );
        expect(await cachedMedia.exists(), isTrue);
        expect(await cachedMedia.readAsBytes(), mediaBytes);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
