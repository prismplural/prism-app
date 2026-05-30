import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/safe_link.dart';

void main() {
  group('safeExternalUri', () {
    group('allowed schemes', () {
      test('accepts https URL', () {
        expect(safeExternalUri('https://x.com'), isNotNull);
      });

      test('accepts http URL', () {
        expect(safeExternalUri('http://x.com'), isNotNull);
      });

      test('accepts mailto URI', () {
        expect(safeExternalUri('mailto:a@b.com'), isNotNull);
      });

      test('accepts tel URI', () {
        expect(safeExternalUri('tel:+15551234'), isNotNull);
      });
    });

    group('blocked schemes', () {
      test('rejects javascript:', () {
        expect(safeExternalUri('javascript:alert(1)'), isNull);
      });

      test('rejects data:', () {
        expect(safeExternalUri('data:text/html,x'), isNull);
      });

      test('rejects file:', () {
        expect(safeExternalUri('file:///etc/passwd'), isNull);
      });

      test('rejects intent:', () {
        expect(safeExternalUri('intent://x'), isNull);
      });

      test('rejects ftp:', () {
        expect(safeExternalUri('ftp://x'), isNull);
      });

      test('rejects ssh:', () {
        expect(safeExternalUri('ssh://x'), isNull);
      });
    });

    group('null / empty / whitespace', () {
      test('returns null for null input', () {
        expect(safeExternalUri(null), isNull);
      });

      test('returns null for empty string', () {
        expect(safeExternalUri(''), isNull);
      });

      test('returns null for whitespace-only string', () {
        expect(safeExternalUri('   '), isNull);
      });
    });

    group('control characters', () {
      test('returns null for string with newline control char', () {
        final url = 'https://x${String.fromCharCode(0x0A)}y';
        expect(safeExternalUri(url), isNull);
      });
    });

    group('length limit', () {
      test('returns null when URL exceeds 2048 chars', () {
        final url = 'https://x.com/${'a' * 3000}';
        expect(safeExternalUri(url), isNull);
      });

      test('accepts URL at exactly 2048 chars', () {
        // Build a valid https URL that is exactly 2048 chars.
        const prefix = 'https://x.com/';
        final url = prefix + 'a' * (2048 - prefix.length);
        expect(url.length, 2048);
        expect(safeExternalUri(url), isNotNull);
      });
    });

    group('whitespace trimming', () {
      test('trims surrounding whitespace before validating', () {
        final result = safeExternalUri('  https://x.com  ');
        expect(result, isNotNull);
        expect(result!.scheme, 'https');
      });
    });

    group('opaque URI schemes', () {
      test('mailto URI has scheme mailto', () {
        final result = safeExternalUri('mailto:a@b.com');
        expect(result, isNotNull);
        expect(result!.scheme, 'mailto');
      });

      test('tel URI has scheme tel', () {
        final result = safeExternalUri('tel:+15551234');
        expect(result, isNotNull);
        expect(result!.scheme, 'tel');
      });
    });
  });
}
