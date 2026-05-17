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

  test(
    'non-participant sees neither DMs nor group chats they are not in',
    () async {
      final container = buildContainer('carol');
      addTearDown(container.dispose);
      final sub = container.listen(conversationsProvider, (_, _) {});
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);
      final conversations = sub.read().value!;

      // Carol is in no participantIds, so she sees nothing — neither the DM
      // nor the group nor the legacy DM (which is `isDirectMessage:false`
      // but matches the legacy two-person-untitled shape).
      expect(conversations, isEmpty);
    },
  );

  test(
    'admin non-participant sees neither DMs nor group chats they are not in',
    () async {
      final container = buildContainer('admin');
      addTearDown(container.dispose);
      final sub = container.listen(conversationsProvider, (_, _) {});
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);
      final conversations = sub.read().value!;

      // Admins have no automatic override — the "speaking-as" picker is what
      // grants access, not the admin flag.
      expect(conversations, isEmpty);
    },
  );

  test('participant sees the group they are in', () async {
    final container = buildContainer('alice');
    addTearDown(container.dispose);
    final sub = container.listen(conversationsProvider, (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversations = sub.read().value!;

    // Alice is in dm-1 and group-1 but not in legacy-dm-1.
    expect(conversations.map((c) => c.id).toSet(), {'dm-1', 'group-1'});
  });

  test('null speakingAs sees groups (browse mode) but not scoped DMs',
      () async {
    final container = buildContainer(null);
    addTearDown(container.dispose);
    final sub = container.listen(conversationsProvider, (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversations = sub.read().value!;

    // When no member is picked, the chat list shows group metadata so the
    // list isn't empty. Scoped DMs stay hidden regardless.
    expect(conversations.map((c) => c.id), ['group-1']);
  });

  test('non-participant cannot open DM by id', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(conversationByIdProvider('dm-1'), (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });

  test('admin non-participant cannot open DM by id', () async {
    final container = buildContainer('admin');
    addTearDown(container.dispose);
    final sub = container.listen(conversationByIdProvider('dm-1'), (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });

  test('non-participant cannot open group chat by id', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(
      conversationByIdProvider('group-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });

  test('admin non-participant cannot open group chat by id', () async {
    final container = buildContainer('admin');
    addTearDown(container.dispose);
    final sub = container.listen(
      conversationByIdProvider('group-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });

  test('non-participant cannot open legacy DM by id', () async {
    final container = buildContainer('carol');
    addTearDown(container.dispose);
    final sub = container.listen(
      conversationByIdProvider('legacy-dm-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    final conversation = sub.read().value;

    expect(conversation, isNull);
  });
}
