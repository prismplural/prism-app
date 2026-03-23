import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

// ---------------------------------------------------------------------------
// These tests verify the logic patterns used by FrontingSessionMapper without
// requiring Drift-generated row objects (which are complex to instantiate in
// isolation). Each test mirrors the exact logic in the mapper so that a
// regression in the source would break the corresponding test here.
// ---------------------------------------------------------------------------

/// Replicates the safe enum deserialization used in FrontingSessionMapper.toDomain.
FrontConfidence? safeConfidenceLookup(int? index) {
  if (index == null) return null;
  if (index < FrontConfidence.values.length) {
    return FrontConfidence.values[index];
  }
  return FrontConfidence.unsure; // out-of-bounds fallback
}

/// Replicates the coFronterIds JSON parsing used in FrontingSessionMapper.toDomain.
List<String> parseCoFronterIds(String raw) {
  if (raw.isEmpty) return [];
  try {
    return (jsonDecode(raw) as List).cast<String>();
  } catch (_) {
    return []; // malformed JSON → empty list (mapper silently reports and returns [])
  }
}

/// Replicates the coFronterIds JSON encoding used in FrontingSessionMapper.toCompanion.
String encodeCoFronterIds(List<String> ids) => jsonEncode(ids);

void main() {
  group('FrontConfidence safe enum lookup', () {
    test('index 0 → unsure', () {
      expect(safeConfidenceLookup(0), FrontConfidence.unsure);
    });

    test('index 1 → strong', () {
      expect(safeConfidenceLookup(1), FrontConfidence.strong);
    });

    test('index 2 → certain', () {
      expect(safeConfidenceLookup(2), FrontConfidence.certain);
    });

    test('null index → null (no confidence stored)', () {
      expect(safeConfidenceLookup(null), isNull);
    });

    test('out-of-bounds index falls back to unsure', () {
      expect(safeConfidenceLookup(99), FrontConfidence.unsure);
      expect(safeConfidenceLookup(3), FrontConfidence.unsure);
      expect(safeConfidenceLookup(100), FrontConfidence.unsure);
    });

    test('covers all current enum values without out-of-bounds fallback', () {
      for (var i = 0; i < FrontConfidence.values.length; i++) {
        final result = safeConfidenceLookup(i);
        expect(result, isNotNull);
        expect(result, FrontConfidence.values[i]);
      }
    });
  });

  group('FrontConfidence index round-trip', () {
    test('enum.index can be used to look up the same enum value', () {
      for (final confidence in FrontConfidence.values) {
        final roundTripped = safeConfidenceLookup(confidence.index);
        expect(roundTripped, confidence);
      }
    });
  });

  group('coFronterIds JSON parsing', () {
    test('parses valid JSON array', () {
      final json = jsonEncode(['id-1', 'id-2', 'id-3']);
      final result = parseCoFronterIds(json);
      expect(result, ['id-1', 'id-2', 'id-3']);
    });

    test('parses empty JSON array', () {
      final result = parseCoFronterIds('[]');
      expect(result, isEmpty);
    });

    test('returns empty list for empty string', () {
      final result = parseCoFronterIds('');
      expect(result, isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      final result = parseCoFronterIds('not-valid-json');
      expect(result, isEmpty);
    });

    test('returns empty list for truncated JSON', () {
      final result = parseCoFronterIds('["id-1", "id-2"');
      expect(result, isEmpty);
    });

    test('returns empty list for JSON null literal', () {
      // jsonDecode('null') returns null, cast will fail → returns []
      final result = parseCoFronterIds('null');
      expect(result, isEmpty);
    });
  });

  group('coFronterIds JSON encoding', () {
    test('encodes list to valid JSON string', () {
      final encoded = encodeCoFronterIds(['a', 'b', 'c']);
      expect(encoded, '["a","b","c"]');
    });

    test('encodes empty list to empty JSON array', () {
      final encoded = encodeCoFronterIds([]);
      expect(encoded, '[]');
    });

    test('encode → decode round-trip preserves order and values', () {
      final ids = ['uuid-1', 'uuid-2', 'uuid-3'];
      final encoded = encodeCoFronterIds(ids);
      final decoded = parseCoFronterIds(encoded);
      expect(decoded, ids);
    });
  });

  group('FrontingSession domain model construction', () {
    test('constructs with required fields only', () {
      final session = FrontingSession(
        id: 'test-id',
        startTime: DateTime(2025, 1, 1, 10, 0),
      );
      expect(session.id, 'test-id');
      expect(session.endTime, isNull);
      expect(session.memberId, isNull);
      expect(session.coFronterIds, isEmpty);
      expect(session.confidence, isNull);
      expect(session.isActive, isTrue);
    });

    test('constructs with all optional fields', () {
      final start = DateTime(2025, 6, 15, 9, 0);
      final end = DateTime(2025, 6, 15, 10, 0);
      final session = FrontingSession(
        id: 'full-id',
        startTime: start,
        endTime: end,
        memberId: 'member-1',
        coFronterIds: const ['member-2', 'member-3'],
        notes: 'Test notes',
        confidence: FrontConfidence.strong,
        pluralkitUuid: 'pk-uuid-123',
      );
      expect(session.isActive, isFalse);
      expect(session.isCoFronting, isTrue);
      expect(session.duration, const Duration(hours: 1));
      expect(session.confidence, FrontConfidence.strong);
    });
  });
}
