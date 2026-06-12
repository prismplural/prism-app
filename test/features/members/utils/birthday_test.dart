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

    test('accepts pre-1900 years', () {
      final dt = parseBirthday('1850-03-12');
      expect(dt, isNotNull);
      expect(dt!.year, 1850);
      expect(isBirthdayYearHidden(dt), isFalse);
    });

    test(
      'treats LEGACY year 0001 as the hidden-year sentinel '
      '(2026-06 PK audit low — wave 4)',
      () {
        // PK's server source (DateUtils.cs) treats 0001 like 0004; older
        // data may still carry it on the wire.
        final dt = parseBirthday('0001-01-01');
        expect(dt, isNotNull);
        expect(dt!.year, birthdayNoYearLegacySentinel);
        expect(isBirthdayYearHidden(dt), isTrue);
      },
    );

    test('accepts far-future years', () {
      final dt = parseBirthday('9999-12-31');
      expect(dt, isNotNull);
      expect(dt!.year, 9999);
      expect(isBirthdayYearHidden(dt), isFalse);
    });

    test(
      'rejects calendar-invalid dates instead of silently normalizing '
      '(2026-06 PK audit low — wave 4)',
      () {
        // DateTime(2020, 2, 30) would silently become Mar 2 — parseBirthday
        // must reject the overflow rather than invent a different date.
        expect(parseBirthday('2020-02-30'), isNull);
        expect(parseBirthday('2021-02-29'), isNull, reason: 'not a leap year');
        expect(parseBirthday('2020-13-01'), isNull);
        expect(parseBirthday('2020-00-15'), isNull);
        expect(parseBirthday('2020-01-00'), isNull);
        expect(parseBirthday('2020-01-32'), isNull);
        // Leap-day on a real leap year still parses.
        expect(parseBirthday('2020-02-29'), isNotNull);
      },
    );
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

    test('pads single- and double-digit years to four digits', () {
      expect(formatBirthdayWire(DateTime(1, 1, 1)), equals('0001-01-01'));
      expect(formatBirthdayWire(DateTime(42, 6, 15)), equals('0042-06-15'));
      expect(formatBirthdayWire(DateTime(850, 3, 12)), equals('0850-03-12'));
    });

    test('round-trips pre-1900 and far-future years', () {
      for (final wire in ['0001-01-01', '0850-03-12', '1750-11-30', '9999-12-31']) {
        final parsed = parseBirthday(wire);
        expect(parsed, isNotNull, reason: 'should parse $wire');
        expect(formatBirthdayWire(parsed!), equals(wire));
      }
    });

    test(
      'legacy 0001 is read as hidden but NEVER written as the sentinel '
      '(2026-06 PK audit low — wave 4)',
      () {
        final parsed = parseBirthday('0001-07-15')!;
        expect(isBirthdayYearHidden(parsed), isTrue);
        // An explicit hide-year WRITE always normalizes to the 0004 write
        // sentinel (0004 is a leap year; 0001 is not).
        expect(formatBirthdayWire(parsed, hideYear: true), '0004-07-15');
        // Without the hide flag the raw components round-trip verbatim, so
        // a stored legacy string is only rewritten when a user edit goes
        // through the hide-year path — never by a passive re-format.
        expect(formatBirthdayWire(parsed), '0001-07-15');
      },
    );
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

    test(
      'legacy 0001 hidden year also displays month+day, not "year 1" '
      '(2026-06 PK audit low — wave 4)',
      () {
        final dt = parseBirthday('0001-07-15')!;
        final out = formatBirthdayDisplay(dt, 'en_US');
        expect(out, 'Jul 15');
      },
    );
  });
}
