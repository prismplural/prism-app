/// Integration test: full SP file import pipeline using a real SP export.
///
/// Excluded from CI. Run manually:
///   flutter test --tags integration test/features/migration/services/sp_file_integration_test.dart
///
/// Looks for the export at SP_EXPORT_FILE env var, or the default path below.
/// The test is skipped automatically if the file doesn't exist.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

const _defaultExportPath =
    '/Users/test/Downloads/export_7b35523dcdf0f69a3aed9e965506e1c0ad9d6a9df79ddba866cbd4bdc352703a(1).json';

String get _exportPath =>
    const String.fromEnvironment('SP_EXPORT_FILE', defaultValue: _defaultExportPath);

void main() {
  group('SP file import — full pipeline integration', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'parseFile + executeImport on a fresh DB writes expected entities',
      () async {
        if (!File(_exportPath).existsSync()) {
          markTestSkipped(
              'Export file not found at $_exportPath — set SP_EXPORT_FILE to run this test');
          return;
        }

        final importer = SpImporter();

        // -- 1. Parse the real export file ----------------------------------------
        final exportData = importer.parseFile(_exportPath);

        expect(exportData.isEmpty, isFalse,
            reason: 'Export file should contain at least one entity');
        expect(exportData.members, isNotEmpty,
            reason: 'Export should have members');
        expect(exportData.frontHistory, isNotEmpty,
            reason: 'Export should have front history');
        expect(exportData.groups.length, 2,
            reason: 'Export has 1 root group (Littles) and 1 sub-group (Children)');
        // Verify "root" parent sentinel is parsed without blowing up
        final rootGroups =
            exportData.groups.where((g) => g.parent == 'root').toList();
        final subGroups =
            exportData.groups.where((g) => g.parent != null && g.parent != 'root').toList();
        expect(rootGroups.length, 1, reason: 'One root group');
        expect(subGroups.length, 1, reason: 'One sub-group with a parent reference');

        // -- 2. Import into a fresh in-memory DB -----------------------------------
        final result = await importer.executeImport(
          db: db,
          data: exportData,
          memberRepo: DriftMemberRepository(db.membersDao, null),
          sessionRepo:
              DriftFrontingSessionRepository(db.frontingSessionsDao, null),
          conversationRepo:
              DriftConversationRepository(db.conversationsDao, null),
          messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
          pollRepo: DriftPollRepository(
              db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null),
          notesRepo: DriftNotesRepository(db.notesDao, null),
          commentsRepo: DriftFrontSessionCommentsRepository(
              db.frontSessionCommentsDao, null),
          customFieldsRepo:
              DriftCustomFieldsRepository(db.customFieldsDao, null),
          groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
          remindersRepo: DriftRemindersRepository(db.remindersDao, null),
          settingsRepo:
              DriftSystemSettingsRepository(db.systemSettingsDao, null),
          categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao, null),
          spImportDao: db.spImportDao,
          downloadAvatars: false,
        );

        // -- 3. Result counts match what we know is in this export -----------------
        expect(result.membersImported, greaterThan(0));
        expect(result.sessionsImported, equals(exportData.frontHistory.length),
            reason: 'All front history entries should become sessions');
        expect(result.conversationsImported, equals(exportData.channels.length),
            reason: 'Each SP channel should become a conversation');
        expect(result.messagesImported, greaterThan(0),
            reason: 'This export has chat messages');
        expect(result.groupsImported, 2,
            reason: 'Both SP groups should be imported');

        // -- 4. DB reflects the result --------------------------------------------
        final membersInDb = await db.membersDao.getAllMembers();
        expect(membersInDb.length, result.membersImported,
            reason: 'DB member count should match import result');

        final sessionsInDb =
            await db.frontingSessionsDao.getAllSessions();
        expect(sessionsInDb.length, result.sessionsImported);

        // Groups: verify hierarchy landed correctly in the DB.
        final groupsInDb = await db.memberGroupsDao.getAllActiveGroups();
        expect(groupsInDb.length, 2);
        final rootGroupsInDb =
            groupsInDb.where((g) => g.parentGroupId == null).toList();
        final childGroupsInDb =
            groupsInDb.where((g) => g.parentGroupId != null).toList();
        expect(rootGroupsInDb.length, 1,
            reason: 'Littles should have no parent');
        expect(childGroupsInDb.length, 1,
            reason: 'Children should have Littles as parent');
        // The child's parentGroupId should match the root group's Prism ID.
        expect(childGroupsInDb.first.parentGroupId, rootGroupsInDb.first.id,
            reason: 'Parent reference should resolve to the imported Prism ID');
        // getDirectChildrenOf returns the sub-group.
        final directChildren = await db.memberGroupsDao
            .getDirectChildrenOf(rootGroupsInDb.first.id);
        expect(directChildren.length, 1);
        expect(directChildren.first.id, childGroupsInDb.first.id);
        // Each group has 1 member entry.
        final groupEntriesInDb = await db.memberGroupsDao.getAllGroupEntries();
        expect(groupEntriesInDb.length, 2,
            reason: 'One member per group');

        // -- 5. ID map was persisted -----------------------------------------------
        final idMappings = await db.spImportDao.getAllMappings();
        expect(idMappings, isNotEmpty);
        final memberMappings =
            idMappings.where((r) => r.entityType == 'member').toList();
        expect(memberMappings.length, result.membersImported);
        final groupMappings =
            idMappings.where((r) => r.entityType == 'group').toList();
        expect(groupMappings.length, 2,
            reason: 'SP→Prism ID map should have an entry for each group');

        // -- 6. Sync state was written --------------------------------------------
        final syncState = await db.spImportDao.getSyncState();
        expect(syncState, isNotNull);
        expect(syncState!.lastImportAt, isNotNull);

        // -- Diagnostic output ----------------------------------------------------
        // ignore: avoid_print
        print('\n=== SP File Integration Test Summary ===');
        // ignore: avoid_print
        print('Parsed: ${exportData.members.length} members, '
            '${exportData.frontHistory.length} sessions, '
            '${exportData.channels.length} channels, '
            '${exportData.messages.length} messages, '
            '${exportData.groups.length} groups');
        // ignore: avoid_print
        print('Imported: ${result.membersImported} members, '
            '${result.sessionsImported} sessions, '
            '${result.conversationsImported} conversations, '
            '${result.messagesImported} messages, '
            '${result.pollsImported} polls, '
            '${result.groupsImported} groups');
        // ignore: avoid_print
        print('Warnings (${result.warnings.length}): ${result.warnings}');
        // ignore: avoid_print
        print('ID map rows: ${idMappings.length}');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      're-import with clearExistingData is idempotent',
      () async {
        if (!File(_exportPath).existsSync()) {
          markTestSkipped(
              'Export file not found at $_exportPath — set SP_EXPORT_FILE to run this test');
          return;
        }

        final importer = SpImporter();
        final exportData = importer.parseFile(_exportPath);

        Future<int> runImport({bool clear = false}) async {
          final r = await importer.executeImport(
            db: db,
            data: exportData,
            memberRepo: DriftMemberRepository(db.membersDao, null),
            sessionRepo:
                DriftFrontingSessionRepository(db.frontingSessionsDao, null),
            conversationRepo:
                DriftConversationRepository(db.conversationsDao, null),
            messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
            pollRepo: DriftPollRepository(
                db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null),
            notesRepo: DriftNotesRepository(db.notesDao, null),
            commentsRepo: DriftFrontSessionCommentsRepository(
                db.frontSessionCommentsDao, null),
            customFieldsRepo:
                DriftCustomFieldsRepository(db.customFieldsDao, null),
            groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
            remindersRepo: DriftRemindersRepository(db.remindersDao, null),
            settingsRepo:
                DriftSystemSettingsRepository(db.systemSettingsDao, null),
            categoriesRepo: DriftConversationCategoriesRepository(
                db.conversationCategoriesDao, null),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            clearExistingData: clear,
          );
          return r.membersImported;
        }

        final first = await runImport();
        final second = await runImport(clear: true);

        expect(second, first,
            reason: 're-import should yield the same member count');

        final membersInDb = await db.membersDao.getAllMembers();
        expect(membersInDb.length, second);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
