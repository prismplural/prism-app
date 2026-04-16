import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/utils/member_frequency_sort.dart';

Member _member(String id, {int displayOrder = 0}) => Member(
      id: id,
      name: id,
      createdAt: DateTime(2026),
      displayOrder: displayOrder,
    );

void main() {
  group('sortMembersByFrequency', () {
    test('sorts by count descending', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final counts = {'a': 1, 'b': 5, 'c': 3};

      final result = sortMembersByFrequency(members, counts);

      expect(result.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('tiebreaks by displayOrder when counts are equal', () {
      final members = [
        _member('a', displayOrder: 3),
        _member('b', displayOrder: 1),
        _member('c', displayOrder: 2),
      ];
      final counts = {'a': 5, 'b': 5, 'c': 5};

      final result = sortMembersByFrequency(members, counts);

      expect(result.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('tiebreaks by id when counts and displayOrder are equal', () {
      final members = [_member('charlie'), _member('alice'), _member('bob')];
      final counts = {'charlie': 2, 'alice': 2, 'bob': 2};

      final result = sortMembersByFrequency(members, counts);

      expect(result.map((m) => m.id).toList(), ['alice', 'bob', 'charlie']);
    });

    test('pinnedMemberId always appears first regardless of count', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final counts = {'a': 10, 'b': 1, 'c': 5};

      final result = sortMembersByFrequency(
        members,
        counts,
        pinnedMemberId: 'b',
      );

      expect(result.first.id, 'b');
      expect(result.map((m) => m.id).toList(), ['b', 'a', 'c']);
    });

    test('take truncates the result list', () {
      final members = [
        _member('a'),
        _member('b'),
        _member('c'),
        _member('d'),
        _member('e'),
      ];
      final counts = {'a': 5, 'b': 4, 'c': 3, 'd': 2, 'e': 1};

      final result = sortMembersByFrequency(members, counts, take: 3);

      expect(result.length, 3);
      expect(result.map((m) => m.id).toList(), ['a', 'b', 'c']);
    });

    test('defaults to take=4', () {
      final members = List.generate(6, (i) => _member('m$i'));
      final counts = {for (final m in members) m.id: 6 - int.parse(m.id.substring(1))};

      final result = sortMembersByFrequency(members, counts);

      expect(result.length, 4);
    });

    test('returns empty list for empty input', () {
      final result = sortMembersByFrequency([], {});

      expect(result, isEmpty);
    });

    test('members missing from counts map sort to end (treated as 0)', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final counts = {'b': 3}; // a and c not in map

      final result = sortMembersByFrequency(members, counts);

      expect(result.first.id, 'b');
      // a and c both have 0, tiebreak by id
      expect(result[1].id, 'a');
      expect(result[2].id, 'c');
    });
  });
}
