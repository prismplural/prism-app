import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

void main() {
  // Local helper to build a MemberGroupRow with a custom sort_state string.
  db.MemberGroupRow rowWithSortState(String sortStateJson) =>
      db.MemberGroupRow(
        id: 'g',
        name: 'g',
        displayOrder: 0,
        groupType: 0,
        createdAt: DateTime(2026, 1, 1),
        isDeleted: false,
        syncSuppressed: false,
        sortState: sortStateJson,
      );

  group('GroupSortState shape', () {
    test('manualEmpty is mode=manual + empty order', () {
      expect(GroupSortState.manualEmpty.mode, GroupSortMode.manual);
      expect(GroupSortState.manualEmpty.manualOrder, isEmpty);
      expect(GroupSortState.manualEmpty.isManual, isTrue);
    });

    test('locked(nameAsc) produces a sort-only state', () {
      final state = GroupSortState.locked(GroupSortMode.nameAsc);
      expect(state.mode, GroupSortMode.nameAsc);
      expect(state.manualOrder, isEmpty);
      expect(state.isManual, isFalse);
    });

    test('equality + hashCode match for same shape', () {
      const a = GroupSortState(
        mode: GroupSortMode.nameAsc,
        manualOrder: ['x', 'y'],
      );
      const b = GroupSortState(
        mode: GroupSortMode.nameAsc,
        manualOrder: ['x', 'y'],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality is false when order differs', () {
      const a = GroupSortState(
        mode: GroupSortMode.manual,
        manualOrder: ['x', 'y'],
      );
      const b = GroupSortState(
        mode: GroupSortMode.manual,
        manualOrder: ['y', 'x'],
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('GroupSortState round-trip via MemberGroupMapper', () {
    test('manualEmpty round-trips through encode → decode', () {
      // Encode via toCompanion, then decode via toDomain.
      final group = domain.MemberGroup(
        id: 'g',
        name: 'g',
        createdAt: DateTime(2026, 1, 1),
      );
      final companion = MemberGroupMapper.toCompanion(group);
      final row = rowWithSortState(companion.sortState.value);
      final restored = MemberGroupMapper.toDomain(row);
      expect(restored.sortState, GroupSortState.manualEmpty);
    });

    test('non-empty manualOrder + nameAsc round-trips', () {
      final group = domain.MemberGroup(
        id: 'g',
        name: 'g',
        createdAt: DateTime(2026, 1, 1),
        sortState: const GroupSortState(
          mode: GroupSortMode.nameAsc,
          manualOrder: ['a', 'b', 'c'],
        ),
      );
      final companion = MemberGroupMapper.toCompanion(group);
      final row = rowWithSortState(companion.sortState.value);
      final restored = MemberGroupMapper.toDomain(row);
      expect(restored.sortState.mode, GroupSortMode.nameAsc);
      expect(restored.sortState.manualOrder, ['a', 'b', 'c']);
    });
  });
}
