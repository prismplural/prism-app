import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

void main() {
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
