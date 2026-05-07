import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/members/providers/members_providers.dart';

domain.Member _member({required String id, bool isActive = true}) =>
    domain.Member(
      id: id,
      name: id,
      createdAt: DateTime(2024, 1, 1),
      isActive: isActive,
    );

class _RecordingMembersDao extends MembersDao {
  _RecordingMembersDao(super.db);

  var bulkUpdateCalls = 0;
  var rowUpdateCalls = 0;

  @override
  Future<void> bulkUpdateDisplayOrders(Map<String, int> displayOrders) async {
    bulkUpdateCalls++;
    await super.bulkUpdateDisplayOrders(displayOrders);
  }

  @override
  Future<void> updateMember(MembersCompanion member) async {
    rowUpdateCalls++;
    await super.updateMember(member);
  }
}

void main() {
  group('userVisibleMembersProvider', () {
    test('hides the Unknown sentinel from the active list', () {
      final c = ProviderContainer(
        overrides: [
          activeMembersProvider.overrideWithValue(
            AsyncValue.data([
              _member(id: 'alice'),
              _member(id: unknownSentinelMemberId),
              _member(id: 'bob'),
            ]),
          ),
        ],
      );
      addTearDown(c.dispose);

      final result = c.read(userVisibleMembersProvider);
      final members = result.value!;
      expect(members.map((m) => m.id), containsAll(['alice', 'bob']));
      expect(
        members.any((m) => m.id == unknownSentinelMemberId),
        isFalse,
        reason: 'sentinel must not appear in the user-visible list',
      );
    });

    test('unfiltered activeMembersProvider still includes the sentinel '
        '(fronting/analytics paths can resolve it)', () {
      final c = ProviderContainer(
        overrides: [
          activeMembersProvider.overrideWithValue(
            AsyncValue.data([
              _member(id: unknownSentinelMemberId),
              _member(id: 'alice'),
            ]),
          ),
        ],
      );
      addTearDown(c.dispose);

      final unfiltered = c.read(activeMembersProvider).value!;
      expect(
        unfiltered.any((m) => m.id == unknownSentinelMemberId),
        isTrue,
        reason:
            'fronting selection / analytics rely on resolving the sentinel id',
      );
    });

    test('preserves loading + error states', () {
      final loadingContainer = ProviderContainer(
        overrides: [
          activeMembersProvider.overrideWithValue(const AsyncValue.loading()),
        ],
      );
      addTearDown(loadingContainer.dispose);
      expect(
        loadingContainer.read(userVisibleMembersProvider).isLoading,
        isTrue,
      );

      final errorContainer = ProviderContainer(
        overrides: [
          activeMembersProvider.overrideWithValue(
            AsyncValue.error(StateError('boom'), StackTrace.empty),
          ),
        ],
      );
      addTearDown(errorContainer.dispose);
      expect(errorContainer.read(userVisibleMembersProvider).hasError, isTrue);
    });
  });

  group('userVisibleAllMembersProvider', () {
    test('hides the sentinel from the all-members list (incl. inactive)', () {
      final c = ProviderContainer(
        overrides: [
          allMembersProvider.overrideWithValue(
            AsyncValue.data([
              _member(id: 'alice', isActive: true),
              _member(id: 'inactive', isActive: false),
              _member(id: unknownSentinelMemberId),
            ]),
          ),
        ],
      );
      addTearDown(c.dispose);

      final members = c.read(userVisibleAllMembersProvider).value!;
      expect(members.map((m) => m.id), containsAll(['alice', 'inactive']));
      expect(members.any((m) => m.id == unknownSentinelMemberId), isFalse);
    });
  });

  test(
    'members notifier reorders via a bulk display-order update path',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final dao = _RecordingMembersDao(db);
      final repo = DriftMemberRepository(dao, null);

      await repo.createMember(_member(id: 'alice').copyWith(displayOrder: 0));
      await repo.createMember(_member(id: 'bob').copyWith(displayOrder: 1));
      await repo.createMember(_member(id: 'carol').copyWith(displayOrder: 2));

      final container = ProviderContainer(
        overrides: [memberRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final initial = await repo.getAllMembers();
      final reordered = [initial[2], initial[0], initial[1]];

      await container
          .read(membersNotifierProvider.notifier)
          .reorderMembers(reordered);

      expect(dao.bulkUpdateCalls, 1);
      expect(dao.rowUpdateCalls, 0);

      final updated = await repo.getAllMembers();
      expect(updated.map((m) => m.id), ['carol', 'alice', 'bob']);
      expect(updated.map((m) => m.displayOrder), [0, 1, 2]);
    },
  );
}
