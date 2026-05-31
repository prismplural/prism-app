import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/chat_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

import '../../../helpers/fake_repositories.dart';

const _groupChatVisibilityNudgeDismissedKey =
    'chat.group_visibility_nudge.dismissed.v1';

class _TestSpeakingAsNotifier extends SpeakingAsNotifier {
  _TestSpeakingAsNotifier(this._memberId);

  String? _memberId;

  @override
  String? build() => _memberId;

  @override
  void setMember(String? memberId, {bool recordLastUsed = true}) {
    _memberId = memberId;
    state = memberId;
  }
}

class _EmptyChatMessageRepository implements ChatMessageRepository {
  @override
  Future<void> createMessage(domain.ChatMessage message) async {}

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<domain.ChatMessage>> getAllMessages() async => [];

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async =>
      null;

  @override
  Future<domain.ChatMessage?> getMessageById(String id) async => null;

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;

  @override
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async => [];

  @override
  Future<
    List<
      ({
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId,
      })
    >
  >
  searchMessages(String query, {int limit = 50}) async => [];

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {}

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value({});

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) => Stream.value({});

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) =>
      Stream.value(null);

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) => Stream.value([]);

  @override
  Stream<List<domain.ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) => Stream.value([]);

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

class _CountingConversationRepository extends FakeConversationRepository {
  int getAllConversationsCallCount = 0;

  @override
  Future<List<Conversation>> getAllConversations() async {
    getAllConversationsCallCount += 1;
    return super.getAllConversations();
  }
}

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 5, 8));

Conversation _conversation({
  required String id,
  required DateTime at,
  required List<String> participantIds,
  String? title,
  bool isDirectMessage = false,
  bool includesAllMembers = false,
}) => Conversation(
  id: id,
  createdAt: at,
  lastActivityAt: at,
  title: title,
  isDirectMessage: isDirectMessage,
  participantIds: participantIds,
  includesAllMembers: includesAllMembers,
);

