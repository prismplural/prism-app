// Sleep sessions use a different grouping strategy than fronting sessions.
// [splitAtMidnight] splits cross-midnight sessions into two continuation slices
// so you can see who was fronting on each calendar day. Sleep sessions are
// single events keyed by wake-date — a session that starts Monday night and
// ends Tuesday morning belongs to Tuesday only, matching how people recall
// "last night's sleep". [groupSleepByEndDate] implements that model.

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';

FrontingSession _sleep({
  required String id,
  required DateTime start,
  DateTime? end,
}) =>
    FrontingSession(
      id: id,
      startTime: start,
      endTime: end,
      sessionType: SessionType.sleep,
    );

void main() {
  group('groupSleepByEndDate', () {
    test('session wholly within one day is keyed by that date', () {
      final session = _sleep(
        id: 's1',
        start: DateTime(2026, 3, 10, 22, 0),
        end: DateTime(2026, 3, 10, 23, 30),
      );

      final result = groupSleepByEndDate([session]);

      expect(result.keys, [DateTime(2026, 3, 10)]);
      expect(result[DateTime(2026, 3, 10)], [session]);
    });

    test('cross-midnight session keyed by end date only (no split)', () {
      final session = _sleep(
        id: 's2',
        start: DateTime(2026, 3, 10, 23, 30), // 11:30 PM Monday
        end: DateTime(2026, 3, 11, 6, 30), // 6:30 AM Tuesday
      );

      final result = groupSleepByEndDate([session]);

      // Must appear under Tuesday only — NOT split across Monday and Tuesday.
      expect(result.keys, [DateTime(2026, 3, 11)]);
      expect(result[DateTime(2026, 3, 11)], [session]);
      expect(result[DateTime(2026, 3, 10)], isNull);
    });

    test('active session (endTime == null) keyed by start date', () {
      final session = _sleep(
        id: 's3',
        start: DateTime(2026, 3, 12, 21, 0),
        end: null,
      );

      final result = groupSleepByEndDate([session]);

      expect(result.keys, [DateTime(2026, 3, 12)]);
      expect(result[DateTime(2026, 3, 12)], [session]);
    });

    test('multiple sessions on the same wake-date are grouped together', () {
      final s1 = _sleep(
        id: 's1',
        start: DateTime(2026, 3, 14, 22, 0),
        end: DateTime(2026, 3, 15, 6, 0),
      );
      final s2 = _sleep(
        id: 's2',
        start: DateTime(2026, 3, 14, 23, 45),
        end: DateTime(2026, 3, 15, 7, 15),
      );

      final result = groupSleepByEndDate([s1, s2]);

      expect(result.keys, [DateTime(2026, 3, 15)]);
      expect(result[DateTime(2026, 3, 15)], [s1, s2]);
    });

    test('input order is preserved within a group', () {
      final s1 = _sleep(
        id: 'first',
        start: DateTime(2026, 3, 20, 21, 0),
        end: DateTime(2026, 3, 21, 5, 0),
      );
      final s2 = _sleep(
        id: 'second',
        start: DateTime(2026, 3, 20, 23, 0),
        end: DateTime(2026, 3, 21, 6, 0),
      );
      final s3 = _sleep(
        id: 'third',
        start: DateTime(2026, 3, 20, 22, 0),
        end: DateTime(2026, 3, 21, 5, 30),
      );

      final result = groupSleepByEndDate([s1, s2, s3]);

      expect(
        result[DateTime(2026, 3, 21)]!.map((s) => s.id).toList(),
        ['first', 'second', 'third'],
      );
    });

    test('empty input returns empty map', () {
      final result = groupSleepByEndDate([]);
      expect(result, isEmpty);
    });

    test('map keys are midnight DateTime (00:00:00) for clean equality', () {
      final session = _sleep(
        id: 's1',
        start: DateTime(2026, 4, 5, 22, 30),
        end: DateTime(2026, 4, 6, 7, 45),
      );

      final result = groupSleepByEndDate([session]);
      final key = result.keys.first;

      expect(key.hour, 0);
      expect(key.minute, 0);
      expect(key.second, 0);
      expect(key.millisecond, 0);
      expect(key.microsecond, 0);
    });
  });
}
