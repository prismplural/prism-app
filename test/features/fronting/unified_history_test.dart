import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';

FrontingSession _fronting({
  required DateTime start,
  DateTime? end,
  String? memberId,
}) =>
    FrontingSession(
      id: 'fronting-${start.millisecondsSinceEpoch}',
      startTime: start,
      endTime: end,
      memberId: memberId ?? 'member-1',
      sessionType: SessionType.normal,
    );

FrontingSession _sleep({
  required DateTime start,
  DateTime? end,
  SleepQuality? quality,
}) =>
    FrontingSession(
      id: 'sleep-${start.millisecondsSinceEpoch}',
      startTime: start,
      endTime: end,
      sessionType: SessionType.sleep,
      quality: quality,
    );

void main() {
  group('groupSessionsByDay with mixed session types', () {
    test('fronting and sleep sessions interleave within the same day', () {
      final sessions = [
        _fronting(
          start: DateTime(2026, 4, 1, 10, 0),
          end: DateTime(2026, 4, 1, 12, 0),
        ),
        _sleep(
          start: DateTime(2026, 4, 1, 0, 30),
          end: DateTime(2026, 4, 1, 7, 0),
          quality: SleepQuality.good,
        ),
        _fronting(
          start: DateTime(2026, 4, 1, 14, 0),
          end: DateTime(2026, 4, 1, 16, 0),
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(1));
      expect(groups[0].dayKey, '2026-04-01');
      expect(groups[0].sessions, hasLength(3));

      // All three sessions should be present (order depends on input order,
      // not startTime, since groupSessionsByDay doesn't sort within a day).
      final ids = groups[0].sessions.map((s) => s.session.id).toList();
      expect(ids, contains(startsWith('fronting-')));
      expect(ids, contains(startsWith('sleep-')));
    });

    test('sleep session spanning midnight splits into two day groups', () {
      final sessions = [
        _sleep(
          start: DateTime(2026, 3, 31, 23, 0),
          end: DateTime(2026, 4, 1, 7, 0),
          quality: SleepQuality.fair,
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      expect(groups, hasLength(2));
      // Newest day first
      expect(groups[0].dayKey, '2026-04-01');
      expect(groups[1].dayKey, '2026-03-31');

      // Both slices reference the same sleep session
      expect(groups[0].sessions[0].session.isSleep, isTrue);
      expect(groups[1].sessions[0].session.isSleep, isTrue);

      // First day slice is a continuation, second is the original start
      expect(groups[0].sessions[0].isContinuation, isTrue);
      expect(groups[1].sessions[0].continuesNextDay, isTrue);
    });

    test('sessions from different days end up in different groups', () {
      final sessions = [
        _fronting(
          start: DateTime(2026, 4, 1, 10, 0),
          end: DateTime(2026, 4, 1, 12, 0),
        ),
        _sleep(
          start: DateTime(2026, 3, 31, 23, 30),
          end: DateTime(2026, 4, 1, 6, 0),
        ),
        _fronting(
          start: DateTime(2026, 3, 30, 9, 0),
          end: DateTime(2026, 3, 30, 11, 0),
        ),
      ];

      final groups = groupSessionsByDay(sessions);

      // April 1 (fronting + sleep continuation), March 31 (sleep start), March 30 (fronting)
      expect(groups, hasLength(3));
      expect(groups[0].dayKey, '2026-04-01');
      expect(groups[1].dayKey, '2026-03-31');
      expect(groups[2].dayKey, '2026-03-30');
    });

    test('mixed types with midnight split preserves session type on both slices',
        () {
      final sleepSession = _sleep(
        start: DateTime(2026, 4, 2, 22, 30),
        end: DateTime(2026, 4, 3, 6, 0),
      );

      final slices = splitAtMidnight(sleepSession);

      expect(slices, hasLength(2));
      expect(slices[0].session.isSleep, isTrue);
      expect(slices[1].session.isSleep, isTrue);
      expect(slices[0].session.sessionType, SessionType.sleep);
      expect(slices[1].session.sessionType, SessionType.sleep);
    });
  });

  group('DisplaySession.timeRangeString', () {
    test('normal session with start and end shows formatted range', () {
      final session = _fronting(
        start: DateTime(2026, 4, 1, 9, 0),
        end: DateTime(2026, 4, 1, 14, 30),
      );

      final display = DisplaySession(
        session: session,
        displayStart: session.startTime,
        displayEnd: session.endTime,
      );

      // DateFormat.jm() produces locale-dependent output like "9:00 AM"
      expect(display.timeRangeString(), contains('\u2013'));
      expect(display.timeRangeString(), contains('AM'));
      expect(display.timeRangeString(), contains('PM'));
    });

    test('active session with no end shows ongoing', () {
      final session = _fronting(
        start: DateTime(2026, 4, 1, 15, 0),
      );

      final display = DisplaySession(
        session: session,
        displayStart: session.startTime,
        displayEnd: null,
      );

      expect(display.timeRangeString(), endsWith('ongoing'));
      expect(display.timeRangeString(), contains('PM'));
    });

    test('session that continues next day shows midnight end', () {
      final session = _fronting(
        start: DateTime(2026, 4, 1, 23, 0),
        end: DateTime(2026, 4, 2, 2, 0),
      );

      final display = DisplaySession(
        session: session,
        displayStart: session.startTime,
        displayEnd: DateTime(2026, 4, 2), // midnight
        continuesNextDay: true,
      );

      expect(display.timeRangeString(), contains('12:00 AM'));
      expect(display.timeRangeString(), contains('PM'));
    });
  });

  group('pagination guard logic', () {
    bool hasMore(int sessionCount, int limit) => sessionCount >= limit;

    test('fewer sessions than limit means no more pages', () {
      expect(hasMore(5, 20), isFalse);
    });

    test('sessions equal to limit means more pages available', () {
      expect(hasMore(20, 20), isTrue);
    });

    test('sessions greater than limit means more pages available', () {
      expect(hasMore(25, 20), isTrue);
    });

    test('empty sessions means no more pages', () {
      expect(hasMore(0, 20), isFalse);
    });
  });
}
