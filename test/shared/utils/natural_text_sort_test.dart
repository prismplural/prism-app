import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/utils/natural_text_sort.dart';

void main() {
  group('sortedByNaturalText', () {
    test('sorts embedded numbers by numeric value', () {
      final sorted = sortedByNaturalText<String>(
        ['Member 49', 'Member 100', 'Member 2', 'Member 10'],
        text: (value) => value,
        id: (value) => value,
      );

      expect(sorted, ['Member 2', 'Member 10', 'Member 49', 'Member 100']);
    });

    test('handles leading zero ties with deterministic id fallback', () {
      final sorted = sortedByNaturalText<String>(
        ['Member 001', 'Member 1', 'Member 0001'],
        text: (value) => value,
        id: (value) => value,
      );

      expect(sorted, ['Member 1', 'Member 001', 'Member 0001']);
    });

    test('uses explicit tie break before id fallback', () {
      final sorted = sortedByNaturalText<({String id, String name, int rank})>(
        [
          (id: 'b', name: 'Alex 2', rank: 2),
          (id: 'a', name: 'alex 2', rank: 1),
        ],
        text: (value) => value.name,
        id: (value) => value.id,
        tieBreak: (left, right) => left.rank.compareTo(right.rank),
      );

      expect(sorted.map((value) => value.id), ['a', 'b']);
    });

    test(
      'sorts descending by natural text but keeps ids ascending for ties',
      () {
        final sorted = sortedByNaturalText<({String id, String name})>(
          [
            (id: 'b', name: 'Member 1'),
            (id: 'a', name: 'member 1'),
            (id: 'c', name: 'Member 100'),
          ],
          text: (value) => value.name,
          id: (value) => value.id,
          direction: -1,
        );

        expect(sorted.map((value) => value.id), ['c', 'a', 'b']);
      },
    );
  });

  group('compareNaturalText', () {
    test('compares case-insensitively and naturally', () {
      expect(compareNaturalText('Member 49', 'member 100'), isNegative);
      expect(compareNaturalText('Member 10', 'member 2'), isPositive);
      expect(compareNaturalText('Alex', 'alex'), 0);
    });
  });
}
