import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

import '../../../helpers/fake_repositories.dart';

class _ThrowingConversationRepository extends FakeConversationRepository {
  @override
  Future<List<Conversation>> getAllConversations() async {
    throw StateError('database unavailable');
  }
}

void main() {
  test('createGroupConversation marks DM conversations correctly', () async {
    final fakeRepo = FakeConversationRepository();
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(fakeRepo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);

    final dm = await notifier.createGroupConversation(
      title: '',
      creatorId: 'ethan',
      participantIds: const ['ethan', 'zari'],
      isDirectMessage: true,
    );
    final group = await notifier.createGroupConversation(
      title: 'Group',
      creatorId: 'melanie',
      participantIds: const ['melanie', 'ethan', 'zari'],
    );

    expect(dm.isDirectMessage, isTrue);
    expect(group.isDirectMessage, isFalse);
    expect(fakeRepo.conversations.map((c) => c.isDirectMessage), [true, false]);
  });

  test(
    'seedDefaultConversationIfNeeded does not duplicate hidden legacy chats',
    () async {
      final now = DateTime(2026, 5, 21, 12);
      final fakeRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'legacy-all-members',
            createdAt: now,
            lastActivityAt: now,
            title: 'All Members',
            participantIds: const ['alice', 'bob'],
          ),
        );
      final container = ProviderContainer(
        overrides: [conversationRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final seeded = await container
          .read(chatNotifierProvider.notifier)
          .seedDefaultConversationIfNeeded(
            title: 'All Members',
            emoji: '💬',
            members: [
              Member(id: 'alice', name: 'Alice', createdAt: now),
              Member(id: 'bob', name: 'Bob', createdAt: now),
            ],
          );

      expect(seeded, isNull);
      expect(fakeRepo.conversations, hasLength(1));
    },
  );

  test(
    'seedDefaultConversationIfNeeded does not duplicate archived existing chats',
    () async {
      final now = DateTime(2026, 5, 21, 12);
      final fakeRepo = FakeConversationRepository()
        ..conversations.add(
          Conversation(
            id: 'archived-all-members',
            createdAt: now,
            lastActivityAt: now,
            title: 'All Members',
            emoji: '💬',
            creatorId: 'alice',
            participantIds: const ['alice'],
            includesAllMembers: true,
            archivedByMemberIds: const ['alice'],
          ),
        );
      final container = ProviderContainer(
        overrides: [conversationRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final seeded = await container
          .read(chatNotifierProvider.notifier)
          .seedDefaultConversationIfNeeded(
            title: 'All Members',
            emoji: '💬',
            members: [
              Member(id: 'alice', name: 'Alice', createdAt: now),
              Member(id: 'bob', name: 'Bob', createdAt: now),
            ],
          );

      expect(seeded, isNull);
      expect(fakeRepo.conversations, hasLength(1));
    },
  );

  test(
    'seedDefaultConversationIfNeeded creates an includes-all-members group',
    () async {
      final now = DateTime(2026, 5, 21, 12);
      final fakeRepo = FakeConversationRepository();
      final container = ProviderContainer(
        overrides: [conversationRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final seeded = await container
          .read(chatNotifierProvider.notifier)
          .seedDefaultConversationIfNeeded(
            title: 'All Members',
            emoji: '💬',
            members: [
              Member(id: 'alice', name: 'Alice', createdAt: now),
              Member(id: 'bob', name: 'Bob', createdAt: now),
            ],
          );

      expect(seeded, isNotNull);
      expect(fakeRepo.conversations, hasLength(1));
      expect(seeded!.title, 'All Members');
      expect(seeded.emoji, '💬');
      expect(seeded.creatorId, 'alice');
      expect(seeded.participantIds, ['alice']);
      expect(seeded.includesAllMembers, isTrue);
    },
  );

  test('seedDefaultConversationIfNeeded exposes repository errors', () async {
    final now = DateTime(2026, 5, 21, 12);
    final fakeRepo = _ThrowingConversationRepository();
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(fakeRepo)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(chatNotifierProvider.notifier)
          .seedDefaultConversationIfNeeded(
            title: 'All Members',
            emoji: '💬',
            members: [
              Member(id: 'alice', name: 'Alice', createdAt: now),
              Member(id: 'bob', name: 'Bob', createdAt: now),
            ],
          ),
      throwsA(isA<StateError>()),
    );

    final state = container.read(chatNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StateError>());
    expect(fakeRepo.conversations, isEmpty);
  });
}
