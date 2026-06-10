import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/sleep_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_recovery_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime(2026, 4, 30, 22),
  endTime: DateTime(2026, 5, 1, 6),
  sessionType: SessionType.sleep,
  quality: SleepQuality.good,
);

SleepStatsView _sleepStats({FrontingSession? session}) => SleepStatsView(
  totalEverCount: session == null ? 0 : 1,
  lastNight: session,
  avg7d: (count: session == null ? 0 : 1, avgDuration: session?.duration),
  avg7dPrior: (count: 0, avgDuration: null),
);

Widget _buildSubject({
  Stream<List<FrontingSession>>? history,
  Stream<FrontingSession?>? activeSleep,
  Future<SleepStatsView>? stats,
  int recoverableSleepCount = 0,
}) {
  final router = GoRouter(
    initialLocation: AppRoutePaths.sleep,
    routes: [
      GoRoute(
        path: AppRoutePaths.sleep,
        builder: (_, _) => const SleepScreen(showBackButton: false),
        routes: [
          GoRoute(
            path: 'session/:id',
            builder: (_, state) =>
                Scaffold(body: Text('detail-${state.pathParameters['id']}')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      activeSleepSessionProvider.overrideWith(
        (ref) => activeSleep ?? Stream.value(null),
      ),
      sleepHistoryProvider.overrideWith(
        (ref) => history ?? Stream.value([_sleepSession()]),
      ),
      sleepStatsProvider.overrideWith(
        (ref) => stats ?? Future.value(_sleepStats()),
      ),
      deletedSleepSessionCountProvider.overrideWith(
        (ref) => Future.value(recoverableSleepCount),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
    ),
  );
}

void _useCompactViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 320);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('tapping a sleep row opens session details', (tester) async {
    final session = _sleepSession();

    await tester.pumpWidget(
      _buildSubject(
        history: Stream.value([session]),
        stats: Future.value(_sleepStats(session: session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SleepSessionRow), findsOneWidget);

    await tester.tap(find.byType(SleepSessionRow));
    await tester.pumpAndSettle();

    expect(find.text('detail-sleep-1'), findsOneWidget);
  });

  testWidgets('loading state uses compact viewport without layout errors', (
    tester,
  ) async {
    _useCompactViewport(tester);
    final history = StreamController<List<FrontingSession>>();
    addTearDown(history.close);

    await tester.pumpWidget(_buildSubject(history: history.stream));
    await tester.pump();

    expect(find.byType(PrismLoadingState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state uses compact viewport without layout errors', (
    tester,
  ) async {
    _useCompactViewport(tester);

    await tester.pumpWidget(
      _buildSubject(
        history: Stream.value(const []),
        stats: Future.value(_sleepStats()),
      ),
    );
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(EmptyState));

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No sleep sessions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state uses compact viewport without layout errors', (
    tester,
  ) async {
    _useCompactViewport(tester);

    await tester.pumpWidget(
      _buildSubject(
        history: Stream<List<FrontingSession>>.error(
          Exception('sleep history failed'),
        ),
      ),
    );
    await tester.pump();
    await _pumpUntilFound(tester, find.text('Exception: sleep history failed'));

    expect(find.text('Exception: sleep history failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recovery banner appears when sleep sessions are recoverable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(
        history: Stream.value([_sleepSession()]),
        stats: Future.value(_sleepStats(session: _sleepSession())),
        recoverableSleepCount: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InfoBanner), findsOneWidget);
    expect(find.text('Missing sleep sessions?'), findsOneWidget);

    // Tapping the action opens the recovery sheet.
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepRecoverySheet), findsOneWidget);
  });

  testWidgets('recovery banner is absent when nothing is recoverable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(
        history: Stream.value([_sleepSession()]),
        stats: Future.value(_sleepStats(session: _sleepSession())),
        recoverableSleepCount: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InfoBanner), findsNothing);
  });

  testWidgets('dismissing the recovery banner hides it for the visit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(
        history: Stream.value([_sleepSession()]),
        stats: Future.value(_sleepStats(session: _sleepSession())),
        recoverableSleepCount: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InfoBanner), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(InfoBanner), findsNothing);
  });
}
