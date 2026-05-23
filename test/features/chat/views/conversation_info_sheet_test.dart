import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/conversation_info_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'alice';
}

void main() {
  testWidgets('category assignment opens a dialog from conversation info', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 9);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
      ]);
    final category = ConversationCategory(
      id: 'fandoms',
      name: 'Fandoms',
      displayOrder: 0,
      createdAt: now,
      modifiedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(await memberRepo.getAllMembers()),
          ),
          activeSessionsProvider.overrideWithValue(
            const AsyncValue.data(<FrontingSession>[]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value([category]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'conv-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsOneWidget);
    expect(find.text('Fandoms'), findsOneWidget);

    await tester.tap(find.text('Fandoms'));
    await tester.pumpAndSettle();

    expect(find.byType(PrismDialog), findsNothing);
    expect(conversationRepo.conversations.single.categoryId, 'fandoms');
  });

  testWidgets(
    'co-fronting admin can transfer group ownership from conversation info',
    (tester) async {
      final now = DateTime(2026, 5, 15);
      final conversationRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'conv-1',
            createdAt: now,
            lastActivityAt: now,
            title: 'General',
            creatorId: 'alice',
            participantIds: const ['alice', 'bob', 'carol'],
          ),
        );
      final memberRepo = FakeMemberRepository()
        ..seed([
          Member(id: 'alice', name: 'Alice', createdAt: now),
          Member(id: 'bob', name: 'Bob', createdAt: now, isAdmin: true),
          Member(id: 'carol', name: 'Carol', createdAt: now),
        ]);
      final messages = _FakeChatMessageRepository();
      final activeMembers = await memberRepo.getAllMembers();
      final activeFronts = [
        FrontingSession(id: 'front-bob', startTime: now, memberId: 'bob'),
        FrontingSession(id: 'front-carol', startTime: now, memberId: 'carol'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(conversationRepo),
            chatMessageRepositoryProvider.overrideWithValue(messages),
            memberRepositoryProvider.overrideWithValue(memberRepo),
            activeMembersProvider.overrideWithValue(
              AsyncValue.data(activeMembers),
            ),
            activeSessionsProvider.overrideWithValue(
              AsyncValue.data(activeFronts),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(const <ConversationCategory>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ConversationInfoSheet(
                conversationId: 'conv-1',
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ownerRow = find.byKey(const ValueKey('conversation-owner-row'));
      expect(ownerRow, findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(ownerRow, findsOneWidget);

      await tester.tap(ownerRow);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      final picker = find.byType(MemberSearchSheet);
      expect(
        find.descendant(of: picker, matching: find.text('Alice')),
        findsNothing,
      );
      expect(
        find.descendant(of: picker, matching: find.text('Bob')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text('Carol')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: picker, matching: find.text('Carol')),
      );
      await tester.pumpAndSettle();

      expect(conversationRepo.conversations.single.creatorId, 'carol');
      expect(messages.messages.single.content, contains('Carol'));
    },
  );

  testWidgets('include-everyone toggle is only shown in edit mode', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 15);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
      ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          chatMessageRepositoryProvider.overrideWithValue(
            _FakeChatMessageRepository(),
          ),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(await memberRepo.getAllMembers()),
          ),
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([
              FrontingSession(
                id: 'front-alice',
                startTime: now,
                memberId: 'alice',
              ),
            ]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value(const <ConversationCategory>[]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'conv-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Include everyone'), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Include everyone'), findsOneWidget);
  });

  testWidgets(
    'everyone-group owner transfer does not count Unknown as a candidate',
    (tester) async {
      final now = DateTime(2026, 5, 15);
      final unknown = Member(
        id: unknownSentinelMemberId,
        name: 'Unknown',
        createdAt: now,
      );
      final conversationRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'everyone-1',
            createdAt: now,
            lastActivityAt: now,
            title: 'Everyone',
            creatorId: 'alice',
            participantIds: const ['alice'],
            includesAllMembers: true,
          ),
        );
      final memberRepo = FakeMemberRepository()
        ..seed([Member(id: 'alice', name: 'Alice', createdAt: now), unknown]);
      final activeMembers = await memberRepo.getAllMembers();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(conversationRepo),
            chatMessageRepositoryProvider.overrideWithValue(
              _FakeChatMessageRepository(),
            ),
            memberRepositoryProvider.overrideWithValue(memberRepo),
            speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
            activeMembersProvider.overrideWithValue(
              AsyncValue.data(activeMembers),
            ),
            activeSessionsProvider.overrideWithValue(
              AsyncValue.data([
                FrontingSession(
                  id: 'front-alice',
                  startTime: now,
                  memberId: 'alice',
                ),
              ]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(const <ConversationCategory>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ConversationInfoSheet(
                conversationId: 'everyone-1',
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('conversation-owner-row')),
        findsNothing,
        reason: 'Unknown must not make the owner-transfer affordance appear.',
      );
    },
  );

  testWidgets('everyone-group owner transfer picker hides Unknown', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 15);
    final unknown = Member(
      id: unknownSentinelMemberId,
      name: 'Unknown',
      createdAt: now,
    );
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'everyone-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Everyone',
          creatorId: 'alice',
          participantIds: const ['alice'],
          includesAllMembers: true,
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: now),
        Member(id: 'bob', name: 'Bob', createdAt: now),
        unknown,
      ]);
    final activeMembers = await memberRepo.getAllMembers();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          chatMessageRepositoryProvider.overrideWithValue(
            _FakeChatMessageRepository(),
          ),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(activeMembers),
          ),
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([
              FrontingSession(
                id: 'front-alice',
                startTime: now,
                memberId: 'alice',
              ),
            ]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value(const <ConversationCategory>[]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ConversationInfoSheet(
              conversationId: 'everyone-1',
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conversation-owner-row')));
    await tester.pumpAndSettle();

    final picker = find.byType(MemberSearchSheet);
    expect(picker, findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.text('Bob')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('Unknown')),
      findsNothing,
    );
  });
}

class _FakeChatMessageRepository implements ChatMessageRepository {
  final messages = <ChatMessage>[];

  @override
  Future<void> createMessage(ChatMessage message) async {
    messages.add(message);
  }

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<ChatMessage>> getAllMessages() async => messages;

  @override
  Future<ChatMessage?> getLatestMessage(String conversationId) async => null;

  @override
  Future<ChatMessage?> getMessageById(String id) async => null;

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;

  @override
  Future<List<ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async => const [];

  @override
  Future<
    List<
      ({
        String? authorId,
        String conversationId,
        String messageId,
        String snippet,
        DateTime timestamp,
      })
    >
  >
  searchMessages(String query, {int limit = 20}) async => const [];

  @override
  Future<void> updateMessage(ChatMessage message) async {}

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value(const {});

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) => Stream.value(const {});

  @override
  Stream<ChatMessage?> watchLatestMessage(String conversationId) =>
      Stream.value(null);

  @override
  Stream<List<ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) => Stream.value(const []);

  @override
  Stream<List<ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) => Stream.value(const []);

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) =>
      Stream.value(0);

  @override
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) => Stream.value(0);
}
