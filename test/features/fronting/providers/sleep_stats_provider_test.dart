import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';

// ---------------------------------------------------------------------------
// Fake repo for sleep stats tests
// ---------------------------------------------------------------------------

class _FakeRepo implements FrontingSessionRepository {
  List<FrontingSession> _sessions = [];

  void seed(List<FrontingSession> sessions) => _sessions = List.of(sessions);

  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) async {
    final end = until ?? DateTime.now();
    final matching = _sessions
        .where(
          (s) =>
              s.isSleep &&
              !s.isActive &&
              s.endTime != null &&
              !s.endTime!.isBefore(since) &&
              s.endTime!.isBefore(end),
        )
        .toList();
    if (matching.isEmpty) return (count: 0, avgDuration: null);
    final totalMs = matching.fold<int>(
      0,
      (sum, s) => sum + s.endTime!.difference(s.startTime).inMilliseconds,
    );
    return (
      count: matching.length,
      avgDuration: Duration(milliseconds: totalMs ~/ matching.length),
    );
  }

  @override
  Stream<List<FrontingSession>> watchRecentSleepSessions({int limit = 20}) {
    return Stream.value(
      _sessions.where((s) => s.isSleep && !s.isActive).take(limit).toList(),
    );
  }

  // --- Stubs for unused interface members ---
  @override
  Future<List<FrontingSession>> getAllSessions() async => const [];
  @override
  Future<List<FrontingSession>> getFrontingSessions() async => const [];
  @override
  Stream<List<FrontingSession>> watchAllSessions() => Stream.value(const []);
  @override
  Future<List<FrontingSession>> getActiveSessions() async => const [];
  @override
  Future<List<FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      const [];
  @override
  Stream<List<FrontingSession>> watchActiveSessions() => Stream.value(const []);
  @override
  Future<FrontingSession?> getActiveSession() async => null;
  @override
  Stream<FrontingSession?> watchActiveSession() => Stream.value(null);
  @override
  Stream<FrontingSession?> watchActiveSleepSession() => Stream.value(null);
  @override
  Stream<List<FrontingSession>> watchAllSleepSessions() =>
      Stream.value(const []);
  @override
  Future<FrontingSession?> getSessionById(String id) async => null;
  @override
  Stream<FrontingSession?> watchSessionById(String id) => Stream.value(null);
  @override
  Future<List<FrontingSession>> getSessionsForMember(String memberId) async =>
      const [];
  @override
  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) async =>
      const [];
  @override
  Future<List<FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async => const [];
  @override
  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(const []);
  @override
  Stream<List<FrontingSession>> watchRecentAllSessions({int limit = 30}) =>
      Stream.value(const []);
  @override
  Future<void> createSession(FrontingSession session) async {}
  @override
  Future<void> updateSession(FrontingSession session) async {}
  @override
  Future<void> endSession(String id, DateTime endTime) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Future<List<FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
  @override
  Future<int> getCount() async => 0;
  @override
  Future<int> getFrontingCount() async => 0;
  @override
  Future<List<FrontingSession>> getDeletedLinkedSessions() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}
  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) async => {};
  @override
  Stream<List<FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) => Stream.value(const []);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FrontingSession _sleepSession({
  required String id,
  required DateTime start,
  required DateTime end,
}) => FrontingSession(
  id: id,
  startTime: start,
  endTime: end,
  sessionType: SessionType.sleep,
);

