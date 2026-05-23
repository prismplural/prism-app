import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
}

class _CountingChatMessageRepository implements ChatMessageRepository {
  int mentionWatchCalls = 0;

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) {
    mentionWatchCalls += 1;
    return Stream.value(conversationSince.keys.toSet());
  }

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value({for (final id in conversationSince.keys) id: 1});

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
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId,
      })
    >
  >
  searchMessages(String query, {int limit = 50}) async => const [];

  @override
  Future<void> updateMessage(ChatMessage message) async {}

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

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;
}

void main() {
  final now = DateTime(2026, 5, 1);
  final later = now.add(const Duration(hours: 1));

  Conversation dm(
    String id, {
    required List<String> participants,
    DateTime? lastActivity,
    Map<String, DateTime>? lastReadTimestamps,
    List<String> mutedBy = const [],
    List<String> archivedBy = const [],
  }) {
    return Conversation(
      id: id,
      createdAt: now,
      lastActivityAt: lastActivity ?? later,
      isDirectMessage: true,
      participantIds: participants,
      mutedByMemberIds: mutedBy,
      archivedByMemberIds: archivedBy,
      lastReadTimestamps: lastReadTimestamps ?? const {},
    );
  }

  Conversation groupChat(
    String id, {
    required List<String> participants,
    DateTime? lastActivity,
    Map<String, DateTime>? lastReadTimestamps,
    List<String> mutedBy = const [],
    List<String> archivedBy = const [],
  }) {
    return Conversation(
      id: id,
      createdAt: now,
      lastActivityAt: lastActivity ?? later,
      title: 'Group $id',
      isDirectMessage: false,
      participantIds: participants,
      mutedByMemberIds: mutedBy,
      archivedByMemberIds: archivedBy,
      lastReadTimestamps: lastReadTimestamps ?? const {},
    );
  }

  ProviderContainer buildContainer({
    required String? speakingAs,
    required List<Conversation> conversations,
    Map<String, String> badgePrefs = const {},
  }) {
    return ProviderContainer(
      overrides: [
        speakingAsProvider.overrideWith(
          () => _FixedSpeakingAsNotifier(speakingAs),
        ),
        conversationsProvider.overrideWith(
          (ref) => Stream.value(conversations),
        ),
        chatBadgePreferencesProvider.overrideWithValue(badgePrefs),
      ],
    );
  }

  Future<void> settle(ProviderContainer container) async {
    // Let the conversationsProvider stream emit its initial value before
    // synchronous Providers read it.
    container.listen(conversationsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  group('mention utility helper', () {
    test('containsMention matches member-id mentions', () {
      const memberId = '00000000-0000-0000-0000-000000000001';
      expect(containsMention('Hey @[$memberId] check this', memberId), isTrue);
      expect(containsMention('Hello world', memberId), isFalse);
    });
  });

  group('unreadDmCountProvider', () {
    test('returns 0 with no unread DMs', () async {
      final container = buildContainer(
        speakingAs: 'alice',
        conversations: [
          dm(
            'dm-1',
            participants: ['alice', 'bob'],
            lastReadTimestamps: {'alice': later.add(const Duration(hours: 1))},
          ),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);
      expect(container.read(unreadDmCountProvider), 0);
    });

    test('counts unread DMs and groups independently', () async {
      final container = buildContainer(
        speakingAs: 'alice',
        conversations: [
          dm('dm-1', participants: ['alice', 'bob']),
          dm('dm-2', participants: ['alice', 'carol']),
          groupChat('group-1', participants: ['alice', 'bob']),
          groupChat('group-2', participants: ['alice', 'carol']),
          groupChat('group-3', participants: ['alice', 'dave']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadDmCountProvider), 2);
      expect(container.read(unreadGroupCountProvider), 3);
      expect(container.read(unreadConversationCountProvider), 5);
    });

    test('co-fronting with no explicit pick returns 0', () async {
      final container = buildContainer(
        speakingAs: null,
        conversations: [
          dm('dm-1', participants: ['alice', 'bob']),
          groupChat('group-1', participants: ['alice', 'bob']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadDmCountProvider), 0);
      expect(container.read(unreadGroupCountProvider), 0);
    });

    test('speaking-as not a DM participant returns 0', () async {
      final container = buildContainer(
        speakingAs: 'eve',
        conversations: [
          dm('dm-1', participants: ['alice', 'bob']),
          dm('dm-2', participants: ['alice', 'carol']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadDmCountProvider), 0);
    });

    test('muted DM is excluded', () async {
      final container = buildContainer(
        speakingAs: 'alice',
        conversations: [
          dm('dm-1', participants: ['alice', 'bob'], mutedBy: ['alice']),
          dm('dm-2', participants: ['alice', 'carol']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadDmCountProvider), 1);
    });

    test('archived DM is excluded', () async {
      final container = buildContainer(
        speakingAs: 'alice',
        conversations: [
          dm('dm-1', participants: ['alice', 'bob'], archivedBy: ['alice']),
          dm('dm-2', participants: ['alice', 'carol']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadDmCountProvider), 1);
    });
  });

  group('unreadConversationCountProvider regression', () {
    test('still returns the union of DM and group unread', () async {
      final container = buildContainer(
        speakingAs: 'alice',
        conversations: [
          dm('dm-1', participants: ['alice', 'bob']),
          groupChat('group-1', participants: ['alice', 'bob']),
          groupChat('group-2', participants: ['alice', 'carol']),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      expect(container.read(unreadConversationCountProvider), 3);
      expect(container.read(unreadDmCountProvider), 1);
      expect(container.read(unreadGroupCountProvider), 2);
    });

    test('mentions-only provider uses a stable mention stream key', () async {
      final messageRepo = _CountingChatMessageRepository();
      final container = ProviderContainer(
        overrides: [
          speakingAsProvider.overrideWith(
            () => _FixedSpeakingAsNotifier('alice'),
          ),
          conversationsProvider.overrideWith(
            (ref) => Stream.value([
              dm('dm-1', participants: ['alice', 'bob']),
            ]),
          ),
          chatBadgePreferencesProvider.overrideWithValue({
            'alice': 'mentions_only',
          }),
          chatMessageRepositoryProvider.overrideWithValue(messageRepo),
        ],
      );
      addTearDown(container.dispose);
      await settle(container);

      container.listen(unreadDmCountProvider, (_, _) {});
      expect(container.read(unreadDmCountProvider), 0);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(unreadDmCountProvider), 1);
      expect(messageRepo.mentionWatchCalls, 1);
    });

    test(
      'mention conversation ids provider uses a stable stream key',
      () async {
        final messageRepo = _CountingChatMessageRepository();
        final container = ProviderContainer(
          overrides: [
            speakingAsProvider.overrideWith(
              () => _FixedSpeakingAsNotifier('alice'),
            ),
            conversationsProvider.overrideWith(
              (ref) => Stream.value([
                dm('dm-1', participants: ['alice', 'bob']),
              ]),
            ),
            chatBadgePreferencesProvider.overrideWithValue({
              'alice': 'mentions_only',
            }),
            chatMessageRepositoryProvider.overrideWithValue(messageRepo),
          ],
        );
        addTearDown(container.dispose);
        await settle(container);

        container.listen(mentionConversationIdsProvider, (_, _) {});
        expect(container.read(mentionConversationIdsProvider), isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(container.read(mentionConversationIdsProvider), {'dm-1'});
        expect(messageRepo.mentionWatchCalls, 1);
      },
    );
  });
}
