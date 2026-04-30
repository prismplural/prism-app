import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_switch_cursor.dart';

void main() {
  group('PkSwitchCursor.compareTo', () {
    test('earlier timestamp compares less', () {
      final a = PkSwitchCursor(
        timestamp: DateTime.utc(2026, 1, 1, 10),
        switchId: 'zzz',
      );
      final b = PkSwitchCursor(
        timestamp: DateTime.utc(2026, 1, 1, 12),
        switchId: 'aaa',
      );
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
    });

    test('same timestamp falls back to switch id (string)', () {
      final ts = DateTime.utc(2026, 1, 1, 10);
      final a = PkSwitchCursor(timestamp: ts, switchId: 'sw-1');
      final b = PkSwitchCursor(timestamp: ts, switchId: 'sw-2');
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
    });

    test('equal cursors compare equal', () {
      final ts = DateTime.utc(2026, 1, 1, 10);
      final a = PkSwitchCursor(timestamp: ts, switchId: 'sw-1');
      final b = PkSwitchCursor(timestamp: ts, switchId: 'sw-1');
      expect(a.compareTo(b), 0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('PkSwitchCursor.covers', () {
    test('covers (equal) — strict less-or-equal', () {
      final ts = DateTime.utc(2026, 1, 1, 10);
      final cursor = PkSwitchCursor(timestamp: ts, switchId: 'sw-1');
      // The cursor's own (ts, id) is covered.
      expect(cursor.covers(ts, 'sw-1'), isTrue);
    });

    test('does not cover same-timestamp switch with later id', () {
      // Regression for review #6: switches at the same timestamp as the
      // cursor with a different id MUST be processed.
      final ts = DateTime.utc(2026, 1, 1, 10);
      final cursor = PkSwitchCursor(timestamp: ts, switchId: 'sw-1');
      expect(
        cursor.covers(ts, 'sw-2'),
        isFalse,
        reason: 'sw-2 > sw-1 lexicographically; must be processed.',
      );
    });

    test('covers same-timestamp switch with earlier id', () {
      final ts = DateTime.utc(2026, 1, 1, 10);
      final cursor = PkSwitchCursor(timestamp: ts, switchId: 'sw-2');
      expect(
        cursor.covers(ts, 'sw-1'),
        isTrue,
        reason: 'sw-1 < sw-2 lexicographically; cursor already past it.',
      );
    });

    test('covers strictly earlier timestamps regardless of id', () {
      final cursor = PkSwitchCursor(
        timestamp: DateTime.utc(2026, 1, 1, 12),
        switchId: 'sw-zzz',
      );
      expect(cursor.covers(DateTime.utc(2026, 1, 1, 10), 'sw-aaa'), isTrue);
    });

    test('does not cover strictly later timestamps regardless of id', () {
      final cursor = PkSwitchCursor(
        timestamp: DateTime.utc(2026, 1, 1, 10),
        switchId: 'sw-zzz',
      );
      expect(cursor.covers(DateTime.utc(2026, 1, 1, 12), 'sw-aaa'), isFalse);
    });
  });

  group('PkPaginationNoProgressError', () {
    test('toString surfaces last before + page count', () {
      final err = PkPaginationNoProgressError(
        lastBefore: DateTime.utc(2026, 1, 1),
        pagesFetched: 7,
      );
      expect(err.toString(), contains('2026-01-01T00:00:00.000Z'));
      expect(err.toString(), contains('7'));
    });
  });

  group('PkImportTooLargeError', () {
    test('toString includes cap and page count', () {
      final err = PkImportTooLargeError(pagesFetched: 1000, cap: 1000);
      expect(err.toString(), contains('1000'));
    });
  });
}
