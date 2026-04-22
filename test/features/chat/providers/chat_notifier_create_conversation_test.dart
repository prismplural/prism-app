import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

import '../../../helpers/fake_repositories.dart';

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
}