Widget _buildSubject({
  int? savedTabIndex,
  bool groupVisibilityNudgeDismissed = false,
}) {
  final mockPreferences = <String, Object>{};
  if (savedTabIndex != null) {
    mockPreferences['chat.last_sub_tab'] = savedTabIndex;
  }
  if (groupVisibilityNudgeDismissed) {
    mockPreferences[_groupChatVisibilityNudgeDismissedKey] = true;
  }
  SharedPreferences.setMockInitialValues(mockPreferences);

  final now = DateTime(2026, 5, 8, 12);
  final alice = _member('alice', 'Alice');
  final bob = _member('bob', 'Bob');
  final carol = _member('carol', 'Carol');
  final dave = _member('dave', 'Dave');
  final members = FakeMemberRepository()..seed([alice, bob, carol, dave]);
  final conversations = FakeConversationRepository()
    ..conversations.addAll([
      _conversation(
        id: 'dm-1',
        at: now,
        participantIds: const ['alice', 'bob'],
        isDirectMessage: true,
      ),
      _conversation(
        id: 'dm-2',
        at: now.subtract(const Duration(seconds: 30)),
        participantIds: const ['carol', 'dave'],
        isDirectMessage: true,
      ),
      _conversation(
        id: 'group-1',
        at: now.subtract(const Duration(minutes: 1)),
        participantIds: const ['alice', 'bob', 'carol'],
        title: 'Planning',
        includesAllMembers: true,
      ),
    ]);

  return ProviderScope(
    overrides: [
      memberRepositoryProvider.overrideWithValue(members),
      conversationRepositoryProvider.overrideWithValue(conversations),
      chatMessageRepositoryProvider.overrideWithValue(
        _EmptyChatMessageRepository(),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      currentChatViewerProvider.overrideWithValue(alice),
      speakingAsProvider.overrideWith(() => _TestSpeakingAsNotifier('alice')),
      conversationCategoriesProvider.overrideWith((ref) => Stream.value([])),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: ChatScreen(),
    ),
  );
}

void main() {
  testWidgets('filters the chat list by direct messages and group chats', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Direct Messages'), findsOneWidget);
    expect(find.text('Group Chats'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Group Chats')).dx,
      lessThan(tester.getTopLeft(find.text('Direct Messages')).dx),
    );
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);

    await tester.tap(find.text('Direct Messages'));
    await tester.pumpAndSettle();

    expect(find.text('Planning'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('chat.last_sub_tab'), 0);
  });

  testWidgets('group chat visibility nudge dismisses persistently', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(
      find.text('Some group chats are visible to everyone'),
      findsOneWidget,
    );
    expect(
      find.text('You can change this in Conversation Details.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Some group chats are visible to everyone'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_groupChatVisibilityNudgeDismissedKey), isTrue);

    await tester.pumpWidget(_buildSubject(groupVisibilityNudgeDismissed: true));
    await tester.pumpAndSettle();

    expect(find.text('Some group chats are visible to everyone'), findsNothing);
  });

  testWidgets('restores the last selected group chat list tab', (tester) async {
    await tester.pumpWidget(_buildSubject(savedTabIndex: 1));
    await tester.pumpAndSettle();

    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('restores the last selected direct messages chat list tab', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject(savedTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Planning'), findsNothing);
  });

  testWidgets(
    'puts search in the overflow menu to make room for member picker',
    (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('chatSpeakingAsAppBarSelector')),
        findsOneWidget,
      );
      expect(find.byTooltip('Search messages'), findsNothing);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Search messages'), findsOneWidget);
    },
  );

  testWidgets('appbar member picker changes the direct message viewer', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject(savedTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chatSpeakingAsAppBarSelector')));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Search')).dy,
      lessThan(tester.getTopLeft(find.text('Alice')).dy),
      reason: 'Search should be the first visible appbar picker option.',
    );

    await tester.tap(find.text('Carol'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsNothing);
    expect(find.text('Dave'), findsOneWidget);
  });

  testWidgets('appbar member picker tooltip matches tap behavior', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject(savedTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Speaking as Alice. Tap to change.'), findsOneWidget);
    expect(
      find.byTooltip('Speaking as Alice. Double tap to change.'),
      findsNothing,
    );
  });

  testWidgets('appbar member picker Search row opens full member search', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject(savedTabIndex: 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chatSpeakingAsAppBarSelector')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets(
    'default seed no-op latches after checking hidden conversations',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final now = DateTime(2026, 5, 8, 12);
      final alice = _member('alice', 'Alice');
      final bob = _member('bob', 'Bob');
      final members = FakeMemberRepository()..seed([alice, bob]);
      final conversations = _CountingConversationRepository()
        ..conversations.add(
          _conversation(
            id: 'hidden-existing',
            at: now,
            participantIds: const ['alice', 'bob'],
            title: 'All Members',
          ),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            memberRepositoryProvider.overrideWithValue(members),
            conversationRepositoryProvider.overrideWithValue(conversations),
            chatMessageRepositoryProvider.overrideWithValue(
              _EmptyChatMessageRepository(),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            currentChatViewerProvider.overrideWithValue(null),
            speakingAsProvider.overrideWith(
              () => _TestSpeakingAsNotifier(null),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: ChatScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(conversations.conversations, hasLength(1));
      expect(conversations.getAllConversationsCallCount, 1);

      await tester.tap(find.text('Direct Messages'));
      await tester.pump();
      await tester.pump();

      expect(conversations.conversations, hasLength(1));
      expect(conversations.getAllConversationsCallCount, 1);
    },
  );

  group('admin moderation section', () {
    Widget buildAdminSubject() {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final now = DateTime(2026, 5, 8, 12);
      final admin = Member(
        id: 'admin',
        name: 'Admin',
        createdAt: now,
        isAdmin: true,
      );
      final bob = _member('bob', 'Bob');
      final carol = _member('carol', 'Carol');
      final members = FakeMemberRepository()..seed([admin, bob, carol]);
      final conversations = FakeConversationRepository()
        ..conversations.addAll([
          // Group the admin IS a participant of — regular section.
          _conversation(
            id: 'group-mine',
            at: now,
            participantIds: const ['admin', 'bob'],
            title: 'Admin Hangout',
          ),
          // Group the admin is NOT a participant of — admin-only section.
          _conversation(
            id: 'group-moderated',
            at: now.subtract(const Duration(minutes: 1)),
            participantIds: const ['bob', 'carol'],
            title: 'Private Crew',
          ),
        ]);

      return ProviderScope(
        overrides: [
          memberRepositoryProvider.overrideWithValue(members),
          conversationRepositoryProvider.overrideWithValue(conversations),
          chatMessageRepositoryProvider.overrideWithValue(
            _EmptyChatMessageRepository(),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          currentChatViewerProvider.overrideWithValue(admin),
          speakingAsProvider.overrideWith(
            () => _TestSpeakingAsNotifier('admin'),
          ),
          conversationCategoriesProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: ChatScreen(),
        ),
      );
    }

    testWidgets(
      'renders non-participant groups under "Admin · Not a member" section',
      (tester) async {
        await tester.pumpWidget(buildAdminSubject());
        await tester.pumpAndSettle();

        // Both groups visible: one as a participant, one via admin override.
        expect(find.text('Admin Hangout'), findsOneWidget);
        expect(find.text('Private Crew'), findsOneWidget);
        expect(find.text('Admin · Not a member'), findsOneWidget);

        // The admin section sits below the participant section.
        expect(
          tester.getTopLeft(find.text('Admin · Not a member')).dy,
          greaterThan(tester.getTopLeft(find.text('Admin Hangout')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Private Crew')).dy,
          greaterThan(tester.getTopLeft(find.text('Admin · Not a member')).dy),
        );
      },
    );

    testWidgets(
      'no admin section when every visible group is a participant chat',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final now = DateTime(2026, 5, 8, 12);
        final admin = Member(
          id: 'admin',
          name: 'Admin',
          createdAt: now,
          isAdmin: true,
        );
        final bob = _member('bob', 'Bob');
        final members = FakeMemberRepository()..seed([admin, bob]);
        final conversations = FakeConversationRepository()
          ..conversations.add(
            _conversation(
              id: 'group-mine',
              at: now,
              participantIds: const ['admin', 'bob'],
              title: 'Admin Hangout',
            ),
          );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              memberRepositoryProvider.overrideWithValue(members),
              conversationRepositoryProvider.overrideWithValue(conversations),
              chatMessageRepositoryProvider.overrideWithValue(
                _EmptyChatMessageRepository(),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              currentChatViewerProvider.overrideWithValue(admin),
              speakingAsProvider.overrideWith(
                () => _TestSpeakingAsNotifier('admin'),
              ),
              conversationCategoriesProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
              allGroupsProvider.overrideWith(
                (ref) => Stream.value(const <MemberGroup>[]),
              ),
              allGroupEntriesProvider.overrideWith(
                (ref) => Stream.value(const <MemberGroupEntry>[]),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: [Locale('en')],
              home: ChatScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Admin Hangout'), findsOneWidget);
        expect(
          find.text('Admin · Not a member'),
          findsNothing,
          reason: 'Header should only appear when admin-only groups exist.',
        );
      },
    );

    testWidgets(
      'null speakingAs renders the pick-speaker banner instead of any chats',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final now = DateTime(2026, 5, 8, 12);
        final alice = _member('alice', 'Alice');
        final bob = _member('bob', 'Bob');
        final members = FakeMemberRepository()..seed([alice, bob]);
        final conversations = FakeConversationRepository()
          ..conversations.add(
            _conversation(
              id: 'group-1',
              at: now,
              participantIds: const ['alice', 'bob'],
              title: 'Planning',
            ),
          );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              memberRepositoryProvider.overrideWithValue(members),
              conversationRepositoryProvider.overrideWithValue(conversations),
              chatMessageRepositoryProvider.overrideWithValue(
                _EmptyChatMessageRepository(),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              currentChatViewerProvider.overrideWithValue(null),
              speakingAsProvider.overrideWith(
                () => _TestSpeakingAsNotifier(null),
              ),
              conversationCategoriesProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
              allGroupsProvider.overrideWith(
                (ref) => Stream.value(const <MemberGroup>[]),
              ),
              allGroupEntriesProvider.overrideWith(
                (ref) => Stream.value(const <MemberGroupEntry>[]),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: [Locale('en')],
              home: ChatScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Pick a member'),
          findsOneWidget,
          reason: 'banner should prompt the user to pick a speaker',
        );
        expect(
          find.text('Planning'),
          findsNothing,
          reason: 'group content must NOT leak when no member is picked',
        );
      },
    );

    testWidgets('non-admin viewer never sees the admin section', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final now = DateTime(2026, 5, 8, 12);
      final bob = _member('bob', 'Bob');
      final carol = _member('carol', 'Carol');
      final members = FakeMemberRepository()..seed([bob, carol]);
      // Two groups: one bob is in (so the list isn't empty), one he's not.
      // Without the admin override, only the participant group shows.
      final conversations = FakeConversationRepository()
        ..conversations.addAll([
          _conversation(
            id: 'group-mine',
            at: now,
            participantIds: const ['bob', 'carol'],
            title: 'Shared',
          ),
          _conversation(
            id: 'group-private',
            at: now.subtract(const Duration(minutes: 1)),
            participantIds: const ['carol'],
            title: 'Carol Only',
          ),
        ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            memberRepositoryProvider.overrideWithValue(members),
            conversationRepositoryProvider.overrideWithValue(conversations),
            chatMessageRepositoryProvider.overrideWithValue(
              _EmptyChatMessageRepository(),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            currentChatViewerProvider.overrideWithValue(bob),
            speakingAsProvider.overrideWith(
              () => _TestSpeakingAsNotifier('bob'),
            ),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared'), findsOneWidget);
      expect(find.text('Carol Only'), findsNothing);
      expect(find.text('Admin · Not a member'), findsNothing);
    });
  });
}
