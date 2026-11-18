import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';

// Characterization only: no daily-sum or overlapping-session product policy.
void main() {
  late AppDatabase db;
  late DriftFrontingSessionRepository repo;
  final now = DateTime(2026, 11, 18, 12);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
  });
  tearDown(() => db.close());

  Future<void> seed(String id, DateTime start, DateTime? end) => db
      .into(db.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: id,
          sessionType: const drift.Value(1),
          startTime: start,
          endTime: drift.Value(end),
        ),
      )
      .then((_) {});

  Future<SleepStatsView> view() async {
    final container = ProviderContainer(
      overrides: [
        frontingSessionRepositoryProvider.overrideWithValue(repo),
        sleepStatsClockProvider.overrideWithValue(() => now),
        frontingTableTickerProvider.overrideWith(
          (ref) => const Stream<int>.empty(),
        ),
      ],
    );
    try {
      final sub = container.listen(sleepStatsProvider, (_, _) {});
      try {
        return await container.read(sleepStatsProvider.future);
      } finally {
        sub.close();
      }
    } finally {
      container.dispose();
    }
  }

  test(
    'two completed sleeps same day: latest card but both in average and storage',
    () async {
      await seed('early', DateTime(2026, 11, 18, 0), DateTime(2026, 11, 18, 4));
      await seed('late', DateTime(2026, 11, 18, 6), DateTime(2026, 11, 18, 8));
      final stats = await view();
      expect(stats.totalEverCount, 2);
      expect(stats.lastNight!.id, 'late');
      expect(stats.lastNight!.duration, const Duration(hours: 2));
      expect(stats.avg7d, (count: 2, avgDuration: const Duration(hours: 3)));
      expect((await repo.watchRecentSleepSessions(limit: 20).first).length, 2);
    },
  );

  test(
    'overlaps count as individual sessions, not union or daily sum',
    () async {
      await seed('a', DateTime(2026, 11, 18, 0), DateTime(2026, 11, 18, 4));
      await seed('b', DateTime(2026, 11, 18, 2), DateTime(2026, 11, 18, 6));
      final stats = await view();
      expect(stats.avg7d, (count: 2, avgDuration: const Duration(hours: 4)));
      expect(stats.lastNight!.id, 'b');
    },
  );

  test(
    'cross-midnight sleep contributes full duration by ending window',
    () async {
      await seed(
        'overnight',
        DateTime(2026, 11, 17, 23),
        DateTime(2026, 11, 18, 7),
      );
      await seed('nap', DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 10));
      final stats = await view();
      expect(stats.avg7d, (
        count: 2,
        avgDuration: const Duration(hours: 4, minutes: 30),
      ));
      final today = await repo.getSleepStats(
        since: DateTime(2026, 11, 18),
        until: now,
      );
      expect(today, stats.avg7d);
      expect(stats.lastNight!.id, 'nap');
    },
  );

  test('latest means latest start, not latest end', () async {
    await seed('long', DateTime(2026, 11, 17, 22), DateTime(2026, 11, 18, 8));
    await seed('nested', DateTime(2026, 11, 18, 1), DateTime(2026, 11, 18, 2));
    expect((await view()).lastNight!.id, 'nested');
  });

  test('active sleep does not replace the last completed session', () async {
    await seed('done', DateTime(2026, 11, 18, 0), DateTime(2026, 11, 18, 4));
    await seed('active', DateTime(2026, 11, 18, 6), null);
    final stats = await view();
    expect(stats.lastNight!.id, 'done');
    expect(stats.avg7d, (count: 1, avgDuration: const Duration(hours: 4)));
  });
}
