import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
