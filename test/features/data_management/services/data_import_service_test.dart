import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
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
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/poll.dart';
import 'package:prism_plurality/domain/models/poll_option.dart';
import 'package:prism_plurality/domain/models/poll_vote.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
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

/// Build a minimal valid V3 export JSON with one member and one sleep session
/// that has a deliberately out-of-bounds quality index to trigger an exception
/// mid-import.
String _malformedExportJson({
  required String memberId,
  required String memberName,
}) {
  final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
  final export = {
    'formatVersion': '2025.1',
    'version': '3.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': 2,
    'headmates': [
      {
        'id': memberId,
        'name': memberName,
        'isActive': true,
        'createdAt': now,
        'displayOrder': 0,
        'isAdmin': false,
        'customColorEnabled': false,
      },
    ],
    'frontSessions': [],
    // This sleep session has quality index 999, which is out of bounds for
    // SleepQuality.values — causes a RangeError inside the transaction.
    'sleepSessions': [
      {
        'id': 'sleep-bad',
        'startTime': now,
        'quality': 999,
        'isHealthKitImport': false,
      },
    ],
    'conversations': [],
    'messages': [],
    'polls': [],
    'pollOptions': [],
    'systemSettings': [],
    'habits': [],
    'habitCompletions': [],
  };
  return jsonEncode(export);
}

/// Build a minimal valid V3 export JSON with one member and no bad records.
String _validExportJson({
  required String memberId,
  required String memberName,
  bool hasCompletedOnboarding = false,
}) {
  final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
  final export = {
    'formatVersion': '2025.1',
    'version': '3.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': 1,
    'headmates': [
      {
        'id': memberId,
        'name': memberName,
        'isActive': true,
        'createdAt': now,
        'displayOrder': 0,
        'isAdmin': false,
        'customColorEnabled': false,
      },
    ],
    'frontSessions': [],
    'sleepSessions': [],
    'conversations': [],
    'messages': [],
    'polls': [],
    'pollOptions': [],
    'systemSettings': [
      {
        'systemName': 'Imported System',
        'hasCompletedOnboarding': hasCompletedOnboarding,
      },
    ],
    'habits': [],
    'habitCompletions': [],
  };
  return jsonEncode(export);
}

