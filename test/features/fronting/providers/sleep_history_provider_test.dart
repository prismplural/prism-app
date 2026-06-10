import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';

// ---------------------------------------------------------------------------
// Fake repo — a single broadcast stream that re-emits a sliced view of the
// seeded sessions whenever the limit changes. Matches Drift's reactive
// behavior closely enough to exercise the load-more flow.
// ---------------------------------------------------------------------------

class _FakeRepo implements FrontingSessionRepository {
  List<FrontingSession> _sessions = const [];

  void seed(List<FrontingSession> sessions) => _sessions = List.of(sessions);

  @override
  Stream<List<FrontingSession>> watchRecentSleepSessions({int limit = 20}) {
    final completed = _sessions.where((s) => s.isSleep && !s.isActive).toList();
    return Stream.value(completed.take(limit).toList());
  }

  // --- Stubs (unused by this test file) ---
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
  Future<List<FrontingSession>> getDeletedSleepSessions() async => const [];

  @override
  Future<void> restoreSleepSession(String id) async {}
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

FrontingSession _sleep(String id, DateTime start, DateTime end) =>
    FrontingSession(
      id: id,
      startTime: start,
      endTime: end,
      sessionType: SessionType.sleep,
    );

Future<List<FrontingSession>> _waitForCount(
  ProviderContainer container,
  int expected,
) async {
  for (var i = 0; i < 50; i++) {
    final value = container.read(sleepHistoryProvider);
    final data = value.value;
    if (data != null && data.length == expected) return data;
    final err = value.whenOrNull(error: (e, _) => e);
    if (err != null) throw err;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for sleep history to reach $expected sessions');
}

void main() {
  group('sleepHistoryProvider', () {
    test('loads the first page using the limit notifier default', () async {
      final repo = _FakeRepo();
      final base = DateTime(2026, 4, 30, 6);
      repo.seed([
        for (var i = 0; i < sleepHistoryPageSize + 5; i++)
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
      container.listen<AsyncValue<List<FrontingSession>>>(
        sleepHistoryProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final firstPage = await _waitForCount(container, sleepHistoryPageSize);
      expect(firstPage, hasLength(sleepHistoryPageSize));
    });

    test('loadMore extends the page in place', () async {
      final repo = _FakeRepo();
      final base = DateTime(2026, 4, 30, 6);
      repo.seed([
        for (var i = 0; i < sleepHistoryPageSize * 2; i++)
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
      container.listen<AsyncValue<List<FrontingSession>>>(
        sleepHistoryProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await _waitForCount(container, sleepHistoryPageSize);
      container.read(sleepHistoryLimitProvider.notifier).loadMore();
      final secondPage = await _waitForCount(
        container,
        sleepHistoryPageSize * 2,
      );
      expect(secondPage, hasLength(sleepHistoryPageSize * 2));
    });

    test(
      'load-more never emits a bare loading state after first page settles',
      () async {
        // Guards against the limit-family-swap that collapsed the list
        // mid-scroll and snapped it back to top.
        final repo = _FakeRepo();
        final base = DateTime(2026, 4, 30, 6);
        repo.seed([
          for (var i = 0; i < sleepHistoryPageSize * 3 + 5; i++)
            _sleep(
              'id-$i',
              base.subtract(Duration(days: i + 1)),
              base.subtract(Duration(days: i + 1) - const Duration(hours: 8)),
            ),
        ]);

        final container = ProviderContainer(
          overrides: [
            frontingSessionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        // Capture every state from initial mount onward. Subscribing here
        // keeps the autoDispose provider alive across `_waitForCount` polls.
        final transitions = <AsyncValue<List<FrontingSession>>>[];
        final sub = container.listen<AsyncValue<List<FrontingSession>>>(
          sleepHistoryProvider,
          (_, next) => transitions.add(next),
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await _waitForCount(container, sleepHistoryPageSize);
        // Drop the initial AsyncLoading from before the first page settled —
        // first-mount loading is expected and not the flicker we're guarding
        // against.
        transitions.clear();

        for (var page = 2; page <= 3; page++) {
          container.read(sleepHistoryLimitProvider.notifier).loadMore();
          await _waitForCount(container, sleepHistoryPageSize * page);
        }

        expect(
          transitions,
          isNotEmpty,
          reason: 'expected at least one provider update during pagination',
        );
        for (final state in transitions) {
          expect(
            state.hasValue,
            isTrue,
            reason:
                'every state after the first settled page must carry a value '
                '(bare AsyncLoading collapses the list and snaps scroll to top)',
          );
        }
      },
    );
  });
}
