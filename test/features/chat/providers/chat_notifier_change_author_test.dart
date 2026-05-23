import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
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

// ---------------------------------------------------------------------------
// Inline fake message repository (tracks calls for spy assertions)
// ---------------------------------------------------------------------------

class _SpyChatMessageRepository implements ChatMessageRepository {
  final _messages = <ChatMessage>[];
  int updateCallCount = 0;
  // Map of messageId → tombstone state; defaults to false (not deleted).
  final _tombstoned = <String, bool>{};

  void seed(List<ChatMessage> msgs) {
    _messages
      ..clear()
      ..addAll(msgs);
  }

  void setTombstoned(String messageId, {bool deleted = true}) {
    _tombstoned[messageId] = deleted;
  }

  @override
  Future<ChatMessage?> getMessageById(String id) async =>
      _messages.cast<ChatMessage?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      );

  @override
  Future<void> updateMessage(ChatMessage message) async {
    updateCallCount++;
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) _messages[idx] = message;
  }

  @override
  Future<void> createMessage(ChatMessage message) async =>
      _messages.add(message);

  @override
  Future<void> deleteMessage(String id) async =>
      _messages.removeWhere((m) => m.id == id);

  @override
  Future<ChatMessage?> getLatestMessage(String conversationId) async {
    final candidates = _messages
        .where((m) => m.conversationId == conversationId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<List<ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async =>
      _messages
          .where((m) => m.conversationId == conversationId)
          .toList();

  @override
  Future<List<ChatMessage>> getAllMessages() async =>
      List.unmodifiable(_messages);

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
      Stream.fromFuture(getLatestMessage(conversationId));

  @override
  Stream<List<ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) =>
      Stream.fromFuture(getMessagesForConversation(conversationId));

  @override
  Stream<List<ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) =>
      Stream.fromFuture(getMessagesForConversation(conversationId));

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) =>
      Stream.value(0);

  @override
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) => Stream.value(0);

  @override
  Future<bool> isMessageDeleted(String messageId) async =>
      _tombstoned[messageId] ?? false;
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

