import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
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
        conversationsProvider.overrideWith((ref) => Stream.value(conversations)),
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
  });
}
