import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  final now = DateTime(2026, 5, 15);

  Member member(String id, {bool isAdmin = false}) =>
      Member(id: id, name: id, createdAt: now, isAdmin: isAdmin);

  Conversation groupConversation({
    String creatorId = 'alice',
    List<String> participantIds = const ['alice', 'bob', 'carol'],
  }) => Conversation(
    id: 'conv-1',
    createdAt: now,
    lastActivityAt: now,
    title: 'General',
    creatorId: creatorId,
    participantIds: participantIds,
  );

  FrontingSession front(String memberId) => FrontingSession(
    id: 'front-$memberId',
    startTime: now,
    memberId: memberId,
  );

  ProviderContainer buildContainer({
    required Conversation conversation,
    required List<Member> members,
    required List<FrontingSession> fronts,
    FakeConversationRepository? conversationRepo,
    _FakeChatMessageRepository? messageRepo,
  }) {
    final repo = conversationRepo ?? FakeConversationRepository();
    if (repo.conversations.isEmpty) {
      repo.conversations.add(conversation);
    }
    final memberRepo = FakeMemberRepository()..seed(members);
    return ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repo),
        memberRepositoryProvider.overrideWithValue(memberRepo),
        chatMessageRepositoryProvider.overrideWithValue(
          messageRepo ?? _FakeChatMessageRepository(),
        ),
        activeMembersProvider.overrideWithValue(AsyncValue.data(members)),
        activeSessionsProvider.overrideWithValue(AsyncValue.data(fronts)),
      ],
    );
  }

  group('currentFrontCanManageConversationProvider', () {
    test('returns true when any current front is the owner', () {
      final conversation = groupConversation();
      final container = buildContainer(
        conversation: conversation,
        members: [member('alice'), member('bob'), member('carol')],
        fronts: [front('carol'), front('alice')],
      );
      addTearDown(container.dispose);

      expect(
        container.read(currentFrontCanManageConversationProvider(conversation)),
        isTrue,
      );
    });

    test('returns true when any current front is an admin', () {
      final conversation = groupConversation();
      final container = buildContainer(
        conversation: conversation,
        members: [member('alice'), member('bob', isAdmin: true)],
        fronts: [front('bob')],
      );
      addTearDown(container.dispose);

      expect(
        container.read(currentFrontCanManageConversationProvider(conversation)),
        isTrue,
      );
    });

    test('returns false for regular current fronts and direct messages', () {
      final group = groupConversation();
      final groupContainer = buildContainer(
        conversation: group,
        members: [member('alice'), member('carol')],
        fronts: [front('carol')],
      );
      addTearDown(groupContainer.dispose);

      expect(
        groupContainer.read(currentFrontCanManageConversationProvider(group)),
        isFalse,
      );

      final dm = group.copyWith(isDirectMessage: true);
      final dmContainer = buildContainer(
        conversation: dm,
        members: [member('alice', isAdmin: true)],
        fronts: [front('alice')],
      );
      addTearDown(dmContainer.dispose);

      expect(
        dmContainer.read(currentFrontCanManageConversationProvider(dm)),
        isFalse,
      );
    });
  });

  group('transferCreator', () {
    test('allows transfer when an active front is an admin', () async {
      final repo = FakeConversationRepository()
        ..conversations.add(groupConversation());
      final messages = _FakeChatMessageRepository();
      final container = buildContainer(
        conversation: repo.conversations.single,
        conversationRepo: repo,
        messageRepo: messages,
        members: [
          member('alice'),
          member('bob', isAdmin: true),
          member('carol'),
        ],
        fronts: [front('bob')],
      );
      addTearDown(container.dispose);

      await container
          .read(chatNotifierProvider.notifier)
          .transferCreator('conv-1', 'carol');

      expect(repo.conversations.single.creatorId, 'carol');
      expect(messages.messages.single.isSystemMessage, isTrue);
      expect(
        messages.messages.single.content,
        'carol is now the conversation owner',
      );
    });

    test('blocks transfer when no current front can manage', () async {
      final repo = FakeConversationRepository()
        ..conversations.add(groupConversation());
      final container = buildContainer(
        conversation: repo.conversations.single,
        conversationRepo: repo,
        members: [member('alice'), member('carol')],
        fronts: [front('carol')],
      );
      addTearDown(container.dispose);

      await container
          .read(chatNotifierProvider.notifier)
          .transferCreator('conv-1', 'carol');

      expect(repo.conversations.single.creatorId, 'alice');
      expect(container.read(chatNotifierProvider).hasError, isTrue);
    });
  });
}

class _FakeChatMessageRepository implements ChatMessageRepository {
  final messages = <ChatMessage>[];

  @override
  Future<void> createMessage(ChatMessage message) async {
    messages.add(message);
  }

  @override
  Future<void> deleteMessage(String id) async {
    messages.removeWhere((message) => message.id == id);
  }

  @override
  Future<List<ChatMessage>> getAllMessages() async =>
      List.unmodifiable(messages);

  @override
  Future<ChatMessage?> getLatestMessage(String conversationId) async {
    final candidates = messages
        .where((message) => message.conversationId == conversationId)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return candidates.first;
  }

  @override
  Future<ChatMessage?> getMessageById(String id) async {
    return messages.cast<ChatMessage?>().firstWhere(
      (message) => message?.id == id,
      orElse: () => null,
    );
  }

  @override
  Future<List<ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    return messages
        .where((message) => message.conversationId == conversationId)
        .toList();
  }

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
  Future<void> updateMessage(ChatMessage message) async {
    final index = messages.indexWhere((existing) => existing.id == message.id);
    if (index >= 0) messages[index] = message;
  }

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
  Stream<ChatMessage?> watchLatestMessage(String conversationId) {
    return Stream.fromFuture(getLatestMessage(conversationId));
  }

  @override
  Stream<List<ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) {
    return Stream.fromFuture(getMessagesForConversation(conversationId));
  }

  @override
  Stream<List<ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) {
    return Stream.fromFuture(getMessagesForConversation(conversationId));
  }

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
