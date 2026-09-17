// Device-capable wrapper for the deterministic member-history calendar repro.
//
// Run on macOS:
//   flutter test integration_test/member_fronting_history_calendar_repro_test.dart \
//     -d macos -r expanded
//
// Run on iOS Simulator (boot a simulator first):
//   flutter test integration_test/member_fronting_history_calendar_repro_test.dart \
//     -d <simulator-id> -r expanded
//
// Use --dart-define=PRISM_MEMBER_HISTORY_REPRO_LARGE=true for 1,200 dense rows
// and 41 calendar-pagination cycles. The default fixture is CI-safe.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

import '../test/support/member_fronting_history_calendar_repro_fixture.dart';

const _runLargeFixture = bool.fromEnvironment(
  'PRISM_MEMBER_HISTORY_REPRO_LARGE',
);

Future<MemberFrontingHistoryData> _waitForHistory(
  ProviderContainer container,
  String memberId, {
  required int minimumSessionCount,
}) async {
  for (var attempt = 0; attempt < 300; attempt++) {
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'REPRO: member calendar jump builds thousands of history day groups',
    (tester) async {
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
        memberFrontingHistoryProvider(memberHistoryCalendarReproMemberId),
        (_, _) {},
        fireImmediately: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: NavBarInset(
                bottomInset: 0,
                child: CustomScrollView(
                  slivers: [
                    MemberFrontingHistoryList(
                      memberId: memberHistoryCalendarReproMemberId,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      var expectedLoaded = memberFrontingHistoryPageSize;
      var pages = 0;
      final total = Stopwatch()..start();
      while (true) {
        final history = await _waitForHistory(
          container,
          fixture.member.id,
          minimumSessionCount: expectedLoaded < fixture.sessionCount
              ? expectedLoaded
              : fixture.sessionCount,
        );
        await tester.pump();
        pages++;
        final oldest = history.oldestLoadedStart;
        if (oldest == null || !oldest.isAfter(fixture.targetDay)) break;
        expect(history.hasMore, isTrue);
        container
            .read(
              memberFrontingHistoryLimitProvider(fixture.member.id).notifier,
            )
            .loadMore();
        expectedLoaded += memberFrontingHistoryPageSize;
      }
      total.stop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final dateChips = find.byType(DateChip);
      // A visible date chip confirms the platform frame completed.
      expect(dateChips, findsWidgets);
      expect(pages, greaterThan(1));
      // ignore: avoid_print
      print(
        '[member-history-calendar-repro-device] '
        'fixture=${_runLargeFixture ? 'large' : 'default'} '
        'rows=${fixture.sessionCount} pages=$pages '
        'visibleDateChips=${dateChips.evaluate().length} '
        'elapsed=${total.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
