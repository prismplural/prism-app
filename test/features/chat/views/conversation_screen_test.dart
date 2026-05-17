import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/conversation_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'admin';
}

class _NoopChatNotifier extends ChatNotifier {
  @override
  Future<void> markConversationAsRead(
    String conversationId,
    String memberId,
  ) async {}
}

class _EmptyChatMessageRepository implements ChatMessageRepository {
  @override
  Future<void> createMessage(ChatMessage message) async {}

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<ChatMessage>> getAllMessages() async => const [];

  @override
  Future<ChatMessage?> getLatestMessage(String conversationId) async => null;

  @override
  Future<ChatMessage?> getMessageById(String id) async => null;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return '/tmp/prism-test';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  testWidgets('admin non-participant group shows read-only posting banner', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 16);
    final admin = Member(
      id: 'admin',
      name: 'Admin',
      createdAt: now,
      isAdmin: true,
    );
    final alice = Member(id: 'alice', name: 'Alice', createdAt: now);
    final bob = Member(id: 'bob', name: 'Bob', createdAt: now);
    final memberRepo = FakeMemberRepository()..seed([admin, alice, bob]);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Private Crew',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(conversationRepo),
          chatMessageRepositoryProvider.overrideWithValue(
            _EmptyChatMessageRepository(),
          ),
          chatNotifierProvider.overrideWith(_NoopChatNotifier.new),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
          currentChatViewerProvider.overrideWithValue(admin),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(await memberRepo.getAllMembers()),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: ConversationScreen(conversationId: 'conv-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viewing as admin. Posting is disabled.'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });
}
