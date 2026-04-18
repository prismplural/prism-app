/// Integration test against a real .prism export file.
///
/// Requires: REDACTED_EXPORT_PATH
/// Skips automatically if the file is not present (safe for CI).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Habit, HabitCompletion, Member;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

const _exportPath = 'REDACTED_EXPORT_PATH';
const _exportPassword = 'REDACTED_TEST_PASSWORD';

final _fileExists = File(_exportPath).existsSync();
final _skip = _fileExists ? null : 'export file not found: $_exportPath';

DataImportService _makeImport(AppDatabase db, Directory cacheDir) =>
    DataImportService(
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
      chatMessageRepository: DriftChatMessageRepository(
        db.chatMessagesDao,
        null,
      ),
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
      memberGroupsRepository: DriftMemberGroupsRepository(
        db.memberGroupsDao,
        null,
      ),
      customFieldsRepository: DriftCustomFieldsRepository(
        db.customFieldsDao,
        null,
      ),
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
      appSupportDirectoryProvider: () async => cacheDir,
    );

void main() {
  group('real .prism export import', () {
    late AppDatabase db;
    late Directory cacheDir;
    late DataImportService importService;

    setUp(() async {
      if (!_fileExists) return;
      db = AppDatabase(NativeDatabase.memory());
      cacheDir = await Directory.systemTemp.createTemp('prism_import_test_');
      importService = _makeImport(db, cacheDir);
    });

    tearDown(() async {
      if (!_fileExists) return;
      await db.close();
      await cacheDir.delete(recursive: true);
    });

    test('decrypts successfully', () {
      final bytes = File(_exportPath).readAsBytesSync();
      final resolved = DataImportService.resolveBytes(
        bytes,
        password: _exportPassword,
      );
      expect(resolved.json, isNotEmpty);
      expect(resolved.mediaBlobs, hasLength(6));
    }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));

    test('imports all records with correct counts', () async {
      final bytes = File(_exportPath).readAsBytesSync();
      final resolved = DataImportService.resolveBytes(
        bytes,
        password: _exportPassword,
      );
      final result = await importService.importData(
        resolved.json,
        mediaBlobs: resolved.mediaBlobs,
      );

      expect(result.membersCreated, 8);
      expect(result.frontSessionsCreated, 109);
      expect(result.sleepSessionsCreated, 1);
      expect(result.conversationsCreated, 5);
      expect(result.messagesCreated, 139);
      expect(result.pollsCreated, 2);
      expect(result.pollOptionsCreated, 7);
      expect(result.habitsCreated, 2);
      expect(result.habitCompletionsCreated, 21);
      expect(result.notesCreated, 2);
      expect(result.mediaAttachmentsCreated, 13);
    }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));

    test('media blobs cached to disk', () async {
      final bytes = File(_exportPath).readAsBytesSync();
      final resolved = DataImportService.resolveBytes(
        bytes,
        password: _exportPassword,
      );
      await importService.importData(
        resolved.json,
        mediaBlobs: resolved.mediaBlobs,
      );

      final mediaDir = Directory('${cacheDir.path}/prism_media');
      expect(mediaDir.existsSync(), isTrue);
      final cached = mediaDir.listSync().whereType<File>().toList();
      expect(cached, hasLength(6));
    }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));

    test('idempotent: second import creates zero duplicates', () async {
      final bytes = File(_exportPath).readAsBytesSync();
      final resolved = DataImportService.resolveBytes(
        bytes,
        password: _exportPassword,
      );
      await importService.importData(
        resolved.json,
        mediaBlobs: resolved.mediaBlobs,
      );
      final result2 = await importService.importData(
        resolved.json,
        mediaBlobs: resolved.mediaBlobs,
      );

      expect(result2.membersCreated, 0);
      expect(result2.frontSessionsCreated, 0);
      expect(result2.messagesCreated, 0);
      expect(result2.mediaAttachmentsCreated, 0);
    }, skip: _skip, timeout: const Timeout(Duration(minutes: 3)));
  });
}
