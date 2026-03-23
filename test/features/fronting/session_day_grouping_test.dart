import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';

FrontingSession _session({
  required DateTime start,
  DateTime? end,
  String id = 'test',
}) {
  return FrontingSession(
    id: id,
    startTime: start,
    endTime: end,
    memberId: 'm1',
  );
}

void main() {
  group('splitAtMidnight', () {
    test('same-day session produces one slice', () {
      final session = _session(
        start: DateTime(2026, 3, 19, 14, 0),
        end: DateTime(2026, 3, 19, 16, 0),
      );

      final slices = splitAtMidnight(session);

      expect(slices, hasLength(1));
      expect(slices[0].isContinuation, isFalse);
      expect(slices[0].continuesNextDay, isFalse);
      expect(slices[0].displayStart, session.startTime);
      expect(slices[0].displayEnd, session.endTime);
    });

    test('session spanning midnight produces two slices', () {
      final session = _session(
        start: DateTime(2026, 3, 19, 23, 0),
        end: DateTime(2026, 3, 20, 2, 0),
      );

      final slices = splitAtMidnight(session);

      expect(slices, hasLength(2));
      // First slice: 11 PM – midnight
      expect(slices[0].displayStart, DateTime(2026, 3, 19, 23, 0));
      expect(slices[0].displayEnd, DateTime(2026, 3, 20));
      expect(slices[0].isContinuation, isFalse);
      expect(slices[0].continuesNextDay, isTrue);
      // Second slice: midnight – 2 AM
      expect(slices[1].displayStart, DateTime(2026, 3, 20));
      expect(slices[1].displayEnd, DateTime(2026, 3, 20, 2, 0));
      expect(slices[1].isContinuation, isTrue);
      expect(slices[1].continuesNextDay, isFalse);
    });

    test('session spanning two midnights produces three slices', () {
      final session = _session(
        start: DateTime(2026, 3, 18, 22, 0),
        end: DateTime(2026, 3, 20, 1, 0),
      );

      final slices = splitAtMidnight(session);

      expect(slices, hasLength(3));
      expect(slices[0].displayStart, DateTime(2026, 3, 18, 22, 0));
      expect(slices[1].displayStart, DateTime(2026, 3, 19));
      expect(slices[2].displayStart, DateTime(2026, 3, 20));
    });
  });

  group('groupSessionsByDay', () {
    test('groups same-day sessions together', () {
      final sessions = [
        _session(
          id: 'a',
          start: DateTime(2026, 3, 19, 16, 0),
          end: DateTime(2026, 3, 19, 18, 0),
        ),
        _session(
          id: 'b',
          start: DateTime(2026, 3, 19, 10, 0),
          end: DateTime(2026, 3, 19, 12, 0),
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(1));
      expect(groups[0].dayKey, '2026-03-19');
      expect(groups[0].sessions, hasLength(2));
    });

    test('sorts day groups newest-first', () {
      final sessions = [
        _session(
          id: 'today',
          start: DateTime(2026, 3, 20, 10, 0),
          end: DateTime(2026, 3, 20, 12, 0),
        ),
        _session(
          id: 'yesterday',
          start: DateTime(2026, 3, 19, 10, 0),
          end: DateTime(2026, 3, 19, 12, 0),
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(2));
      expect(groups[0].dayKey, '2026-03-20'); // Today first
      expect(groups[1].dayKey, '2026-03-19'); // Yesterday second
    });

    test('midnight-spanning session does not flip day order (regression)', () {
      // This is the exact bug scenario: the only "today" session comes from
      // a midnight split of a session that started yesterday. Without the
      // sort fix, encounter order would put yesterday before today.
      final sessions = [
        _session(
          id: 'spanning',
          start: DateTime(2026, 3, 19, 23, 19),
          end: DateTime(2026, 3, 20, 0, 40), // ends past midnight
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(2));
      // Today (2026-03-20) MUST come before yesterday (2026-03-19)
      expect(groups[0].dayKey, '2026-03-20');
      expect(groups[1].dayKey, '2026-03-19');
    });

    test('ongoing session spanning midnight keeps today first', () {
      // Ongoing session started yesterday, still active today.
      // splitAtMidnight produces yesterday slice first, today slice second.
      // The sort must ensure today still appears first.
      final sessions = [
        _session(
          id: 'ongoing',
          start: DateTime(2026, 3, 19, 14, 0),
          // endTime: null → ongoing
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      // Should have at least 2 groups (yesterday and today)
      expect(groups.length, greaterThanOrEqualTo(2));
      // First group should be the most recent day
      final dayKeys = groups.map((g) => g.dayKey).toList();
      // Verify descending order
      for (var i = 0; i < dayKeys.length - 1; i++) {
        expect(
          dayKeys[i].compareTo(dayKeys[i + 1]),
          greaterThan(0),
          reason: 'Day keys should be in descending order',
        );
      }
    });

    test('mixed sessions with midnight splits maintain correct order', () {
      // Yesterday sessions + a session spanning midnight + today-only session
      final sessions = [
        _session(
          id: 'today-only',
          start: DateTime(2026, 3, 20, 9, 0),
          end: DateTime(2026, 3, 20, 10, 0),
        ),
        _session(
          id: 'spanning',
          start: DateTime(2026, 3, 19, 23, 0),
          end: DateTime(2026, 3, 20, 1, 0),
        ),
        _session(
          id: 'yesterday-only',
          start: DateTime(2026, 3, 19, 8, 0),
          end: DateTime(2026, 3, 19, 12, 0),
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(2));
      expect(groups[0].dayKey, '2026-03-20');
      expect(groups[1].dayKey, '2026-03-19');
      // Today should have 2 slices (today-only + midnight continuation)
      expect(groups[0].sessions, hasLength(2));
      // Yesterday should have 2 slices (yesterday-only + midnight start)
      expect(groups[1].sessions, hasLength(2));
    });
  });
}
