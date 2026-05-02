import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/co_front_detector.dart';

void main() {
  FrontingSession session({
    required String id,
    required String? memberId,
    required DateTime start,
    DateTime? end,
    SessionType type = SessionType.normal,
    bool isDeleted = false,
  }) => FrontingSession(
    id: id,
    memberId: memberId,
    startTime: start,
    endTime: end,
    sessionType: type,
    isDeleted: isDeleted,
  );

  group('sessionsCoFront', () {
    final t0 = DateTime.utc(2026, 4, 30, 10);
    final t1 = DateTime.utc(2026, 4, 30, 11);
    final t2 = DateTime.utc(2026, 4, 30, 12);
    final t3 = DateTime.utc(2026, 4, 30, 13);

    test('detects overlapping sessions for different members', () {
      final a = session(id: 'a', memberId: 'alice', start: t0, end: t2);
      final b = session(id: 'b', memberId: 'bob', start: t1, end: t3);

      expect(sessionsCoFront(a, [b]), isTrue);
      expect(sessionsCoFront(b, [a]), isTrue);
    });

    test('treats touching half-open ranges as non-overlapping', () {
      final a = session(id: 'a', memberId: 'alice', start: t0, end: t1);
      final b = session(id: 'b', memberId: 'bob', start: t1, end: t2);

      expect(sessionsCoFront(a, [b]), isFalse);
    });

    test('ignores same-member, sleep, deleted, and null-member rows', () {
      final a = session(id: 'a', memberId: 'alice', start: t0, end: t2);
      final sameMember = session(
        id: 'same',
        memberId: 'alice',
        start: t1,
        end: t3,
      );
      final sleep = session(
        id: 'sleep',
        memberId: null,
        start: t1,
        end: t3,
        type: SessionType.sleep,
      );
      final deleted = session(
        id: 'deleted',
        memberId: 'bob',
        start: t1,
        end: t3,
        isDeleted: true,
      );
      final orphan = session(id: 'orphan', memberId: null, start: t1, end: t3);

      expect(sessionsCoFront(a, [sameMember, sleep, deleted, orphan]), isFalse);
    });

    test('handles open-ended sessions', () {
      final open = session(id: 'open', memberId: 'alice', start: t0);
      final later = session(id: 'later', memberId: 'bob', start: t2, end: t3);

      expect(sessionsCoFront(open, [later]), isTrue);
    });
  });
}
