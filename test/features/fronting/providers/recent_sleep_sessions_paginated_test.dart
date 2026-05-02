import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements FrontingSessionRepository {
  List<FrontingSession> _sessions = [];

  void seed(List<FrontingSession> sessions) => _sessions = List.of(sessions);

  @override
  Stream<List<FrontingSession>> watchRecentSleepSessions({int limit = 20}) {
    final completed = _sessions.where((s) => s.isSleep && !s.isActive).toList();
    return Stream.value(completed.take(limit).toList());
  }

  // --- Stubs ---
  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) async => (count: 0, avgDuration: null);
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

FrontingSession _sleep(String id, DateTime start, DateTime end) =>
    FrontingSession(
      id: id,
      startTime: start,
      endTime: end,
      sessionType: SessionType.sleep,
    );

/// Reads an autoDispose StreamProvider family by keeping a live listener
/// for the duration of the await to prevent premature disposal.
Future<List<FrontingSession>> _readPaginated(
  ProviderContainer container,
  int limit,
) async {
  final provider = recentSleepSessionsPaginatedProvider(limit);
  final sub = container.listen<AsyncValue<List<FrontingSession>>>(
    provider,
    (_, _) {},
  );
  final result = await container.read(provider.future);
  sub.close();
  return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final base = DateTime(2026, 4, 30, 6, 0);

  group('recentSleepSessionsPaginatedProvider', () {
    test('returns empty list when repo has no sessions', () async {
      final repo = _FakeRepo();
      final container = ProviderContainer(
        overrides: [frontingSessionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result = await _readPaginated(container, 20);
      expect(result, isEmpty);
    });

    test('family key controls slice size — limit 3 returns only 3', () async {
      final repo = _FakeRepo();
      repo.seed([
        for (int i = 0; i < 10; i++)
          _sleep(
            'id-$i',
            base.subtract(Duration(days: i + 1)),
            base.subtract(Duration(days: i + 1) - const Duration(hours: 8)),
          ),
      ]);

      final container = ProviderContainer(
        overrides: [frontingSessionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result = await _readPaginated(container, 3);
      expect(result.length, 3);
    });

    test('family key controls slice size — limit 20 returns all 10', () async {
      final repo = _FakeRepo();
      repo.seed([
        for (int i = 0; i < 10; i++)
          _sleep(
            'id-$i',
            base.subtract(Duration(days: i + 1)),
            base.subtract(Duration(days: i + 1) - const Duration(hours: 8)),
          ),
      ]);

      final container = ProviderContainer(
        overrides: [frontingSessionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result = await _readPaginated(container, 20);
      expect(result.length, 10);
    });

    test('active sleep sessions are excluded', () async {
      final repo = _FakeRepo();
      repo.seed([
        // Completed
        _sleep(
          'done',
          base.subtract(const Duration(days: 1)),
          base.subtract(const Duration(days: 1) - const Duration(hours: 8)),
        ),
        // Active (no endTime)
        FrontingSession(
          id: 'active',
          startTime: base.subtract(const Duration(hours: 2)),
          sessionType: SessionType.sleep,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [frontingSessionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result = await _readPaginated(container, 20);
      expect(result.length, 1);
      expect(result.first.id, 'done');
    });

    test('different family keys produce independent providers', () async {
      final repo = _FakeRepo();
      repo.seed([
        for (int i = 0; i < 10; i++)
          _sleep(
            'id-$i',
            base.subtract(Duration(days: i + 1)),
            base.subtract(Duration(days: i + 1) - const Duration(hours: 8)),
          ),
      ]);

      final container = ProviderContainer(
        overrides: [frontingSessionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final result5 = await _readPaginated(container, 5);
      final result10 = await _readPaginated(container, 10);

      expect(result5.length, 5);
      expect(result10.length, 10);
    });
  });
}
