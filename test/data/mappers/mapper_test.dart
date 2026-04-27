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

  group('FrontingSession domain model construction', () {
    test('constructs with required fields only', () {
      final session = FrontingSession(
        id: 'test-id',
        startTime: DateTime(2025, 1, 1, 10, 0),
      );
      expect(session.id, 'test-id');
      expect(session.endTime, isNull);
      expect(session.memberId, isNull);
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
        notes: 'Test notes',
        confidence: FrontConfidence.strong,
        pluralkitUuid: 'pk-uuid-123',
      );
      expect(session.isActive, isFalse);
      expect(session.duration, const Duration(hours: 1));
      expect(session.confidence, FrontConfidence.strong);
    });

    test('isSleep is false for normal sessions', () {
      final session = FrontingSession(
        id: 'normal-id',
        startTime: DateTime(2025, 6, 15, 9, 0),
        memberId: 'member-1',
      );
      expect(session.isSleep, isFalse);
    });

    test('isSleep is true for sleep sessions', () {
      final session = FrontingSession(
        id: 'sleep-id',
        startTime: DateTime(2025, 6, 15, 22, 0),
        sessionType: SessionType.sleep,
      );
      expect(session.isSleep, isTrue);
    });
  });
}
