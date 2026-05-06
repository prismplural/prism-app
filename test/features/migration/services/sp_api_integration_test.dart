/// Integration test: full SP API import pipeline against a live SP account.
///
/// Excluded from CI. Run manually with an SP token in SP_TOKEN:
///   SP_TOKEN=your-token flutter test --tags integration \
///     test/features/migration/services/sp_api_integration_test.dart
///
/// The test hits the live Simply Plural API — use a dedicated test account,
/// not your real system.
@Tags(['integration'])
library;

import 'dart:io' show Platform;

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
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

final String? _spToken = Platform.environment['SP_TOKEN'];

Object? get _skipWithoutSpToken => _spToken == null || _spToken!.isEmpty
    ? 'SP_TOKEN env var not set — skipping live Simply Plural integration tests'
    : false;

String get _testToken {
  final token = _spToken;
  if (token == null || token.isEmpty) {
    throw StateError('SP_TOKEN env var is required for this integration test.');
  }
  return token;
}

void main() {
  group('SP API import — full pipeline integration', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'fetchAll + executeImport on a fresh DB writes entities and id-map',
      () async {
        final client = SpApiClient(token: _testToken);
        addTearDown(client.dispose);

        // -- 1. Fetch from the real SP API ----------------------------------------
        final progressLog = <String>[];
        final exportData = await client.fetchAll(
          onProgress: (collection, count) {
            progressLog.add('$collection: $count');
          },
        );

        expect(
          exportData.isEmpty,
          isFalse,
          reason: 'Test account should have at least one entity',
        );

        // -- 2. Import into a fresh in-memory DB -----------------------------------
        final result = await SpImporter().executeImport(
          db: db,
          data: exportData,
          memberRepo: DriftMemberRepository(db.membersDao, null),
          sessionRepo: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          ),
          conversationRepo: DriftConversationRepository(
            db.conversationsDao,
            null,
          ),
          messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
          pollRepo: DriftPollRepository(
            db.pollsDao,
            db.pollOptionsDao,
            db.pollVotesDao,
            null,
          ),
          notesRepo: DriftNotesRepository(db.notesDao, null),
          commentsRepo: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          customFieldsRepo: DriftCustomFieldsRepository(
            db.customFieldsDao,
            null,
          ),
          groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
          remindersRepo: DriftRemindersRepository(db.remindersDao, null),
          settingsRepo: DriftSystemSettingsRepository(
            db.systemSettingsDao,
            null,
          ),
          boardPostsRepo: DriftMemberBoardPostsRepository(
            db.memberBoardPostsDao,
            db.membersDao,
            null,
          ),
          categoriesRepo: DriftConversationCategoriesRepository(
            db.conversationCategoriesDao,
            null,
          ),
          spImportDao: db.spImportDao,
          downloadAvatars: false,
        );

        // -- 3. Result counts are internally consistent ----------------------------
        // SP data may include soft-deleted members or custom fronts that are
        // filtered/counted separately — just verify we got something.
        expect(
          result.membersImported,
          greaterThan(0),
          reason: 'Test account has members',
        );
        expect(result.sessionsImported, greaterThanOrEqualTo(0));

        // -- 4. DB reflects the import result -------------------------------------
        final membersInDb = await db.membersDao.getAllMembers();
        expect(
          membersInDb.length,
          result.membersImported,
          reason: 'DB member count should match import result',
        );

        final settings = await DriftSystemSettingsRepository(
          db.systemSettingsDao,
          null,
        ).getSettings();
        if ((exportData.systemDescription ?? '').trim().isNotEmpty) {
          expect(
            settings.systemDescription,
            exportData.systemDescription,
            reason:
                'System description from the API should persist into settings',
          );
        }

        final chatMessagesInDb = await db.chatMessagesDao.getAllMessages();
        final sourceReplyMessages = exportData.messages
            .where((message) => (message.replyTo ?? '').isNotEmpty)
            .toList();
        if (sourceReplyMessages.isNotEmpty) {
          expect(
            chatMessagesInDb
                .where((message) => message.replyToId != null)
                .length,
            sourceReplyMessages.length,
            reason: 'Reply metadata should survive SP API import',
          );
        }

        final sourceEditedMessages = exportData.messages
            .where((message) => message.updatedAt != null)
            .toList();
        if (sourceEditedMessages.isNotEmpty) {
          expect(
            chatMessagesInDb
                .where((message) => message.editedAt != null)
                .length,
            sourceEditedMessages.length,
            reason: 'Edited timestamps should survive SP API import',
          );
        }

        final pollsInDb = await db.pollsDao.getAllPolls();
        expect(
          pollsInDb.length,
          result.pollsImported,
          reason: 'DB poll count should match import result',
        );

        final standardSourcePolls = exportData.polls
            .where((poll) => !poll.isCustom)
            .toList();
        expect(
          standardSourcePolls,
          isNotEmpty,
          reason: 'Live test account should include at least one standard poll',
        );

        for (final sourcePoll in standardSourcePolls) {
          final matchingPolls = pollsInDb
              .where((poll) => poll.question == sourcePoll.question)
              .toList();
          expect(
            matchingPolls,
            isNotEmpty,
            reason:
                'Imported DB should contain standard poll "${sourcePoll.question}"',
          );
          final importedPoll = matchingPolls.first;

          final optionsForPoll = await db.pollOptionsDao.getOptionsForPoll(
            importedPoll.id,
          );
          final optionTexts = optionsForPoll
              .map((option) => option.optionText)
              .toList();
          final expectedOptionTexts = <String>[
            'Yes',
            'No',
            if (sourcePoll.allowAbstain) 'Abstain',
            if (sourcePoll.allowVeto) 'Veto',
          ];
          expect(
            optionTexts,
            expectedOptionTexts,
            reason:
                'Standard poll "${sourcePoll.question}" should synthesize fixed Prism options',
          );

          var importedVoteCount = 0;
          for (final option in optionsForPoll) {
            importedVoteCount += (await db.pollVotesDao.getVotesForOption(
              option.id,
            )).length;
          }
          expect(
            importedVoteCount,
            sourcePoll.votes.length,
            reason:
                'Standard poll "${sourcePoll.question}" should preserve all source votes',
          );
        }

        // -- 5. ID map was persisted -----------------------------------------------
        final idMappings = await db.spImportDao.getAllMappings();
        expect(
          idMappings,
          isNotEmpty,
          reason: 'At least member ID mappings should be in the id-map table',
        );
        // Every imported member should have a mapping row.
        final memberMappings = idMappings
            .where((r) => r.entityType == 'member')
            .toList();
        expect(memberMappings.length, result.membersImported);

        final valuesInDb = await db.customFieldsDao.getAllValues();
        final sourceMembersWithInfo = exportData.members
            .where(
              (member) => member.info.entries.any(
                (entry) =>
                    entry.value != null &&
                    entry.value.toString().trim().isNotEmpty,
              ),
            )
            .toList();
        expect(
          sourceMembersWithInfo,
          isNotEmpty,
          reason:
              'Live test account should include at least one member with custom field values',
        );

        for (final sourceMember in sourceMembersWithInfo) {
          final prismMemberId = memberMappings
              .firstWhere((mapping) => mapping.spId == sourceMember.id)
              .prismId;
          final expectedValues = sourceMember.info.values
              .where(
                (value) => value != null && value.toString().trim().isNotEmpty,
              )
              .map((value) => value.toString())
              .toSet();
          final importedValues = valuesInDb
              .where((value) => value.memberId == prismMemberId)
              .map((value) => value.value)
              .toSet();
          expect(
            importedValues,
            expectedValues,
            reason:
                'Custom field values should round-trip for member "${sourceMember.name}"',
          );
        }

        final readBoardMessages = exportData.boardMessages
            .where((message) => message.read && message.writtenFor != null)
            .toList();
        expect(
          readBoardMessages,
          isNotEmpty,
          reason:
              'Live test account should include at least one read board message',
        );

        final latestReadAtBySpMember = <String, DateTime>{};
        for (final message in readBoardMessages) {
          final memberId = message.writtenFor!;
          final previous = latestReadAtBySpMember[memberId];
          if (previous == null || message.writtenAt.isAfter(previous)) {
            latestReadAtBySpMember[memberId] = message.writtenAt;
          }
        }

        for (final entry in latestReadAtBySpMember.entries) {
          final prismMemberId = memberMappings
              .firstWhere((mapping) => mapping.spId == entry.key)
              .prismId;
          final importedMember = await db.membersDao.getMemberById(
            prismMemberId,
          );
          expect(importedMember, isNotNull);
          expect(
            importedMember!.boardLastReadAt,
            isNotNull,
            reason:
                'Read board messages should set boardLastReadAt for member ${entry.key}',
          );
          expect(
            importedMember.boardLastReadAt!.millisecondsSinceEpoch,
            (entry.value.toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
            reason:
                'boardLastReadAt should match latest read board message timestamp',
          );
        }

        // -- 6. Sync state was written --------------------------------------------
        final syncState = await db.spImportDao.getSyncState();
        expect(
          syncState,
          isNotNull,
          reason:
              'SpImporter should write SpSyncState after a successful import',
        );
        expect(syncState!.lastImportAt, isNotNull);

        // Diagnostic output — helpful when running manually.
        // ignore: avoid_print
        print('\n=== SP API Integration Test Summary ===');
        // ignore: avoid_print
        print('Progress: $progressLog');
        // ignore: avoid_print
        print(
          'Members: ${result.membersImported}, '
          'Sessions: ${result.sessionsImported}, '
          'Conversations: ${result.conversationsImported}, '
          'Messages: ${result.messagesImported}, '
          'Polls: ${result.pollsImported}',
        );
        // ignore: avoid_print
        print('Warnings (${result.warnings.length}): ${result.warnings}');
        // ignore: avoid_print
        print('ID map rows: ${idMappings.length}');
        // ignore: avoid_print
        print('Sync state last import: ${syncState.lastImportAt}');
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: _skipWithoutSpToken,
    );

    test(
      're-import is idempotent: running twice yields same member count',
      () async {
        final client = SpApiClient(token: _testToken);
        addTearDown(client.dispose);

        final exportData = await client.fetchAll();

        Future<int> runImport() async {
          final result = await SpImporter().executeImport(
            db: db,
            data: exportData,
            memberRepo: DriftMemberRepository(db.membersDao, null),
            sessionRepo: DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
            ),
            conversationRepo: DriftConversationRepository(
              db.conversationsDao,
              null,
            ),
            messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
            pollRepo: DriftPollRepository(
              db.pollsDao,
              db.pollOptionsDao,
              db.pollVotesDao,
              null,
            ),
            notesRepo: DriftNotesRepository(db.notesDao, null),
            commentsRepo: DriftFrontSessionCommentsRepository(
              db.frontSessionCommentsDao,
              null,
            ),
            customFieldsRepo: DriftCustomFieldsRepository(
              db.customFieldsDao,
              null,
            ),
            groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
            remindersRepo: DriftRemindersRepository(db.remindersDao, null),
            settingsRepo: DriftSystemSettingsRepository(
              db.systemSettingsDao,
              null,
            ),
            boardPostsRepo: DriftMemberBoardPostsRepository(
              db.memberBoardPostsDao,
              db.membersDao,
              null,
            ),
            categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao,
              null,
            ),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
          );
          return result.membersImported;
        }

        final firstCount = await runImport();
        // Second import uses clearExistingData to wipe and re-import cleanly.
        final secondCount = await SpImporter()
            .executeImport(
              db: db,
              data: exportData,
              memberRepo: DriftMemberRepository(db.membersDao, null),
              sessionRepo: DriftFrontingSessionRepository(
                db.frontingSessionsDao,
                null,
              ),
              conversationRepo: DriftConversationRepository(
                db.conversationsDao,
                null,
              ),
              messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
              pollRepo: DriftPollRepository(
                db.pollsDao,
                db.pollOptionsDao,
                db.pollVotesDao,
                null,
              ),
              notesRepo: DriftNotesRepository(db.notesDao, null),
              commentsRepo: DriftFrontSessionCommentsRepository(
                db.frontSessionCommentsDao,
                null,
              ),
              customFieldsRepo: DriftCustomFieldsRepository(
                db.customFieldsDao,
                null,
              ),
              groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
              remindersRepo: DriftRemindersRepository(db.remindersDao, null),
              settingsRepo: DriftSystemSettingsRepository(
                db.systemSettingsDao,
                null,
              ),
              boardPostsRepo: DriftMemberBoardPostsRepository(
                db.memberBoardPostsDao,
                db.membersDao,
                null,
              ),
              categoriesRepo: DriftConversationCategoriesRepository(
                db.conversationCategoriesDao,
                null,
              ),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
              clearExistingData: true,
            )
            .then((r) => r.membersImported);

        expect(
          secondCount,
          firstCount,
          reason:
              're-import with clearExistingData should yield the same member count',
        );

        final membersInDb = await db.membersDao.getAllMembers();
        expect(
          membersInDb.length,
          secondCount,
          reason: 'DB should have exactly secondCount members after re-import',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: _skipWithoutSpToken,
    );
  });
}
