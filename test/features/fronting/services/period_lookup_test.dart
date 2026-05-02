import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/services/period_lookup.dart';

FrontingPeriod _period(List<String> sessionIds) => FrontingPeriod(
  start: DateTime(2026, 1, 1),
  end: DateTime(2026, 1, 1, 1),
  activeMembers: const [],
  briefVisitors: const [],
  sessionIds: sessionIds,
  alwaysPresentMembers: const [],
  isOpenEnded: false,
);

void main() {
  group('findPeriodBySessionIds', () {
    test('exact set match returns the period', () {
      final p = _period(['a', 'b', 'c']);
      final result = findPeriodBySessionIds([p], ['a', 'b', 'c']);
      expect(result, same(p));
    });

    test('superset does not match', () {
      final p = _period(['a', 'b', 'c']);
      final result = findPeriodBySessionIds([p], ['a', 'b']);
      expect(result, isNull);
    });

    test('subset does not match', () {
      final p = _period(['a']);
      final result = findPeriodBySessionIds([p], ['a', 'b']);
      expect(result, isNull);
    });

    test('disjoint does not match', () {
      final p = _period(['a', 'b']);
      final result = findPeriodBySessionIds([p], ['c', 'd']);
      expect(result, isNull);
    });

    test('returns null when periods is empty', () {
      final result = findPeriodBySessionIds([], ['a', 'b']);
      expect(result, isNull);
    });

    test('order-independent', () {
      final p = _period(['a', 'b', 'c']);
      final result = findPeriodBySessionIds([p], ['c', 'a', 'b']);
      expect(result, same(p));
    });

    test('picks the first matching period when multiple periods could match',
        () {
      final first = _period(['a', 'b']);
      final second = _period(['a', 'b']);
      final result = findPeriodBySessionIds([first, second], ['a', 'b']);
      expect(result, same(first));
    });
  });
}
