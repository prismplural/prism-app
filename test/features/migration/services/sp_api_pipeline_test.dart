import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

void main() {
  group('SP API pipeline', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'mocked API import with clearExistingData preserves chat messages on overwrite',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            final path = request.url.path;

            if (path == '/v1/me') {
              return http.Response(
                jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test'}),
                200,
              );
            }
            if (path.startsWith('/v1/members/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
                ]),
                200,
              );
            }
            if (path == '/v1/frontHistory') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/customFronts/') ||
                path.startsWith('/v1/groups/') ||
                path.startsWith('/v1/customFields/') ||
                path.startsWith('/v1/polls/') ||
                path.startsWith('/v1/notes/') ||
                path.startsWith('/v1/comments/') ||
                path.startsWith('/v1/board/member/')) {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path == '/v1/chat/categories') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path == '/v1/chat/channels') {
              return http.Response(
                jsonEncode([
                  {
                    '_id': 'ch1',
                    'name': 'General',
                    'members': ['mem1'],
                  },
                ]),
                200,
              );
            }
            if (path == '/v1/chat/messages/ch1') {
              final skipTo = request.url.queryParameters['skipTo'];
              if (skipTo == null) {
                return http.Response(
                  jsonEncode([
                    {
                      '_id': 'msg1',
                      'message': 'hello',
                      'sender': 'mem1',
                      'timestamp': 1768435200000,
                    },
                    {
                      '_id': 'msg2',
                      'message': 'world',
                      'sender': 'mem1',
                      'timestamp': 1768435260000,
                    },
                  ]),
                  200,
                );
              }
              return http.Response(jsonEncode(const []), 200);
            }

            return http.Response('Not found', 404);
          }),
        );
        addTearDown(client.dispose);

        Future<void> runImport({required bool clearExistingData}) async {
          final exportData = await client.fetchAll();
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
            categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao,
              null,
            ),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            clearExistingData: clearExistingData,
          );

          expect(result.conversationsImported, 1);
          expect(result.messagesImported, 2);
        }

        await runImport(clearExistingData: false);

        var conversations = await db.conversationsDao.getAllConversations();
        var messages = await db.chatMessagesDao.getAllMessages();
        expect(conversations, hasLength(1));
        expect(messages, hasLength(2));
        expect(messages.map((m) => m.content).toList(), ['world', 'hello']);

        await runImport(clearExistingData: true);

        conversations = await db.conversationsDao.getAllConversations();
        messages = await db.chatMessagesDao.getAllMessages();
        expect(conversations, hasLength(1));
        expect(messages, hasLength(2));
        expect(messages.map((m) => m.content).toList(), ['world', 'hello']);
      },
    );

    test(
      'mocked multi-page API import preserves full chat history on overwrite',
      () async {
        final page1 = List.generate(
          100,
          (index) => {
            '_id': 'msg${index + 1}',
            'message': 'message ${index + 1}',
            'sender': 'mem1',
            'timestamp': 1768435200000 + (index * 60000),
          },
        );
        final page2 = List.generate(
          25,
          (index) => {
            '_id': 'msg${index + 101}',
            'message': 'message ${index + 101}',
            'sender': 'mem1',
            'timestamp': 1768441200000 + (index * 60000),
          },
        );
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            final path = request.url.path;

            if (path == '/v1/me') {
              return http.Response(
                jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test'}),
                200,
              );
            }
            if (path.startsWith('/v1/members/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
                ]),
                200,
              );
            }
            if (path == '/v1/frontHistory') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/customFronts/') ||
                path.startsWith('/v1/groups/') ||
                path.startsWith('/v1/customFields/') ||
                path.startsWith('/v1/polls/') ||
                path.startsWith('/v1/notes/') ||
                path.startsWith('/v1/comments/') ||
                path.startsWith('/v1/board/member/')) {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path == '/v1/chat/categories') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path == '/v1/chat/channels') {
              return http.Response(
                jsonEncode([
                  {
                    '_id': 'ch1',
                    'name': 'General',
                    'members': ['mem1'],
                  },
                ]),
                200,
              );
            }
            if (path == '/v1/chat/messages/ch1') {
              final skipTo = request.url.queryParameters['skipTo'];
              if (skipTo == null) {
                return http.Response(jsonEncode(page1), 200);
              }
              if (skipTo == 'msg100') {
                return http.Response(jsonEncode(page2), 200);
              }
              return http.Response(jsonEncode(const []), 200);
            }

            return http.Response('Not found', 404);
          }),
        );
        addTearDown(client.dispose);

        Future<void> runImport({required bool clearExistingData}) async {
          final exportData = await client.fetchAll();
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
            categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao,
              null,
            ),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            clearExistingData: clearExistingData,
          );

          expect(result.conversationsImported, 1);
          expect(result.messagesImported, 125);
        }

        await runImport(clearExistingData: false);

        var conversations = await db.conversationsDao.getAllConversations();
        var messages = await db.chatMessagesDao.getAllMessages();
        expect(conversations, hasLength(1));
        expect(messages, hasLength(125));
        expect(messages.first.content, 'message 125');
        expect(messages.last.content, 'message 1');
        expect(messages.map((m) => m.content).toSet(), hasLength(125));

        await runImport(clearExistingData: true);

        conversations = await db.conversationsDao.getAllConversations();
        messages = await db.chatMessagesDao.getAllMessages();
        expect(conversations, hasLength(1));
        expect(messages, hasLength(125));
        expect(messages.first.content, 'message 125');
        expect(messages.last.content, 'message 1');
        expect(messages.map((m) => m.content).toSet(), hasLength(125));
      },
    );

    test(
      'mocked API import fetches standard poll detail before overwrite',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            final path = request.url.path;

            if (path == '/v1/me') {
              return http.Response(
                jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test'}),
                200,
              );
            }
            if (path.startsWith('/v1/members/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
                ]),
                200,
              );
            }
            if (path == '/v1/frontHistory') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/customFronts/') ||
                path.startsWith('/v1/groups/') ||
                path.startsWith('/v1/customFields/') ||
                path.startsWith('/v1/notes/') ||
                path.startsWith('/v1/comments/') ||
                path.startsWith('/v1/board/member/')) {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/polls/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'poll1', 'name': 'Test poll', 'custom': false},
                ]),
                200,
              );
            }
            if (path == '/v1/poll/sys1/poll1') {
              return http.Response(
                jsonEncode({
                  '_id': 'poll1',
                  'name': 'Test poll',
                  'custom': false,
                  'allowAbstain': true,
                  'allowVeto': true,
                  'votes': [
                    {'id': 'mem1', 'vote': 'yes', 'comment': 'hell yea'},
                  ],
                }),
                200,
              );
            }
            if (path == '/v1/chat/categories' || path == '/v1/chat/channels') {
              return http.Response(jsonEncode(const []), 200);
            }

            return http.Response('Not found', 404);
          }),
        );
        addTearDown(client.dispose);

        Future<void> runImport({required bool clearExistingData}) async {
          final exportData = await client.fetchAll();
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
            categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao,
              null,
            ),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            clearExistingData: clearExistingData,
          );

          expect(result.pollsImported, 1);
        }

        await runImport(clearExistingData: false);

        var polls = await db.pollsDao.getAllPolls();
        var options = await db.pollOptionsDao.getOptionsForPoll(
          polls.single.id,
        );
        expect(polls, hasLength(1));
        expect(options.map((o) => o.optionText).toList(), [
          'Yes',
          'No',
          'Abstain',
          'Veto',
        ]);
        final yesOption = options.firstWhere(
          (option) => option.optionText == 'Yes',
        );
        var votes = await db.pollVotesDao.getVotesForOption(yesOption.id);
        expect(votes, hasLength(1));
        expect(votes.single.responseText, 'hell yea');

        await runImport(clearExistingData: true);

        polls = await db.pollsDao.getAllPolls();
        options = await db.pollOptionsDao.getOptionsForPoll(polls.single.id);
        expect(polls, hasLength(1));
        expect(options.map((o) => o.optionText).toList(), [
          'Yes',
          'No',
          'Abstain',
          'Veto',
        ]);
        final overwrittenYesOption = options.firstWhere(
          (option) => option.optionText == 'Yes',
        );
        votes = await db.pollVotesDao.getVotesForOption(
          overwrittenYesOption.id,
        );
        expect(votes, hasLength(1));
        expect(votes.single.responseText, 'hell yea');
      },
    );

    test(
      'mocked API import preserves custom poll detail, colors, and vote comments on overwrite',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            final path = request.url.path;

            if (path == '/v1/me') {
              return http.Response(
                jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test'}),
                200,
              );
            }
            if (path.startsWith('/v1/members/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
                  {'_id': 'mem2', 'name': 'Mina', 'pronouns': 'she/her'},
                ]),
                200,
              );
            }
            if (path == '/v1/frontHistory') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/customFronts/') ||
                path.startsWith('/v1/groups/') ||
                path.startsWith('/v1/customFields/') ||
                path.startsWith('/v1/notes/') ||
                path.startsWith('/v1/comments/') ||
                path.startsWith('/v1/board/member/')) {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/polls/')) {
              return http.Response(
                jsonEncode([
                  {
                    '_id': 'poll1',
                    'question': 'Pick multiple',
                    'custom': true,
                    'allowMultiple': true,
                  },
                ]),
                200,
              );
            }
            if (path == '/v1/poll/sys1/poll1') {
              return http.Response(
                jsonEncode({
                  '_id': 'poll1',
                  'question': 'Pick multiple',
                  'custom': true,
                  'allowMultiple': true,
                  'options': [
                    {'text': 'Alpha', 'color': '#AA0000'},
                    {'text': 'Beta', 'color': '#00BB00'},
                  ],
                  'votes': [
                    {'id': 'mem1', 'vote': 'Alpha', 'comment': 'first pick'},
                    {'id': 'mem1', 'vote': 'Beta'},
                    {'id': 'mem2', 'vote': 'Beta'},
                  ],
                }),
                200,
              );
            }
            if (path == '/v1/chat/categories' || path == '/v1/chat/channels') {
              return http.Response(jsonEncode(const []), 200);
            }

            return http.Response('Not found', 404);
          }),
        );
        addTearDown(client.dispose);

        Future<void> runImport({required bool clearExistingData}) async {
          final exportData = await client.fetchAll();
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
            categoriesRepo: DriftConversationCategoriesRepository(
              db.conversationCategoriesDao,
              null,
            ),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            clearExistingData: clearExistingData,
          );

          expect(result.pollsImported, 1);
        }

        await runImport(clearExistingData: false);

        var polls = await db.pollsDao.getAllPolls();
        expect(polls, hasLength(1));
        expect(polls.single.question, 'Pick multiple');
        expect(polls.single.allowsMultipleVotes, isTrue);

        var options = await db.pollOptionsDao.getOptionsForPoll(
          polls.single.id,
        );
        expect(options.map((option) => option.optionText).toList(), [
          'Alpha',
          'Beta',
        ]);
        expect(options.map((option) => option.colorHex).toList(), [
          'AA0000',
          '00BB00',
        ]);

        final alphaOption = options.firstWhere(
          (option) => option.optionText == 'Alpha',
        );
        final betaOption = options.firstWhere(
          (option) => option.optionText == 'Beta',
        );
        var alphaVotes = await db.pollVotesDao.getVotesForOption(
          alphaOption.id,
        );
        var betaVotes = await db.pollVotesDao.getVotesForOption(betaOption.id);
        expect(alphaVotes, hasLength(1));
        expect(alphaVotes.single.responseText, 'first pick');
        expect(betaVotes, hasLength(2));

        await runImport(clearExistingData: true);

        polls = await db.pollsDao.getAllPolls();
        expect(polls, hasLength(1));
        expect(polls.single.question, 'Pick multiple');
        expect(polls.single.allowsMultipleVotes, isTrue);

        options = await db.pollOptionsDao.getOptionsForPoll(polls.single.id);
        expect(options.map((option) => option.optionText).toList(), [
          'Alpha',
          'Beta',
        ]);
        expect(options.map((option) => option.colorHex).toList(), [
          'AA0000',
          '00BB00',
        ]);

        final overwrittenAlphaOption = options.firstWhere(
          (option) => option.optionText == 'Alpha',
        );
        final overwrittenBetaOption = options.firstWhere(
          (option) => option.optionText == 'Beta',
        );
        alphaVotes = await db.pollVotesDao.getVotesForOption(
          overwrittenAlphaOption.id,
        );
        betaVotes = await db.pollVotesDao.getVotesForOption(
          overwrittenBetaOption.id,
        );
        expect(alphaVotes, hasLength(1));
        expect(alphaVotes.single.responseText, 'first pick');
        expect(betaVotes, hasLength(2));
      },
    );

    test(
      'mocked API import falls back to shallow poll summaries when detail fetch fails',
      () async {
        final client = SpApiClient(
          token: 'test-token',
          httpClient: MockClient((request) async {
            final path = request.url.path;

            if (path == '/v1/me') {
              return http.Response(
                jsonEncode({'_id': 'sys1', 'uid': 'sys1', 'username': 'test'}),
                200,
              );
            }
            if (path.startsWith('/v1/members/')) {
              return http.Response(
                jsonEncode([
                  {'_id': 'mem1', 'name': 'Kai', 'pronouns': 'he/him'},
                ]),
                200,
              );
            }
            if (path == '/v1/frontHistory') {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/customFronts/') ||
                path.startsWith('/v1/groups/') ||
                path.startsWith('/v1/customFields/') ||
                path.startsWith('/v1/notes/') ||
                path.startsWith('/v1/comments/') ||
                path.startsWith('/v1/board/member/')) {
              return http.Response(jsonEncode(const []), 200);
            }
            if (path.startsWith('/v1/polls/')) {
              return http.Response(
                jsonEncode([
                  {
                    '_id': 'poll1',
                    'question': 'Fallback poll',
                    'custom': true,
                    'options': [
                      {'text': 'Fallback', 'color': '#123456'},
                    ],
                  },
                ]),
                200,
              );
            }
            if (path == '/v1/poll/sys1/poll1') {
              return http.Response('boom', 500);
            }
            if (path == '/v1/chat/categories' || path == '/v1/chat/channels') {
              return http.Response(jsonEncode(const []), 200);
            }

            return http.Response('Not found', 404);
          }),
        );
        addTearDown(client.dispose);

        final exportData = await client.fetchAll();
        expect(exportData.polls, hasLength(1));
        expect(exportData.polls.single.options.map((o) => o.name).toList(), [
          'Fallback',
        ]);

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
          categoriesRepo: DriftConversationCategoriesRepository(
            db.conversationCategoriesDao,
            null,
          ),
          spImportDao: db.spImportDao,
          downloadAvatars: false,
        );

        expect(result.pollsImported, 1);

        final polls = await db.pollsDao.getAllPolls();
        expect(polls, hasLength(1));
        expect(polls.single.question, 'Fallback poll');

        final options = await db.pollOptionsDao.getOptionsForPoll(
          polls.single.id,
        );
        expect(options, hasLength(1));
        expect(options.single.optionText, 'Fallback');
        expect(options.single.colorHex, '123456');

        final votes = await db.pollVotesDao.getAllVotes();
        expect(votes, isEmpty);
      },
    );
  });
}
