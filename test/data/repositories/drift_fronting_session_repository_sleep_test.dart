import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

void main() {
  late AppDatabase db;
  late FrontingSessionsDao dao;
  late DriftFrontingSessionRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = FrontingSessionsDao(db);
    repo = DriftFrontingSessionRepository(dao, null);
  });

  tearDown(() => db.close());

  final now = DateTime(2026, 4, 30, 12, 0, 0);

  domain.FrontingSession makeSleep({
    required String id,
    required DateTime start,
    DateTime? end,
    bool isDeleted = false,
  }) {
    return domain.FrontingSession(
      id: id,
      sessionType: domain.SessionType.sleep,
      startTime: start,
      endTime: end,
      isDeleted: isDeleted,
    );
  }

  domain.FrontingSession makeFronting({
    required String id,
    required DateTime start,
    DateTime? end,
  }) {
    return domain.FrontingSession(
      id: id,
      sessionType: domain.SessionType.normal,
      startTime: start,
      endTime: end,
    );
  }

  Future<void> insert(domain.FrontingSession s) async {
    await db.into(db.frontingSessions).insert(
      FrontingSessionsCompanion.insert(
        id: s.id,
        sessionType: Value(s.sessionType.index),
        startTime: s.startTime,
        endTime: Value(s.endTime),
        isDeleted: Value(s.isDeleted),
      ),
    );
  }

  group('getSleepStats', () {
    test('empty DB returns count 0 and null avgDuration', () async {
      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 0);
      expect(stats.avgDuration, isNull);
    });

    test('3 completed sleeps returns correct count and average', () async {
      final base = now.subtract(const Duration(days: 3));
      await insert(makeSleep(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 8)),
      ));
      await insert(makeSleep(
        id: 's2',
        start: base.subtract(const Duration(days: 1)),
        end: base
            .subtract(const Duration(days: 1))
            .add(const Duration(hours: 6)),
      ));
      await insert(makeSleep(
        id: 's3',
        start: base.subtract(const Duration(days: 2)),
        end: base
            .subtract(const Duration(days: 2))
            .add(const Duration(hours: 7)),
      ));

      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 3);
      expect(stats.avgDuration, isNotNull);
      // avg of 8h, 6h, 7h = 7h exactly
      expect(stats.avgDuration!.inMinutes, closeTo(7 * 60, 1));
    });

    test(
      'excludes active sessions (endTime null) from count and average',
      () async {
        final base = now.subtract(const Duration(days: 2));
        await insert(makeSleep(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 8)),
        ));
        // Active — no endTime
        await insert(
          makeSleep(id: 's2', start: base.subtract(const Duration(hours: 2))),
        );

        final stats = await repo.getSleepStats(
          since: now.subtract(const Duration(days: 7)),
        );
        expect(stats.count, 1);
        expect(stats.avgDuration!.inHours, 8);
      },
    );

    test('excludes non-sleep sessions from count and average', () async {
      final base = now.subtract(const Duration(days: 2));
      await insert(makeSleep(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 8)),
      ));
      await insert(makeFronting(
        id: 'f1',
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 1)),
      ));

      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 1);
    });

    test('excludes deleted rows from count and average', () async {
      final base = now.subtract(const Duration(days: 2));
      await insert(makeSleep(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 8)),
      ));
      await insert(makeSleep(
        id: 's2',
        start: base.subtract(const Duration(hours: 4)),
        end: base
            .subtract(const Duration(hours: 4))
            .add(const Duration(hours: 6)),
        isDeleted: true,
      ));

      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 1);
      expect(stats.avgDuration!.inHours, 8);
    });

    test('excludes zero-duration sessions (endTime == startTime)', () async {
      final base = now.subtract(const Duration(days: 2));
      await insert(makeSleep(
        id: 's1',
        start: base,
        end: base, // zero duration
      ));
      await insert(makeSleep(
        id: 's2',
        start: base.subtract(const Duration(hours: 1)),
        end: base
            .subtract(const Duration(hours: 1))
            .add(const Duration(hours: 7)),
      ));

      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 1);
      expect(stats.avgDuration!.inHours, 7);
    });

    test('excludes negative-duration sessions (endTime < startTime)', () async {
      final base = now.subtract(const Duration(days: 2));
      await insert(makeSleep(
        id: 's1',
        start: base,
        end: base.subtract(const Duration(hours: 1)), // negative duration
      ));
      await insert(makeSleep(
        id: 's2',
        start: base.subtract(const Duration(hours: 2)),
        end: base
            .subtract(const Duration(hours: 2))
            .add(const Duration(hours: 8)),
      ));

      final stats = await repo.getSleepStats(
        since: now.subtract(const Duration(days: 7)),
      );
      expect(stats.count, 1);
      expect(stats.avgDuration!.inHours, 8);
    });

    test('until arg returns prior-week aggregate with no overlap', () async {
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final fourteenDaysAgo = now.subtract(const Duration(days: 14));

      // Prior week session (14–7 days ago window)
      final priorBase = now.subtract(const Duration(days: 10));
      await insert(makeSleep(
        id: 'old1',
        start: priorBase,
        end: priorBase.add(const Duration(hours: 9)),
      ));

      // Current week session (within 7 days)
      final recentBase = now.subtract(const Duration(days: 3));
      await insert(makeSleep(
        id: 'new1',
        start: recentBase,
        end: recentBase.add(const Duration(hours: 6)),
      ));

      final priorStats = await repo.getSleepStats(
        since: fourteenDaysAgo,
        until: sevenDaysAgo,
      );
      expect(priorStats.count, 1);
      expect(priorStats.avgDuration!.inHours, 9);

      final recentStats = await repo.getSleepStats(since: sevenDaysAgo);
      expect(recentStats.count, 1);
      expect(recentStats.avgDuration!.inHours, 6);
    });
  });

  group('watchRecentSleepSessions', () {
    test('emits at most limit sessions, newest first by startTime', () async {
      for (var i = 0; i < 8; i++) {
        final base = now.subtract(Duration(days: i + 1));
        await insert(makeSleep(
          id: 's$i',
          start: base,
          end: base.add(const Duration(hours: 7)),
        ));
      }

      final sessions = await repo.watchRecentSleepSessions(limit: 5).first;
      expect(sessions, hasLength(5));
      // newest first — s0 is most recent (1 day ago)
      expect(sessions.first.id, 's0');
      for (var i = 0; i < sessions.length - 1; i++) {
        expect(
          sessions[i].startTime.isAfter(sessions[i + 1].startTime),
          isTrue,
        );
      }
    });

    test('excludes active sessions (endTime null)', () async {
      final base = now.subtract(const Duration(days: 1));
      await insert(makeSleep(
        id: 'completed',
        start: base,
        end: base.add(const Duration(hours: 8)),
      ));
      await insert(
        makeSleep(id: 'active', start: now.subtract(const Duration(hours: 2))),
      );

      final sessions = await repo.watchRecentSleepSessions(limit: 10).first;
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 'completed');
    });

    test('excludes deleted rows', () async {
      final base = now.subtract(const Duration(days: 1));
      await insert(makeSleep(
        id: 'alive',
        start: base,
        end: base.add(const Duration(hours: 8)),
      ));
      await insert(makeSleep(
        id: 'dead',
        start: base.subtract(const Duration(hours: 2)),
        end: base
            .subtract(const Duration(hours: 2))
            .add(const Duration(hours: 7)),
        isDeleted: true,
      ));

      final sessions = await repo.watchRecentSleepSessions(limit: 10).first;
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 'alive');
    });

    test('empty DB emits empty list', () async {
      final sessions = await repo.watchRecentSleepSessions(limit: 5).first;
      expect(sessions, isEmpty);
    });
  });
}