void main() {
  final now = DateTime(2026, 5, 23);

  Member member(String id, {bool isAdmin = false, bool isActive = true}) =>
      Member(
        id: id,
        name: id,
        createdAt: now,
        isAdmin: isAdmin,
        isActive: isActive,
      );

  FrontingSession front(String memberId) => FrontingSession(
    id: 'front-$memberId',
    startTime: now,
    memberId: memberId,
  );

  Conversation groupConv({
    String id = 'conv-1',
    String creatorId = 'alice',
    List<String> participantIds = const ['alice', 'bob', 'carol'],
  }) => Conversation(
    id: id,
    createdAt: now,
    lastActivityAt: now,
    title: 'General',
    creatorId: creatorId,
    participantIds: participantIds,
  );

  ChatMessage msg({
    String id = 'msg-1',
    String conversationId = 'conv-1',
    String? authorId = 'bob',
    DateTime? editedAt,
    bool isSystemMessage = false,
  }) => ChatMessage(
    id: id,
    content: 'Hello',
    timestamp: now,
    conversationId: conversationId,
    authorId: authorId,
    editedAt: editedAt,
    isSystemMessage: isSystemMessage,
  );

  /// Build a container. [fronts] determines speakingAs via SpeakingAsNotifier.
  ProviderContainer buildContainer({
    required FakeConversationRepository convRepo,
    required _SpyChatMessageRepository msgRepo,
    required FakeMemberRepository memberRepo,
    List<Member>? activeMembers,
    List<FrontingSession> fronts = const [],
  }) {
    final members =
        activeMembers ?? [member('alice'), member('bob'), member('carol')];
    return ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(convRepo),
        chatMessageRepositoryProvider.overrideWithValue(msgRepo),
        memberRepositoryProvider.overrideWithValue(memberRepo),
        activeMembersProvider.overrideWithValue(AsyncValue.data(members)),
        activeSessionsProvider.overrideWithValue(AsyncValue.data(fronts)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Happy path
  // -------------------------------------------------------------------------

  test('changeMessageAuthor writes new authorId without touching editedAt',
      () async {
    final conv = groupConv();
    final original = msg(authorId: 'bob', editedAt: now);

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()..seed([original]);
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    // alice is fronting → speakingAs = 'alice' (conversation creator).
    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'carol');

    expect(container.read(chatNotifierProvider).hasError, isFalse);

    final updated = await msgRepo.getMessageById('msg-1');
    expect(updated?.authorId, 'carol', reason: 'authorId must be updated');
    expect(
      updated?.editedAt,
      now,
      reason: 'editedAt must NOT be bumped by re-attribution',
    );
  });

  // -------------------------------------------------------------------------
  // No-op: same author
  // -------------------------------------------------------------------------

  test('changeMessageAuthor is a no-op when newAuthorId equals current authorId',
      () async {
    final conv = groupConv();
    final original = msg(authorId: 'bob');

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()..seed([original]);
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'bob');

    expect(msgRepo.updateCallCount, 0, reason: 'no write should occur');
  });

  // -------------------------------------------------------------------------
  // Permission denial
  // -------------------------------------------------------------------------

  test('changeMessageAuthor throws StateError when permission is denied',
      () async {
    // Use a DM: 'dave' is not a participant, so canWrite = false and
    // canManage = false → canChangeMessageAuthor returns false.
    final dmConv = Conversation(
      id: 'conv-dm',
      createdAt: now,
      lastActivityAt: now,
      isDirectMessage: true,
      // alice and bob are the DM participants; dave is not.
      participantIds: const ['alice', 'bob'],
    );
    final original = ChatMessage(
      id: 'msg-1',
      content: 'Hey',
      timestamp: now,
      conversationId: 'conv-dm',
      authorId: 'alice',
    );

    final convRepo = FakeConversationRepository()..conversations.add(dmConv);
    final msgRepo = _SpyChatMessageRepository()..seed([original]);
    final members = [
      member('alice'),
      member('bob'),
      member('dave'),
    ];
    final memberRepo = FakeMemberRepository()..seed(members);

    // dave is fronting but is NOT a participant of the DM.
    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      activeMembers: members,
      fronts: [front('dave')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'bob');

    expect(
      container.read(chatNotifierProvider).hasError,
      isTrue,
      reason: 'non-participant should be denied',
    );
    expect(
      container.read(chatNotifierProvider).error,
      isA<StateError>(),
    );
  });

  // -------------------------------------------------------------------------
  // Invalid candidate
  // -------------------------------------------------------------------------

  test('changeMessageAuthor throws StateError for unknown candidate id',
      () async {
    final conv = groupConv();
    final original = msg(authorId: 'bob');

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()..seed([original]);
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'nonexistent-member');

    expect(container.read(chatNotifierProvider).hasError, isTrue);
    expect(container.read(chatNotifierProvider).error, isA<StateError>());
  });

  // -------------------------------------------------------------------------
  // Sentinel accepted
  // -------------------------------------------------------------------------

  test('changeMessageAuthor accepts unknownSentinelMemberId', () async {
    final conv = groupConv();
    final original = msg(authorId: 'bob');

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()..seed([original]);
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', unknownSentinelMemberId);

    expect(container.read(chatNotifierProvider).hasError, isFalse);

    final updated = await msgRepo.getMessageById('msg-1');
    expect(
      updated?.authorId,
      unknownSentinelMemberId,
      reason: 'sentinel should be written as new authorId',
    );
  });

  // -------------------------------------------------------------------------
  // Tombstoned message — silent no-op
  // -------------------------------------------------------------------------

  test('changeMessageAuthor is a silent no-op on tombstoned message', () async {
    final conv = groupConv();
    final original = msg(authorId: 'bob');

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()
      ..seed([original])
      ..setTombstoned('msg-1');
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'carol');

    expect(
      container.read(chatNotifierProvider).hasError,
      isFalse,
      reason: 'tombstoned message should not raise an error',
    );
    expect(
      msgRepo.updateCallCount,
      0,
      reason: 'updateMessage must not be called for a tombstoned message',
    );
  });

  // -------------------------------------------------------------------------
  // System message — silent no-op
  // -------------------------------------------------------------------------

  test('changeMessageAuthor is a no-op for system messages', () async {
    final conv = groupConv();
    final systemMsg = msg(authorId: null, isSystemMessage: true);

    final convRepo = FakeConversationRepository()..conversations.add(conv);
    final msgRepo = _SpyChatMessageRepository()..seed([systemMsg]);
    final memberRepo = FakeMemberRepository()
      ..seed([member('alice'), member('bob'), member('carol')]);

    final container = buildContainer(
      convRepo: convRepo,
      msgRepo: msgRepo,
      memberRepo: memberRepo,
      fronts: [front('alice')],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .changeMessageAuthor('msg-1', 'carol');

    expect(container.read(chatNotifierProvider).hasError, isFalse);
    expect(msgRepo.updateCallCount, 0, reason: 'no write for system messages');
  });
}
