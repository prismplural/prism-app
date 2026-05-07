import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'alice';
}

void main() {
  test('adding emoji to an emoji-less conversation saves it', () async {
    final now = DateTime(2026, 5, 6);
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
      ..seed([Member(id: 'alice', name: 'Alice', createdAt: now)]);

    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(conversationRepo),
        memberRepositoryProvider.overrideWithValue(memberRepo),
        speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .updateConversation('conv-1', emoji: '✨');

    expect(conversationRepo.conversations.single.emoji, '✨');
  });

  test('clearing emoji removes it', () async {
    final now = DateTime(2026, 5, 6);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          emoji: '✨',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([Member(id: 'alice', name: 'Alice', createdAt: now)]);

    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(conversationRepo),
        memberRepositoryProvider.overrideWithValue(memberRepo),
        speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .updateConversation('conv-1', clearEmoji: true);

    expect(conversationRepo.conversations.single.emoji, isNull);
  });

  test('changing category preserves existing emoji', () async {
    final now = DateTime(2026, 5, 6);
    final conversationRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'General',
          emoji: '✨',
          creatorId: 'alice',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([Member(id: 'alice', name: 'Alice', createdAt: now)]);

    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(conversationRepo),
        memberRepositoryProvider.overrideWithValue(memberRepo),
        speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .updateConversation('conv-1', categoryId: 'category-1');

    expect(conversationRepo.conversations.single.categoryId, 'category-1');
    expect(conversationRepo.conversations.single.emoji, '✨');
  });
}
