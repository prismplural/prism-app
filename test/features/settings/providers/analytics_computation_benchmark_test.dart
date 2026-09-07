@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

class _FakeSession {
  _FakeSession({
    required this.startTime,
    required this.endTime,
    required this.memberId,
  });

  final DateTime startTime;
  final DateTime endTime;
  final String memberId;
  int get sessionType => 0;
}

void main() {
  group('sweep-line pair-overlap performance', () {
    test('5000 members × 4 sessions completes in < 2s (JIT)', () {
      final base = DateTime.utc(2026, 3, 1);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 30)),
      );
      const memberCount = 5000;
      const totalMinutes = 30 * 24 * 60;
      final sessions = <_FakeSession>[];
      for (var member = 0; member < memberCount; member++) {
        final offset = member * totalMinutes ~/ memberCount;
        for (var session = 0; session < 4; session++) {
          final start = base.add(
            Duration(minutes: offset + session * 7 * 24 * 60),
          );
          sessions.add(
            _FakeSession(
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              memberId: 'm$member',
            ),
          );
        }
      }
      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();
      expect(result.totalSessions, 20000);
      expect(result.uniqueFronters, memberCount);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason:
            'sweep-line on 20k sessions took ${stopwatch.elapsedMilliseconds}ms (JIT)',
      );
    });

    test('10 heavy co-fronters × 200 sessions each: sub-100ms', () {
      final base = DateTime.utc(2026, 3, 1);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 30)),
      );
      final sessions = <_FakeSession>[];
      for (var member = 0; member < 10; member++) {
        for (var session = 0; session < 200; session++) {
          final start = base.add(
            Duration(hours: session * 3, minutes: member * 10),
          );
          sessions.add(
            _FakeSession(
              startTime: start,
              endTime: start.add(const Duration(hours: 2)),
              memberId: 'h$member',
            ),
          );
        }
      }
      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();
      expect(result.uniqueFronters, 10);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason:
            'heavy co-fronter scenario took ${stopwatch.elapsedMilliseconds}ms',
      );
    });
  });
}
