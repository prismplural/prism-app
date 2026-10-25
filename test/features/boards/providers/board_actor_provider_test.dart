import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_actor_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

void main() {
  final now = DateTime(2026, 5, 1);
  final alice = Member(id: 'alice', name: 'Alice', createdAt: now);
  final archived = Member(
    id: 'archived',
    name: 'Archived',
    createdAt: now,
    isActive: false,
  );
  final deleted = Member(
    id: 'deleted',
    name: 'Deleted',
    createdAt: now,
    isDeleted: true,
  );
  final unknown = Member(
    id: unknownSentinelMemberId,
    name: 'Unknown',
    createdAt: now,
  );

  test('only explicit valid roster members can act on boards', () async {
    final members = [alice, archived, deleted, unknown];
    final container = ProviderContainer(
      overrides: [
        activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
        memberByIdProvider.overrideWith(
          (ref, id) => Stream.value(
            members.where((member) => member.id == id).firstOrNull,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final rosterSubscription = container.listen(
      activeMemberListProvider,
      (_, _) {},
    );
    final actorSubscription = container.listen(
      boardActorMemberProvider,
      (_, _) {},
    );
    addTearDown(rosterSubscription.close);
    addTearDown(actorSubscription.close);
    await container
        .read(activeMemberListProvider.future)
        .timeout(const Duration(seconds: 5));
    expect(container.read(boardActorProvider), isNull);
    for (final id in ['missing', archived.id, deleted.id, unknown.id]) {
      container.read(boardActorProvider.notifier).setMember(id);
      expect(container.read(boardActorProvider), isNull);
      expect(container.read(boardActorMemberProvider), isNull);
    }
    final memberSubscription = container.listen(
      activeMemberByIdProvider(alice.id),
      (_, _) {},
    );
    addTearDown(memberSubscription.close);
    container.read(boardActorProvider.notifier).setMember(alice.id);
    await container
        .read(memberByIdProvider(alice.id).future)
        .timeout(const Duration(seconds: 5));
    expect(container.read(boardActorMemberProvider)?.id, alice.id);
    container.read(boardActorProvider.notifier).setMember(null);
    expect(container.read(boardActorMemberProvider), isNull);
  });

  test('removing an actor from the active roster revokes selection', () async {
    final roster = StreamController<List<Member>>();
    final container = ProviderContainer(
      overrides: [
        activeMemberListProvider.overrideWith((ref) => roster.stream),
        memberByIdProvider.overrideWith((ref, id) => Stream.value(alice)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await roster.close();
    });
    final actorSubscription = container.listen(boardActorProvider, (_, _) {});
    addTearDown(actorSubscription.close);
    final loaded = container.read(activeMemberListProvider.future);
    roster.add([alice]);
    await loaded.timeout(const Duration(seconds: 5));
    container.read(boardActorProvider.notifier).setMember(alice.id);
    expect(container.read(boardActorProvider), alice.id);
    roster.add([]);
    await container.pump();
    expect(container.read(boardActorProvider), isNull);
    roster.add([alice]);
    await container.pump();
    expect(
      container.read(boardActorProvider),
      isNull,
      reason: 'restoring a profile must not silently restore its identity',
    );
  });
}
