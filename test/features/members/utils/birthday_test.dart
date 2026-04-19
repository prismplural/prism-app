import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';

void main() {
  group('parseBirthday', () {
    test('returns null for null/empty', () {
      expect(parseBirthday(null), isNull);
      expect(parseBirthday(''), isNull);
      expect(parseBirthday('   '), isNull);
    });

    test('parses a full YYYY-MM-DD date', () {
      final dt = parseBirthday('1993-07-15');
      expect(dt, isNotNull);
      expect(dt!.year, 1993);
      expect(dt.month, 7);
      expect(dt.day, 15);
    });

    test('preserves the 0004 no-year sentinel', () {
      final dt = parseBirthday('0004-02-29');
      expect(dt, isNotNull);
      expect(dt!.year, birthdayNoYearSentinel);
      expect(isBirthdayYearHidden(dt), isTrue);
    });

    test('rejects malformed strings', () {
      expect(parseBirthday('not-a-date'), isNull);
      expect(parseBirthday('1993-07-15T00:00:00Z'), isNull);
      expect(parseBirthday('1993/07/15'), isNull);
    });
  });

  group('formatBirthdayWire', () {
    test('round-trips a full date byte-identically', () {
      const original = '1993-07-15';
      final parsed = parseBirthday(original)!;
      expect(formatBirthdayWire(parsed), equals(original));
    });

    test('round-trips the 0004 sentinel', () {
      const original = '0004-02-29';
      final parsed = parseBirthday(original)!;
      expect(
        formatBirthdayWire(parsed, hideYear: true),
        equals(original),
      );
    });

    test('hideYear substitutes 0004 for the year', () {
      final dt = DateTime(1993, 7, 15);
      expect(formatBirthdayWire(dt, hideYear: true), equals('0004-07-15'));
      expect(formatBirthdayWire(dt, hideYear: false), equals('1993-07-15'));
    });

    test('single-digit months and days are zero-padded', () {
      final dt = DateTime(2001, 1, 5);
      expect(formatBirthdayWire(dt), equals('2001-01-05'));
    });
  });

  group('formatBirthdayDisplay', () {
    test('shows full date when year is visible', () {
      final dt = DateTime(1993, 7, 15);
      final out = formatBirthdayDisplay(dt, 'en_US');
      // Don't assert exact locale output — just that year appears.
      expect(out, contains('1993'));
    });

    test('collapses to month+day when year is hidden', () {
      final dt = DateTime(birthdayNoYearSentinel, 7, 15);
      final out = formatBirthdayDisplay(dt, 'en_US');
      expect(out, isNot(contains('0004')));
      expect(out, isNot(contains('1993')));
    });
  });
}
