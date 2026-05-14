import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';

void main() {
  group('GroupSortMode.fromInt', () {
    test('0 → manual', () {
      expect(GroupSortMode.fromInt(0), GroupSortMode.manual);
    });

    test('1 → nameAsc', () {
      expect(GroupSortMode.fromInt(1), GroupSortMode.nameAsc);
    });

    test('2 → nameDesc', () {
      expect(GroupSortMode.fromInt(2), GroupSortMode.nameDesc);
    });

    test('3 → recentDesc', () {
      expect(GroupSortMode.fromInt(3), GroupSortMode.recentDesc);
    });

    test('99 (unknown int) → manual', () {
      expect(GroupSortMode.fromInt(99), GroupSortMode.manual);
    });

    test('null → manual', () {
      expect(GroupSortMode.fromInt(null), GroupSortMode.manual);
    });

    test('-1 → manual', () {
      expect(GroupSortMode.fromInt(-1), GroupSortMode.manual);
    });
  });

  group('GroupSortMode round-trip', () {
    test('every variant survives asInt → fromInt', () {
      for (final mode in GroupSortMode.values) {
        expect(
          GroupSortMode.fromInt(mode.asInt),
          mode,
          reason: 'round-trip for $mode',
        );
      }
    });

    test('asInt matches the enum index', () {
      expect(GroupSortMode.manual.asInt, 0);
      expect(GroupSortMode.nameAsc.asInt, 1);
      expect(GroupSortMode.nameDesc.asInt, 2);
      expect(GroupSortMode.recentDesc.asInt, 3);
    });
  });
}
