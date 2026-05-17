import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  test(
    'clears explicit speaking-as selection when member is no longer active',
    () {
      final activeMember = Member(
        id: 'active-member',
        name: 'Active',
        createdAt: DateTime(2026, 5, 7),
        isActive: true,
      );
      final container = ProviderContainer(
        overrides: [
          activeSessionsProvider.overrideWithValue(
            const AsyncValue.data(<FrontingSession>[]),
          ),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(<Member>[activeMember]),
          ),
          chatLogsFrontProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(speakingAsProvider.notifier).setMember('deleted-member');

      expect(container.read(speakingAsProvider), isNull);
    },
  );

  test(
    'reactively clears explicit selection when active members change',
    () async {
      final activeMember = Member(
        id: 'active-member',
        name: 'Active',
        createdAt: DateTime(2026, 5, 7),
        isActive: true,
      );
      final removedMember = Member(
        id: 'removed-member',
        name: 'Removed',
        createdAt: DateTime(2026, 5, 7),
        isActive: true,
      );
      final activeMembers = StreamController<List<Member>>();
      addTearDown(activeMembers.close);

      final container = ProviderContainer(
        overrides: [
          activeSessionsProvider.overrideWithValue(
            const AsyncValue.data(<FrontingSession>[]),
          ),
          activeMembersProvider.overrideWith((ref) => activeMembers.stream),
          chatLogsFrontProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final cleared = Completer<void>();
      final subscription = container.listen<String?>(speakingAsProvider, (
        previous,
        next,
      ) {
        if (previous == removedMember.id &&
            next == null &&
            !cleared.isCompleted) {
          cleared.complete();
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);

      activeMembers.add([activeMember, removedMember]);
      await container.read(activeMembersProvider.future);

      container.read(speakingAsProvider.notifier).setMember(removedMember.id);
      expect(container.read(speakingAsProvider), removedMember.id);

      activeMembers.add([activeMember]);
      await cleared.future.timeout(const Duration(seconds: 1));

      expect(container.read(speakingAsProvider), isNull);
    },
  );

  group('most-recent fronter default', () {
    Member member(String id) =>
        Member(id: id, name: id, createdAt: DateTime(2026, 5, 7));
    FrontingSession session({
      required String memberId,
      required DateTime startTime,
    }) => FrontingSession(
      id: 'session-$memberId',
      memberId: memberId,
      startTime: startTime,
    );

    ProviderContainer makeContainer({
      required List<FrontingSession> sessions,
      required List<Member> members,
    }) => ProviderContainer(
      overrides: [
        activeSessionsProvider.overrideWithValue(AsyncValue.data(sessions)),
        activeMembersProvider.overrideWithValue(AsyncValue.data(members)),
        chatLogsFrontProvider.overrideWithValue(false),
      ],
    );

    test('one fronter -> that fronter is the default', () {
      final container = makeContainer(
        sessions: [
          session(memberId: 'alice', startTime: DateTime(2026, 5, 7, 10)),
        ],
        members: [member('alice')],
      );
      addTearDown(container.dispose);

      expect(container.read(speakingAsProvider), 'alice');
    });

    test('multiple fronters -> latest startTime wins', () {
      // bob started after alice — bob should be the default.
      final container = makeContainer(
        sessions: [
          session(memberId: 'alice', startTime: DateTime(2026, 5, 7, 10)),
          session(memberId: 'bob', startTime: DateTime(2026, 5, 7, 11, 30)),
          session(memberId: 'carol', startTime: DateTime(2026, 5, 7, 9)),
        ],
        members: [member('alice'), member('bob'), member('carol')],
      );
      addTearDown(container.dispose);

      expect(container.read(speakingAsProvider), 'bob');
    });

    test('simultaneous startTimes -> deterministic lex order on member id', () {
      final t = DateTime(2026, 5, 7, 10);
      final container = makeContainer(
        sessions: [
          session(memberId: 'bob', startTime: t),
          session(memberId: 'alice', startTime: t),
        ],
        members: [member('alice'), member('bob')],
      );
      addTearDown(container.dispose);

      // 'alice' < 'bob' lexicographically — alice wins the tiebreak.
      expect(container.read(speakingAsProvider), 'alice');
    });

    test('zero fronters -> null (chat screen renders pick-speaker banner)',
        () {
      final container = makeContainer(
        sessions: const [],
        members: [member('alice')],
      );
      addTearDown(container.dispose);

      expect(container.read(speakingAsProvider), isNull);
    });

    test(
      'most-recent fronter is not active -> falls through, no default',
      () {
        final container = makeContainer(
          sessions: [
            session(memberId: 'paused', startTime: DateTime(2026, 5, 7, 11)),
          ],
          members: [member('alice')], // paused is not in active members
        );
        addTearDown(container.dispose);

        expect(container.read(speakingAsProvider), isNull);
      },
    );

    test('explicit selection overrides the most-recent default', () {
      final container = makeContainer(
        sessions: [
          session(memberId: 'alice', startTime: DateTime(2026, 5, 7, 10)),
          session(memberId: 'bob', startTime: DateTime(2026, 5, 7, 11)),
        ],
        members: [member('alice'), member('bob')],
      );
      addTearDown(container.dispose);

      // Default would be 'bob'; user picks 'alice'.
      container.read(speakingAsProvider.notifier).setMember('alice');
      expect(container.read(speakingAsProvider), 'alice');
    });
  });

  test('keeps Unknown selection even before the sentinel member exists', () {
    final activeMember = Member(
      id: 'active-member',
      name: 'Active',
      createdAt: DateTime(2026, 5, 7),
      isActive: true,
    );
    final container = ProviderContainer(
      overrides: [
        activeSessionsProvider.overrideWithValue(
          const AsyncValue.data(<FrontingSession>[]),
        ),
        activeMembersProvider.overrideWithValue(
          AsyncValue.data(<Member>[activeMember]),
        ),
        chatLogsFrontProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(speakingAsProvider.notifier)
        .setMember(unknownSentinelMemberId);

    expect(container.read(speakingAsProvider), unknownSentinelMemberId);
  });
}