ProviderContainer _makeContainer(_FakeRepo repo, {DateTime? now}) {
  final container = ProviderContainer(
    overrides: [
      frontingSessionRepositoryProvider.overrideWithValue(repo),
      if (now != null) sleepStatsClockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final now = DateTime(2026, 4, 30, 12, 0);

  group('sleepStatsProvider', () {
    test('empty repo → all zeros, no lastNight', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo, now: now);

      final stats = await container.read(sleepStatsProvider.future);

      expect(stats.totalEverCount, 0);
      expect(stats.lastNight, isNull);
      expect(stats.avg7d, (count: 0, avgDuration: null));
      expect(stats.avg7dPrior, (count: 0, avgDuration: null));
    });

    test(
      'one sleep within last 7d → lastNight populated, avg7d.count == 1',
      () async {
        final repo = _FakeRepo();
        repo.seed([
          _sleepSession(
            id: 's1',
            start: now.subtract(const Duration(days: 1)),
            end: now.subtract(
              const Duration(days: 1) - const Duration(hours: 8),
            ),
          ),
        ]);
        final container = _makeContainer(repo, now: now);

        final stats = await container.read(sleepStatsProvider.future);

        expect(stats.totalEverCount, 1);
        expect(stats.lastNight, isNotNull);
        expect(stats.lastNight!.id, 's1');
        expect(stats.avg7d.count, 1);
        expect(stats.avg7d.avgDuration, isNotNull);
        expect(stats.avg7dPrior.count, 0);
        expect(stats.avg7dPrior.avgDuration, isNull);
      },
    );

    test(
      '3 in last 7d, 2 in prior 7d → both populated, totalEverCount == 5',
      () async {
        final repo = _FakeRepo();
        repo.seed([
          // 3 in current 7d window
          _sleepSession(
            id: 'c1',
            start: now.subtract(const Duration(days: 1)),
            end: now.subtract(
              const Duration(days: 1) - const Duration(hours: 7),
            ),
          ),
          _sleepSession(
            id: 'c2',
            start: now.subtract(const Duration(days: 3)),
            end: now.subtract(
              const Duration(days: 3) - const Duration(hours: 8),
            ),
          ),
          _sleepSession(
            id: 'c3',
            start: now.subtract(const Duration(days: 5)),
            end: now.subtract(
              const Duration(days: 5) - const Duration(hours: 9),
            ),
          ),
          // 2 in prior 7d window (8-14 days ago)
          _sleepSession(
            id: 'p1',
            start: now.subtract(const Duration(days: 8)),
            end: now.subtract(
              const Duration(days: 8) - const Duration(hours: 8),
            ),
          ),
          _sleepSession(
            id: 'p2',
            start: now.subtract(const Duration(days: 12)),
            end: now.subtract(
              const Duration(days: 12) - const Duration(hours: 7),
            ),
          ),
        ]);
        final container = _makeContainer(repo, now: now);

        final stats = await container.read(sleepStatsProvider.future);

        expect(stats.totalEverCount, 5);
        expect(stats.avg7d.count, 3);
        expect(stats.avg7d.avgDuration, isNotNull);
        expect(stats.avg7dPrior.count, 2);
        expect(stats.avg7dPrior.avgDuration, isNotNull);
      },
    );

    test('invalidation causes re-evaluation against fresh repo state', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo, now: now);

      // First read — empty
      final before = await container.read(sleepStatsProvider.future);
      expect(before.totalEverCount, 0);

      // Add a session, then invalidate (mirrors what frontingTableTickerProvider
      // emissions trigger via ref.watch in production)
      repo.seed([
        _sleepSession(
          id: 'new',
          start: now.subtract(const Duration(days: 1)),
          end: now.subtract(const Duration(days: 1) - const Duration(hours: 8)),
        ),
      ]);
      container.invalidate(sleepStatsProvider);

      final after = await container.read(sleepStatsProvider.future);
      expect(after.totalEverCount, 1);
    });
  });

  group('SleepStatsView equality', () {
    test('equal when all fields match', () {
      const a = SleepStatsView(
        totalEverCount: 5,
        lastNight: null,
        avg7d: (count: 3, avgDuration: Duration(hours: 8)),
        avg7dPrior: (count: 2, avgDuration: Duration(hours: 7)),
      );
      const b = SleepStatsView(
        totalEverCount: 5,
        lastNight: null,
        avg7d: (count: 3, avgDuration: Duration(hours: 8)),
        avg7dPrior: (count: 2, avgDuration: Duration(hours: 7)),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when totalEverCount differs', () {
      const a = SleepStatsView(
        totalEverCount: 5,
        lastNight: null,
        avg7d: (count: 0, avgDuration: null),
        avg7dPrior: (count: 0, avgDuration: null),
      );
      const b = SleepStatsView(
        totalEverCount: 6,
        lastNight: null,
        avg7d: (count: 0, avgDuration: null),
        avg7dPrior: (count: 0, avgDuration: null),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
