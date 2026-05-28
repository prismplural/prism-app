import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

void main() {
  group('analytics "All time" range', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      // Keep the analytics provider alive across rebuilds.
      container.listen<AsyncValue<FrontingAnalytics>>(
        frontingAnalyticsProvider,
        (_, _) {},
        fireImmediately: true,
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> insert(String id, DateTime start, {bool deleted = false}) {
      return db.frontingSessionsDao.insertSession(
        FrontingSessionMapper.toCompanion(
          FrontingSession(
            id: id,
            memberId: 'a',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            isDeleted: deleted,
          ),
        ),
      );
    }

    Future<FrontingAnalytics> readAnalytics() => container
        .read(frontingAnalyticsProvider.future)
        .timeout(const Duration(seconds: 2));

    void expectStartNear(DateTime actual, DateTime expected) {
      // Drift stores DateTime as unix seconds, so the round-tripped start
      // loses sub-second precision — compare within a 1s tolerance.
      expect(actual.difference(expected).inSeconds.abs(), lessThanOrEqualTo(1));
    }

    test('selectAllTime flips isAllTime synchronously', () {
      container.read(analyticsRangeProvider.notifier).selectAllTime();
      expect(container.read(analyticsRangeProvider).isAllTime, isTrue);
    });

    test('range starts at the earliest session, not a fixed lookback', () async {
      final earliest = DateTime.now().subtract(const Duration(days: 730));
      await insert('first', earliest);
      await insert('later', DateTime.now().subtract(const Duration(days: 1)));

      container.read(analyticsRangeProvider.notifier).selectAllTime();
      final analytics = await readAnalytics();

      expectStartNear(analytics.rangeStart, earliest);
    });

    test(
      'self-corrects when the earliest session is deleted (no stale gap)',
      () async {
        final first = DateTime.now().subtract(const Duration(days: 730));
        final second = DateTime.now().subtract(const Duration(days: 100));
        await insert('first', first);
        await insert('second', second);

        container.read(analyticsRangeProvider.notifier).selectAllTime();
        final before = await readAnalytics();
        expectStartNear(before.rangeStart, first);

        // Remove the first row; the range must advance to the next-earliest
        // session rather than stranding the old start as phantom gap time.
        await db.frontingSessionsDao.softDeleteSession('first');
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final after = await readAnalytics();
        expectStartNear(after.rangeStart, second);
      },
    );

    test('ignores soft-deleted sessions when finding the earliest', () async {
      final tombstone = DateTime.now().subtract(const Duration(days: 2000));
      await insert('dead', tombstone, deleted: true);
      final liveStart = DateTime.now().subtract(const Duration(days: 100));
      await insert('live', liveStart);

      container.read(analyticsRangeProvider.notifier).selectAllTime();
      final analytics = await readAnalytics();

      expectStartNear(analytics.rangeStart, liveStart);
    });

    test('falls back to a 30-day window when there are no sessions', () async {
      container.read(analyticsRangeProvider.notifier).selectAllTime();
      final analytics = await readAnalytics();

      expect(analytics.totalSessions, 0);
      final spanDays = analytics.rangeEnd
          .difference(analytics.rangeStart)
          .inDays;
      expect(spanDays, inInclusiveRange(29, 31));
    });
  });
}
