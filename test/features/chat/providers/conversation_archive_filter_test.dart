import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

void main() {
  final now = DateTime(2026, 5, 20);

  Conversation conv(
    String id, {
    List<String> archivedBy = const [],
    bool archivedForEveryone = false,
  }) => Conversation(
    id: id,
    createdAt: now,
    lastActivityAt: now,
    title: id,
    participantIds: const ['alice'],
    includesAllMembers: true,
    archivedByMemberIds: archivedBy,
    archivedForEveryone: archivedForEveryone,
  );

  // Fronts as 'alice', so speakingAsProvider resolves to her.
  ProviderContainer buildContainer(List<Conversation> conversations) {
    return ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith((ref) => Stream.value(conversations)),
        activeMembersProvider.overrideWithValue(
          AsyncValue.data([Member(id: 'alice', name: 'Alice', createdAt: now)]),
        ),
        activeSessionsProvider.overrideWithValue(
          AsyncValue.data([
            FrontingSession(id: 'f-alice', startTime: now, memberId: 'alice'),
          ]),
        ),
      ],
    );
  }

  // Listening transitively subscribes conversationsProvider's stream; a
  // microtask pump lets Stream.value emit before we read.
  Future<List<Conversation>> readVisible(ProviderContainer container) async {
    final sub = container.listen(filteredConversationsProvider, (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    return container.read(filteredConversationsProvider).value ?? const [];
  }

  test(
    'filteredConversationsProvider hides per-member AND for-everyone archives',
    () async {
      final container = buildContainer([
        conv('normal'),
        conv('mine', archivedBy: const ['alice']),
        conv('everyone', archivedForEveryone: true),
      ]);
      addTearDown(container.dispose);

      final visible = await readVisible(container);
      expect(
        visible.map((c) => c.id),
        ['normal'],
        reason:
            'the per-member archive (mine) and the for-everyone archive '
            '(everyone) should both drop out of the default list',
      );

      // The "Archived" affordance must still appear — both archived kinds count.
      expect(container.read(hasArchivedConversationsProvider), isTrue);
    },
  );

  test(
    'a for-everyone archive is hidden even for a member who never archived it',
    () async {
      // alice is NOT in archivedByMemberIds, but the convo is archived for
      // everyone, so it must still be hidden for her.
      final container = buildContainer([
        conv('everyone', archivedForEveryone: true),
      ]);
      addTearDown(container.dispose);

      expect(await readVisible(container), isEmpty);
    },
  );
}
