import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

void main() {
  group('extractObjectIdTimestamp', () {
    test('decodes a known ObjectId prefix to the correct UTC datetime', () {
      // 0x69c0c13c = 1774240060 seconds since epoch
      // → 2026-03-23T04:27:40Z
      final result = extractObjectIdTimestamp('69c0c13c577c2c05c3000000');
      expect(result, isNotNull);
      expect(result, DateTime.utc(2026, 3, 23, 4, 27, 40));
    });

    test('returns null for empty string', () {
      expect(extractObjectIdTimestamp(''), isNull);
    });

    test('returns null for string shorter than 8 chars', () {
      expect(extractObjectIdTimestamp('abcdef0'), isNull);
    });

    test('returns null for 5-char PluralKit-style id', () {
      expect(extractObjectIdTimestamp('abcde'), isNull);
    });

    test('returns null when leading 8 chars contain non-hex characters', () {
      expect(extractObjectIdTimestamp('ZZZZZZZZ0000000000000000'), isNull);
    });

    test('returns null for zero ObjectId (year 1970, before 2000)', () {
      expect(extractObjectIdTimestamp('000000000000000000000000'), isNull);
    });

    test('returns a post-2000 DateTime for a valid 8+ char hex prefix', () {
      // 0x50000000 = 1342177280 seconds → 2012-07-13
      final result = extractObjectIdTimestamp('500000001234567890abcdef');
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.year, greaterThanOrEqualTo(2000));
    });
  });
}
