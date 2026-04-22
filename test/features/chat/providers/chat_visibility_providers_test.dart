import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';

import '../../../helpers/fake_repositories.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
}

void main() {
  final now = DateTime(2026, 4, 21);
  final dmConversation = Conversation(
    id: 'dm-1',
    createdAt: now,
    lastActivityAt: now,
    isDirectMessage: true,
    participantIds: const ['alice', 'bob'],
  );
  final legacyDmConversation = Conversation(
    id: 'legacy-dm-1',
    createdAt: now,
    lastActivityAt: now,
    isDirectMessage: false,
    title: '',
    emoji: null,
    participantIds: const ['ethan', 'zari'],
  );
  final groupConversation = Conversation(
    id: 'group-1',
    createdAt: now,
    lastActivityAt: now,
    title: 'Everyone',
    participantIds: const ['alice', 'bob'],
  );

  ProviderContainer buildContainer(String? speakingAs) {
    final seededMembers = [
      Member(id: 'alice', name: 'Alice', createdAt: now),
      Member(id: 'bob', name: 'Bob', createdAt: now),
      Member(id: 'carol', name: 'Carol', createdAt: now),
      Member(id: 'admin', name: 'Admin', createdAt: now, isAdmin: true),
      Member(id: 'ethan', name: 'Ethan', createdAt: now),
      Member(id: 'zari', name: 'Zari', createdAt: now),
    ];
    final members = FakeMemberRepository()..seed(seededMembers);
    final conversations = FakeConversationRepository()
      ..conversations.addAll([
        dmConversation,
        legacyDmConversation,
        groupConversation,
      ]);
    final currentViewer = seededMembers
        .where((member) => member.id == speakingAs)
        .firstOrNull;

    return ProviderContainer(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        conversationRepositoryProvider.overrideWithValue(conversations),
        currentChatViewerProvider.overrideWithValue(currentViewer),
        speakingAsProvider.overrideWith(
          () => _FixedSpeakingAsNotifier(speakingAs),
        ),
      ],
    );
  }

  test('non-participant does not see DM in conversation list', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(conversationsProvider, (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversations = sub.read().value!;

    expect(conversations.map((c) => c.id), ['group-1']);
  });

  test('admin can see DM in conversation list', () async {
    final container = buildContainer('admin');
    addTearDown(container.dispose);
    final sub = container.listen(conversationsProvider, (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversations = sub.read().value!;

    expect(conversations.map((c) => c.id), ['dm-1', 'legacy-dm-1', 'group-1']);
  });

  test('non-participant cannot open DM by id', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(conversationByIdProvider('dm-1'), (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });

  test('admin can open DM by id in read-only mode', () async {
    final container = buildContainer('admin');
    addTearDown(container.dispose);
    final sub = container.listen(conversationByIdProvider('dm-1'), (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation?.id, 'dm-1');
  });

  test('non-participant cannot open legacy DM by id', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(
      conversationByIdProvider('legacy-dm-1'),
      (_, __) {},
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });
}
