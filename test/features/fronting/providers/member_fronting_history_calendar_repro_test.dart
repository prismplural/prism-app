// Deterministic repro harness for the member-history calendar jump crash.
//
// The reported iOS flow is:
//
//   Member page → Fronting sessions → calendar → choose a far-back day.
//
// A far-back date repeatedly calls `loadMore()`, rebuilding history from every
// overlapping session and expanding the long session across its calendar days.
//
// Run the default, CI-safe fixture on macOS or iOS Simulator:
//
// ```sh
// flutter test test/features/fronting/providers/ \
//   member_fronting_history_calendar_repro_test.dart -r expanded
// ```
//
// Run the larger, report-shaped fixture (same test; no source changes):
//
// ```sh
// flutter test test/features/fronting/providers/ \
//   member_fronting_history_calendar_repro_test.dart -r expanded \
//   --dart-define=PRISM_MEMBER_HISTORY_REPRO_LARGE=true
// ```
//
// The integration test reuses this fixture on macOS or iOS Simulator.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/utils/period_day_grouping.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

import '../../../support/member_fronting_history_calendar_repro_fixture.dart';

const _runLargeFixture = bool.fromEnvironment(
  'PRISM_MEMBER_HISTORY_REPRO_LARGE',
);

Future<MemberFrontingHistoryData> _waitForHistory(
  ProviderContainer container,
  String memberId, {
  required int minimumSessionCount,
}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final value = container.read(memberFrontingHistoryProvider(memberId));
    final error = value.whenOrNull(error: (error, _) => error);
    if (error != null) throw error;
    final data = value.whenOrNull(data: (data) => data);
    if (data != null && data.targetSessions.length >= minimumSessionCount) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out loading $minimumSessionCount target sessions');
}

void main() {
  test(
    'REPRO: calendar jump repeatedly expands a long member history',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await seedMemberHistoryCalendarReproFixture(
        db,
        large: _runLargeFixture,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          allMembersProvider.overrideWith(
            (ref) => Stream.value([fixture.member]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<MemberFrontingHistoryData>>(
        memberFrontingHistoryProvider(fixture.member.id),
        (_, _) {},
        fireImmediately: true,
      );

      // Simulate the calendar's repeated pagination for a far-back day.
      var expectedLoaded = memberFrontingHistoryPageSize;
      var pages = 0;
      var maximumGroups = 0;
      var maximumPeriods = 0;
      final total = Stopwatch()..start();

      while (true) {
        final pageTimer = Stopwatch()..start();
        final history = await _waitForHistory(
          container,
          fixture.member.id,
          minimumSessionCount: expectedLoaded < fixture.sessionCount
              ? expectedLoaded
              : fixture.sessionCount,
        );
        final groups = groupHistoryByDay(
          periods: history.periods,
          sleepSessions: const <FrontingSession>[],
        );
        pageTimer.stop();
        pages++;
        maximumGroups = maximumGroups < groups.length
            ? groups.length
            : maximumGroups;
        maximumPeriods = maximumPeriods < history.periods.length
            ? history.periods.length
            : maximumPeriods;

        // ignore: avoid_print
        print(
          '[member-history-calendar-repro] page=$pages '
          'limit=$expectedLoaded loaded=${history.targetSessions.length} '
          'periods=${history.periods.length} days=${groups.length} '
          'elapsed=${pageTimer.elapsedMilliseconds}ms',
        );

        final oldest = history.oldestLoadedStart;
        if (oldest == null || !oldest.isAfter(fixture.targetDay)) break;
        expect(
          history.hasMore,
          isTrue,
          reason:
              'fixture must contain enough newer rows to require another '
              'calendar-driven history page',
        );
        container
            .read(
              memberFrontingHistoryLimitProvider(fixture.member.id).notifier,
            )
            .loadMore();
        expectedLoaded += memberFrontingHistoryPageSize;
      }
      total.stop();

      // The long session must expand beyond the initial page.
      expect(pages, greaterThan(1));
      expect(maximumGroups, greaterThan(fixture.longSessionDays ~/ 2));
      expect(maximumPeriods, greaterThan(0));
      // ignore: avoid_print
      print(
        '[member-history-calendar-repro] complete '
        'fixture=${_runLargeFixture ? 'large' : 'default'} '
        'rows=${fixture.sessionCount} longDays=${fixture.longSessionDays} '
        'target=${fixture.targetDay.toIso8601String().substring(0, 10)} '
        'pages=$pages maxPeriods=$maximumPeriods maxDays=$maximumGroups '
        'total=${total.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
