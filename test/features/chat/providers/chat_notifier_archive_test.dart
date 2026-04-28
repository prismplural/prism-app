import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  final now = DateTime(2026, 4, 25);

  ProviderContainer buildContainer({
    required FakeConversationRepository conversations,
    required FakeMemberRepository members,
  }) {
    return ProviderContainer(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        conversationRepositoryProvider.overrideWithValue(conversations),
      ],
    );
  }

  test('archive then unarchive round-trips archivedByMemberIds', () async {
    final convRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Group',
          participantIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([Member(id: 'alice', name: 'Alice', createdAt: now)]);

    final container = buildContainer(
      conversations: convRepo,
      members: memberRepo,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.archiveConversation('conv-1', 'alice');
    expect(
      convRepo.conversations.single.archivedByMemberIds,
      ['alice'],
      reason: 'archive should add the member id',
    );

    await notifier.unarchiveConversation('conv-1', 'alice');
    expect(
      convRepo.conversations.single.archivedByMemberIds,
      isEmpty,
      reason: 'unarchive should remove the member id',
    );
  });

  test('unarchive only removes the calling member, leaves others archived',
      () async {
    final convRepo = FakeConversationRepository()
      ..conversations.add(
        Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Group',
          participantIds: const ['alice', 'bob'],
          archivedByMemberIds: const ['alice', 'bob'],
        ),
      );
    final memberRepo = FakeMemberRepository()
      ..seed([Member(id: 'alice', name: 'Alice', createdAt: now)]);

    final container = buildContainer(
      conversations: convRepo,
      members: memberRepo,
    );
    addTearDown(container.dispose);

    await container
        .read(chatNotifierProvider.notifier)
        .unarchiveConversation('conv-1', 'alice');

    expect(convRepo.conversations.single.archivedByMemberIds, ['bob']);
  });
}