void main() {
  group('DataImportService transaction rollback', () {
    late AppDatabase db;
    late DataImportService importService;
    late DriftMemberRepository memberRepo;
    late DriftSystemSettingsRepository settingsRepo;

    setUp(() {
      db = _makeDb();
      importService = _makeImport(db);
      memberRepo = DriftMemberRepository(db.membersDao, null);
      settingsRepo = DriftSystemSettingsRepository(db.systemSettingsDao, null);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'import with out-of-bounds quality gracefully defaults to unknown',
      () async {
        // Arrange: seed the database with one existing member.
        const existingId = 'existing-member';
        const existingName = 'Existing';
        await memberRepo.createMember(
          Member(
            id: existingId,
            name: existingName,
            emoji: '🔵',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ),
        );

        final before = await memberRepo.getAllMembers();
        expect(before, hasLength(1));

        // Act: import data with a sleep session quality index of 999.
        // The import service clamps out-of-bounds quality to SleepQuality.unknown
        // instead of crashing — this tests that graceful fallback.
        final badJson = _malformedExportJson(
          memberId: 'new-member-1',
          memberName: 'NewMember',
        );

        final result = await importService.importData(badJson);

        // Assert: import succeeded — the new member was added alongside the
        // existing one, and the sleep session was imported with quality=unknown.
        expect(result.membersCreated, 1);
        final after = await memberRepo.getAllMembers();
        expect(after, hasLength(2));

        final importedSleep = await db
            .customSelect(
              '''
            SELECT session_type, quality, is_health_kit_import
            FROM fronting_sessions
            WHERE id = ?
            ''',
              variables: [drift.Variable.withString('sleep-bad')],
            )
            .getSingleOrNull();
        expect(importedSleep, isNotNull);
        expect(importedSleep!.read<int>('session_type'), 1);
        expect(importedSleep.read<int>('quality'), 0);
        expect(importedSleep.read<bool>('is_health_kit_import'), isFalse);
      },
    );

    test(
      'import with out-of-bounds quality does not corrupt existing data',
      () async {
        // Arrange
        const existingId = 'pre-existing';
        await memberRepo.createMember(
          Member(
            id: existingId,
            name: 'Pre-existing',
            emoji: '⭐',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ),
        );

        final badJson = _malformedExportJson(
          memberId: 'partial-member',
          memberName: 'Partial',
        );

        // Act: import completes without throwing.
        final result = await importService.importData(badJson);
        expect(result.membersCreated, 1);

        // Assert: both the pre-existing and imported member are present.
        final members = await memberRepo.getAllMembers();
        expect(members, hasLength(2));
        expect(members.any((m) => m.id == existingId), isTrue);
        expect(members.any((m) => m.id == 'partial-member'), isTrue);
      },
    );

    test('successful import commits all records', () async {
      final validJson = _validExportJson(
        memberId: 'good-member',
        memberName: 'Good',
      );

      final result = await importService.importData(validJson);

      expect(result.membersCreated, 1);

      final members = await memberRepo.getAllMembers();
      expect(members, hasLength(1));
      expect(members.single.id, 'good-member');
    });

    test('import honors directmessage conversation type', () async {
      final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
      final json = jsonEncode({
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': now,
        'totalRecords': 1,
        'headmates': [],
        'frontSessions': [],
        'sleepSessions': [],
        'conversations': [
          {
            'id': 'dm-1',
            'createdAt': now,
            'lastActivityAt': now,
            'title': 'Imported DM',
            'type': 'directmessage',
            'isDirectMessage': false,
            'participantIds': ['alice', 'bob', 'carol'],
            'lastReadTimestamps': {},
          },
        ],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      });

      final result = await importService.importData(json);
      expect(result.conversationsCreated, 1);

      final conversations = await importService.conversationRepository
          .getAllConversations();
      expect(conversations, hasLength(1));
      expect(conversations.single.isDirectMessage, isTrue);
    });

    test('import honors everyone-group conversation flag', () async {
      final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
      final json = jsonEncode({
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': now,
        'totalRecords': 1,
        'headmates': [],
        'frontSessions': [],
        'sleepSessions': [],
        'conversations': [
          {
            'id': 'everyone-1',
            'createdAt': now,
            'lastActivityAt': now,
            'title': 'Everyone',
            'type': 'group',
            'isDirectMessage': false,
            'participantIds': ['alice'],
            'includesAllMembers': true,
            'lastReadTimestamps': {},
          },
        ],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      });

      final result = await importService.importData(json);
      expect(result.conversationsCreated, 1);

      final conversations = await importService.conversationRepository
          .getAllConversations();
      expect(conversations, hasLength(1));
      expect(conversations.single.includesAllMembers, isTrue);
    });

    test(
      'import defaults missing everyone-group flag for old exports',
      () async {
        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now,
          'totalRecords': 1,
          'headmates': [],
          'frontSessions': [],
          'sleepSessions': [],
          'conversations': [
            {
              'id': 'legacy-group-1',
              'createdAt': now,
              'lastActivityAt': now,
              'title': 'Legacy Group',
              'type': 'group',
              'isDirectMessage': false,
              'participantIds': ['alice'],
              'lastReadTimestamps': {},
            },
          ],
          'messages': [],
          'polls': [],
          'pollOptions': [],
          'systemSettings': [],
          'habits': [],
          'habitCompletions': [],
        });

        final result = await importService.importData(json);
        expect(result.conversationsCreated, 1);

        final conversations = await importService.conversationRepository
            .getAllConversations();
        expect(conversations, hasLength(1));
        expect(conversations.single.includesAllMembers, isFalse);
      },
    );

    test(
      'import preserves local values for missing legacy settings fields',
      () async {
        await importService.systemSettingsRepository.updateSettings(
          const SystemSettings(
            paletteSource: PaletteSource.device,
            paletteSeedColorHex: '#112233',
            paletteMood: PaletteMood.vibrant,
            paletteContrast: PaletteContrast.high,
            bioMarkdownEnabled: false,
          ),
        );

        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now,
          'totalRecords': 1,
          'headmates': [],
          'frontSessions': [],
          'sleepSessions': [],
          'conversations': [],
          'messages': [],
          'polls': [],
          'pollOptions': [],
          'systemSettings': [
            {'systemName': 'Legacy Export', 'accentColorHex': '#445566'},
          ],
          'habits': [],
          'habitCompletions': [],
        });

        final result = await importService.importData(json);
        expect(result.settingsUpdated, isTrue);

        final settings = await importService.systemSettingsRepository
            .getSettings();
        expect(settings.systemName, 'Legacy Export');
        expect(settings.paletteSource, PaletteSource.device);
        expect(settings.paletteSeedColorHex, '#112233');
        expect(settings.paletteMood, PaletteMood.vibrant);
        expect(settings.paletteContrast, PaletteContrast.high);
        expect(settings.bioMarkdownEnabled, isFalse);
      },
    );

    test(
      'import tolerates malformed member group presentation fields',
      () async {
        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc().toIso8601String();
        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now,
          'totalRecords': 1,
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
          'memberGroups': [
            {
              'id': 'group-bad-presentation',
              'name': 'Group',
              'avatarImageData': 'not-base64!',
              'sortState': {'mode': true, 'manualOrder': 'bad'},
              'createdAt': now,
            },
          ],
        });

        final result = await importService.importData(json);
        expect(result.memberGroupsCreated, 1);

        final groups = await importService.memberGroupsRepository
            .watchAllGroups()
            .first;
        expect(groups, hasLength(1));
        expect(groups.single.avatarImageData, isNull);
        expect(groups.single.sortState.isManual, isTrue);
        expect(groups.single.sortState.manualOrder, isEmpty);
      },
    );

    test(
      'can suppress imported onboarding completion for onboarding restore flow',
      () async {
        final validJson = _validExportJson(
          memberId: 'good-member',
          memberName: 'Good',
          hasCompletedOnboarding: true,
        );

        await importService.importData(
          validJson,
          preserveImportedOnboardingState: false,
        );

        final settings = await settingsRepo.getSettings();
        expect(settings.systemName, 'Imported System');
        expect(settings.hasCompletedOnboarding, isFalse);
      },
    );

    test(
      'import dedupes poll votes already written to the destination',
      () async {
        // Reproduces the onboarding collision: relay sync upserts a vote
        // row, the user falls back to backup import, the bare INSERT
        // collides on poll_votes.id.
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc();
        const pollId = 'poll-1';
        const optionId = 'opt-1';
        const voteId = '77c17336-87d6-4b9f-a513-34817f6bff86';
        const memberId = 'member-1';

        // Seed only the vote, not the parent option — that matches the
        // observed user state where the option dedup did not trigger but
        // the vote insert collided. poll_votes has no FK to poll_options.
        await pollRepo.castVote(
          PollVote(id: voteId, memberId: memberId, votedAt: now),
          optionId,
        );

        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now.toIso8601String(),
          'totalRecords': 1,
          'headmates': [
            {
              'id': memberId,
              'name': 'Voter',
              'isActive': true,
              'createdAt': now.toIso8601String(),
              'displayOrder': 0,
              'isAdmin': false,
              'customColorEnabled': false,
            },
          ],
          'frontSessions': [],
          'sleepSessions': [],
          'conversations': [],
          'messages': [],
          'polls': [
            {
              'id': pollId,
              'question': 'Do you want freeform?',
              'isAnonymous': false,
              'allowsMultipleVotes': false,
              'isClosed': false,
              'createdAt': now.toIso8601String(),
            },
          ],
          'pollOptions': [
            {
              'id': optionId,
              'pollId': pollId,
              'text': 'Yes',
              'sortOrder': 0,
              'isOtherOption': true,
              'votes': [
                {
                  'id': voteId,
                  'memberId': memberId,
                  'votedAt': now.toIso8601String(),
                  'responseText': 'a freeform answer',
                },
              ],
            },
          ],
          'systemSettings': [],
          'habits': [],
          'habitCompletions': [],
        });

        final result = await importService.importData(json);
        expect(result.pollsCreated, 1);
        expect(result.pollOptionsCreated, 1);

        final votes = await pollRepo.getAllVotes();
        expect(votes.where((v) => v.id == voteId), hasLength(1));
      },
    );

    test(
      'import dedupes poll/option/vote tombstones in the destination',
      () async {
        // Soft-delete keeps the PK id; dedup must include tombstones or
        // the import rolls back on UNIQUE constraint. This exercises the
        // polls.id path — the option tombstone short-circuits the outer
        // loop, so the vote tombstone path is covered by the next test.
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc();
        const pollId = 'tomb-poll-1';
        const optionId = 'tomb-opt-1';
        const voteId = 'tomb-vote-1';
        const memberId = 'tomb-member-1';

        await pollRepo.createPoll(
          Poll(id: pollId, question: 'tombstoned', createdAt: now),
        );
        await pollRepo.createOption(
          PollOption(id: optionId, text: 'Yes'),
          pollId,
        );
        await pollRepo.castVote(
          PollVote(id: voteId, memberId: memberId, votedAt: now),
          optionId,
        );
        await db.pollVotesDao.softDeleteVote(voteId);
        await db.pollOptionsDao.softDeleteOption(optionId);
        await db.pollsDao.softDeletePoll(pollId);

        expect(await pollRepo.getAllPolls(), isEmpty);
        expect(await pollRepo.getAllOptions(), isEmpty);
        expect(await pollRepo.getAllVotes(), isEmpty);
        expect(
          (await db.pollsDao.getAllPollsIncludingDeleted())
              .map((p) => p.id),
          contains(pollId),
        );

        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now.toIso8601String(),
          'totalRecords': 1,
          'headmates': [
            {
              'id': memberId,
              'name': 'Voter',
              'isActive': true,
              'createdAt': now.toIso8601String(),
              'displayOrder': 0,
              'isAdmin': false,
              'customColorEnabled': false,
            },
          ],
          'frontSessions': [],
          'sleepSessions': [],
          'conversations': [],
          'messages': [],
          'polls': [
            {
              'id': pollId,
              'question': 'tombstoned',
              'isAnonymous': false,
              'allowsMultipleVotes': false,
              'isClosed': false,
              'createdAt': now.toIso8601String(),
            },
          ],
          'pollOptions': [
            {
              'id': optionId,
              'pollId': pollId,
              'text': 'Yes',
              'sortOrder': 0,
              'isOtherOption': false,
              'votes': [
                {
                  'id': voteId,
                  'memberId': memberId,
                  'votedAt': now.toIso8601String(),
                },
              ],
            },
          ],
          'systemSettings': [],
          'habits': [],
          'habitCompletions': [],
        });

        await importService.importData(json);

        expect(await pollRepo.getAllPolls(), isEmpty);
        expect(await pollRepo.getAllOptions(), isEmpty);
        expect(await pollRepo.getAllVotes(), isEmpty);
      },
    );

    test(
      'import dedupes orphan poll vote tombstone via fresh option',
      () async {
        // Pins the vote tombstone path: seed only a soft-deleted orphan
        // vote, then import a fresh poll + fresh option whose votes array
        // references the same id. The option dedup does not short-circuit,
        // so the inner vote loop runs and must skip on existingVoteIds.
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc();
        const memberId = 'orphan-vote-member';
        const tombstonedVoteId = 'orphan-vote-tombstone';
        const newPollId = 'fresh-poll';
        const newOptionId = 'fresh-opt';

        await pollRepo.castVote(
          PollVote(id: tombstonedVoteId, memberId: memberId, votedAt: now),
          'seed-only-option',
        );
        await db.pollVotesDao.softDeleteVote(tombstonedVoteId);

        final json = jsonEncode({
          'formatVersion': '1.0',
          'version': '1.0',
          'appName': 'Prism Plurality',
          'exportDate': now.toIso8601String(),
          'totalRecords': 1,
          'headmates': [
            {
              'id': memberId,
              'name': 'Voter',
              'isActive': true,
              'createdAt': now.toIso8601String(),
              'displayOrder': 0,
              'isAdmin': false,
              'customColorEnabled': false,
            },
          ],
          'frontSessions': [],
          'sleepSessions': [],
          'conversations': [],
          'messages': [],
          'polls': [
            {
              'id': newPollId,
              'question': 'fresh',
              'isAnonymous': false,
              'allowsMultipleVotes': false,
              'isClosed': false,
              'createdAt': now.toIso8601String(),
            },
          ],
          'pollOptions': [
            {
              'id': newOptionId,
              'pollId': newPollId,
              'text': 'Yes',
              'sortOrder': 0,
              'isOtherOption': false,
              'votes': [
                {
                  'id': tombstonedVoteId,
                  'memberId': memberId,
                  'votedAt': now.toIso8601String(),
                },
              ],
            },
          ],
          'systemSettings': [],
          'habits': [],
          'habitCompletions': [],
        });

        final result = await importService.importData(json);
        expect(result.pollsCreated, 1);
        expect(result.pollOptionsCreated, 1);

        expect(await pollRepo.getAllPolls(), hasLength(1));
        expect(await pollRepo.getAllOptions(), hasLength(1));
        expect(await pollRepo.getAllVotes(), isEmpty);
      },
    );
  });

  group('DataImportService.resolveBytes — Prism JSON rejection', () {
    test(
      'unencrypted Prism JSON (has "formatVersion") throws FormatException',
      () {
        final prismJson = utf8.encode(
          '{"formatVersion":"prism_v3","headmates":[]}',
        );
        expect(
          () => DataImportService.resolveBytes(Uint8List.fromList(prismJson)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              equals('unencrypted-prism-backup'),
            ),
          ),
        );
      },
    );

    test('third-party SP JSON (no "formatVersion") is accepted', () {
      final spJson = utf8.encode('{"content":"Hello"}');
      final result = DataImportService.resolveBytes(Uint8List.fromList(spJson));
      expect(result.json, equals('{"content":"Hello"}'));
      expect(result.mediaBlobs, isEmpty);
    });

    test('binary garbage that fails UTF-8 decode throws FormatException', () {
      final garbage = Uint8List.fromList([0xff, 0xfe, 0xfd, 0x00, 0x01]);
      expect(
        () => DataImportService.resolveBytes(garbage),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DataImportService.resolveBytes — media manifest validation', () {
    const password = 'test-password-manifest-2026';

    Uint8List makeEncrypted(
      String json,
      List<({String mediaId, Uint8List blob})> blobs,
    ) => ExportCrypto.encrypt(json, blobs, password);

    test('blob whose mediaId is not in manifest throws FormatException', () {
      // JSON has empty mediaAttachments; binary has 1 blob — mismatch
      const json = '{"mediaAttachments":[]}';
      final blob = Uint8List.fromList([1, 2, 3]);
      final encrypted = makeEncrypted(json, [
        (mediaId: 'extra-id', blob: blob),
      ]);
      expect(
        () => DataImportService.resolveBytes(encrypted, password: password),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('corrupted'),
          ),
        ),
      );
    });

    test(
      'blob whose mediaId matches a thumbnailMediaId in the manifest is accepted',
      () {
        const thumbId = 'thumb-abc-123';
        const json =
            '{"mediaAttachments":[{"mediaId":"main-abc","thumbnailMediaId":"$thumbId"}]}';
        final blob = Uint8List.fromList([10, 20, 30]);
        final encrypted = makeEncrypted(json, [(mediaId: thumbId, blob: blob)]);
        final result = DataImportService.resolveBytes(
          encrypted,
          password: password,
        );
        expect(result.mediaBlobs.length, equals(1));
        expect(result.mediaBlobs.first.mediaId, equals(thumbId));
      },
    );

    test('blob whose mediaId matches a mediaId in the manifest is accepted', () {
      const mainId = 'main-abc-456';
      const json =
          '{"mediaAttachments":[{"mediaId":"$mainId","thumbnailMediaId":""}]}';
      final blob = Uint8List.fromList([7, 8, 9]);
      final encrypted = makeEncrypted(json, [(mediaId: mainId, blob: blob)]);
      final result = DataImportService.resolveBytes(
        encrypted,
        password: password,
      );
      expect(result.mediaBlobs.length, equals(1));
    });

    test('no blobs skips manifest validation (no JSON parse needed)', () {
      const json = '{"mediaAttachments":[]}';
      final encrypted = makeEncrypted(json, const []);
      final result = DataImportService.resolveBytes(
        encrypted,
        password: password,
      );
      expect(result.mediaBlobs, isEmpty);
    });
  });
}
