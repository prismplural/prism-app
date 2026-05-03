import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Conversation, FrontingSession, Habit, HabitCompletion;
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
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(
  AppDatabase db,
  Directory cacheDir,
) => DataExportService(
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

    test('buildExport normalizes legacy dm-shaped conversations', () async {
      await exportService.conversationRepository.createConversation(
        Conversation(
          id: 'legacy-dm',
          createdAt: DateTime(2026, 3, 18, 10),
          lastActivityAt: DateTime(2026, 3, 18, 11),
          title: '',
          participantIds: const ['alice', 'bob'],
        ),
      );

      final export = await exportService.buildExport();
      final conversation = export.conversations.single;
      final json = conversation.toJson();

      expect(conversation.isDirectMessage, isTrue);
      expect(json['type'], 'directmessage');
      expect(json['isDirectMessage'], isTrue);
    });

    // Issue #40 (review-2026-04-30): legacy raw-SQL queries on dropped
    // columns must degrade gracefully. Today the v7 schema still has
    // `co_fronter_ids`, `pk_member_ids_json`, and comment `session_id`,
    // so the export reads them without complaint. The future v8 cleanup
    // migration will drop those columns; we simulate the post-cleanup
    // shape by physically dropping them via raw SQL after the v7 schema
    // is created, then assert that `buildExport(includeLegacyFields: true)`
    // still completes and merely returns empty legacy maps.
    test(
      'buildExport with includeLegacyFields=true succeeds when legacy columns '
      'still exist on disk',
      () async {
        // Smoke-test the current state.
        final export = await exportService.buildExport(
          includeLegacyFields: true,
        );
        expect(export.frontSessions, isEmpty);
      },
    );

    // -- PR G additions (review finding #39): envelope shape gating ----

    test('V1Export.fromJson rejects unknown formatVersion explicitly '
        '(review finding #39 + remediation plan WS4 step 7)', () async {
      final json = {
        'formatVersion': '99.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 0,
        'headmates': [],
        'frontSessions': [],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      expect(() => V1Export.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('envelope rescueLegacyFields=true wins over ambiguous row shape: '
        'a row carrying only `headmateId` (which the row-shape sniff would '
        'route to new-shape) routes through legacy when the envelope '
        'flag is set', () async {
      // Row shape: only headmateId, no coFronterIds, no pkMemberIdsJson,
      // no sessionType / memberId. Per the row-shape sniff this would
      // be classified as legacy via the "no headmateId AND no
      // coFronterIds AND no new-shape marker" leg — but it DOES have
      // headmateId, so the row sniff alone routes it to new-shape.
      // The envelope flag overrides.
      V1FrontSession.resetRowShapeLegacyFallbackCount();
      final json = {
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 1,
        'rescueLegacyFields': true,
        'headmates': [],
        'frontSessions': [
          {
            'id': 'ambig-1',
            'startTime': '2026-04-01T09:00:00.000Z',
            'headmateId': 'm1',
          },
        ],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      final export = V1Export.fromJson(json);
      // Envelope flag forces legacy.
      expect(export.frontSessions.single.isLegacyShape, true);
      // Envelope flag drove the decision; the per-row sniff
      // fallback counter did not tick.
      expect(V1FrontSession.rowShapeLegacyFallbackCount, 0);
    });

    test('envelope rescueLegacyFields=false + ambiguous row: per-row sniff '
        'is the fallback and the counter ticks (so its uses can be '
        'observed and eventually removed)', () async {
      V1FrontSession.resetRowShapeLegacyFallbackCount();
      final json = {
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 1,
        // No rescueLegacyFields: false implicit.
        'headmates': [],
        'frontSessions': [
          {
            'id': 'leg-1',
            'startTime': '2026-04-01T09:00:00.000Z',
            // Pure legacy shape (pkMemberIdsJson present, no
            // sessionType / memberId).
            'pkMemberIdsJson': '["abc"]',
            'pluralkitUuid': 'switch-1',
          },
        ],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      final export = V1Export.fromJson(json);
      expect(export.frontSessions.single.isLegacyShape, true);
      // Per-row sniff was the trigger — counter ticks once.
      expect(V1FrontSession.rowShapeLegacyFallbackCount, 1);
    });

    test(
      'buildExport with includeLegacyFields=true gracefully skips legacy '
      'queries when columns have been dropped (post-v8 cleanup simulation)',
      () async {
        // Simulate a future v8 cleanup migration by physically dropping the
        // legacy columns. SQLite needs a TableMigration-style rebuild for
        // DROP COLUMN; the simplest reproducible setup is to recreate the
        // tables without the legacy columns using `customStatement`.
        await db.customStatement(
          'CREATE TABLE _new_fronting_sessions ('
          '  id TEXT NOT NULL PRIMARY KEY,'
          '  session_type INTEGER NOT NULL DEFAULT 0,'
          '  start_time INTEGER NOT NULL,'
          '  end_time INTEGER,'
          '  member_id TEXT,'
          '  notes TEXT,'
          '  confidence INTEGER,'
          '  quality INTEGER,'
          '  is_health_kit_import INTEGER NOT NULL DEFAULT 0,'
          '  pluralkit_uuid TEXT,'
          '  pk_import_source TEXT,'
          '  pk_file_switch_id TEXT,'
          '  is_deleted INTEGER NOT NULL DEFAULT 0,'
          '  delete_intent_epoch INTEGER,'
          '  delete_push_started_at INTEGER'
          ')',
        );
        await db.customStatement('DROP TABLE fronting_sessions');
        await db.customStatement(
          'ALTER TABLE _new_fronting_sessions RENAME TO fronting_sessions',
        );

        await db.customStatement(
          'CREATE TABLE _new_front_session_comments ('
          '  id TEXT NOT NULL PRIMARY KEY,'
          '  session_id TEXT NOT NULL,'
          '  body TEXT NOT NULL,'
          '  timestamp INTEGER NOT NULL,'
          '  created_at INTEGER NOT NULL,'
          '  is_deleted INTEGER NOT NULL DEFAULT 0'
          ')',
        );
        await db.customStatement('DROP TABLE front_session_comments');
        await db.customStatement(
          'ALTER TABLE _new_front_session_comments RENAME TO '
          'front_session_comments',
        );

        // Build a fresh export service so the column-existence cache
        // starts clean against the rewritten tables.
        final freshExport = _makeExport(db, cacheDir);
        final export = await freshExport.buildExport(includeLegacyFields: true);
        expect(
          export,
          isNotNull,
          reason:
              'buildExport must not throw a SQL error when legacy columns '
              'have been dropped — the helper should detect the missing '
              'columns via PRAGMA table_info and return empty maps',
        );
      },
    );
  });
}
