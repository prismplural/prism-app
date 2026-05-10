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

class _TestSpeakingAsNotifier extends SpeakingAsNotifier {
  _TestSpeakingAsNotifier(this._memberId);

  String? _memberId;

  @override
  String? build() => _memberId;

  @override
  void setMember(String? memberId) {
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

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 5, 8));

Conversation _conversation({
  required String id,
  required DateTime at,
  required List<String> participantIds,
  String? title,
  bool isDirectMessage = false,
}) => Conversation(
  id: id,
  createdAt: at,
  lastActivityAt: at,
  title: title,
  isDirectMessage: isDirectMessage,
  participantIds: participantIds,
);

Widget _buildSubject({int? savedTabIndex}) {
  final mockPreferences = <String, Object>{};
  if (savedTabIndex != null) {
    mockPreferences['chat.last_sub_tab'] = savedTabIndex;
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
}
