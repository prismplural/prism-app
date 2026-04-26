/// Smoke tests that pin the RFC 4122 validity of every fronting namespace UUID.
///
/// The `uuid` package's `UuidParsing.parse()` validates the variant nibble
/// (must be 8/9/a/b) before accepting a namespace string; passing an invalid
/// UUID throws `FormatException` at the call site — at import time, not in a
/// test.  These tests catch any future regeneration that produces an invalid
/// variant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:uuid/uuid.dart';

void main() {
  const u = Uuid();

  group('fronting namespace UUIDs are valid RFC 4122', () {
    for (final entry in {
      'pkFrontingNamespace': pkFrontingNamespace,
      'spFrontingNamespace': spFrontingNamespace,
      'migrationFrontingNamespace': migrationFrontingNamespace,
      'splitNamespace': splitNamespace,
    }.entries) {
      test('${entry.key} (${entry.value}) — v5 succeeds', () {
        // If the namespace is invalid, Uuid().v5() throws FormatException.
        final result = u.v5(entry.value, 'test');
        expect(result, isNotEmpty);
        // The output must itself be a valid v5 UUID.
        expect(
          UuidValue.withValidation(result),
          isNotNull,
          reason: 'v5 output must be a valid UUID',
        );
      });
    }
  });
}
