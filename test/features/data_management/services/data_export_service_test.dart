import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Habit, HabitCompletion;
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
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(
  AppDatabase db,
  Directory cacheDir,
) => DataExportService(
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
  appSupportDirectoryProvider: () async => cacheDir,
);

void main() {
  group('DataExportService', () {
    late AppDatabase db;
    late Directory cacheDir;
    late DataExportService exportService;

    setUp(() {
      db = _makeDb();
      cacheDir = Directory.systemTemp.createTempSync('prism-export-test-');
      exportService = _makeExport(db, cacheDir);
    });

    tearDown(() async {
      await db.close();
      await cacheDir.delete(recursive: true);
    });

    test('exportEncryptedData writes an encrypted .prism file', () async {
      final file = await exportService.exportEncryptedData(
        password: 'test-password',
      );

      expect(file.path, endsWith('.prism'));
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      expect(ExportCrypto.isEncrypted(bytes), isTrue);

      final json = ExportCrypto.decrypt(bytes, 'test-password').json;
      final export = jsonDecode(json) as Map<String, dynamic>;
      expect(export['appName'], 'Prism Plurality');
      expect(export['version'], '1.0');
    });

    test(
      'buildExport keeps sleep sessions separate from fronting sessions',
      () async {
        await exportService.frontingSessionRepository.createSession(
          FrontingSession(
            id: 'front-1',
            startTime: DateTime(2026, 3, 18, 10),
            memberId: 'member-1',
          ),
        );
        await exportService.frontingSessionRepository.createSession(
          FrontingSession(
            id: 'sleep-1',
            startTime: DateTime(2026, 3, 18, 22),
            endTime: DateTime(2026, 3, 19, 6),
            memberId: null,
            sessionType: SessionType.sleep,
            quality: SleepQuality.unknown,
            notes: 'nap',
          ),
        );

        final export = await exportService.buildExport();

        expect(export.frontSessions, hasLength(1));
        expect(export.sleepSessions, hasLength(1));
        expect(export.frontSessions.single.id, 'front-1');
        expect(export.sleepSessions.single.id, 'sleep-1');
      },
    );
  });
}
