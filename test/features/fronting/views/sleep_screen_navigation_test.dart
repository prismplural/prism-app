import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/sleep_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime(2026, 4, 30, 22),
  endTime: DateTime(2026, 5, 1, 6),
  sessionType: SessionType.sleep,
  quality: SleepQuality.good,
);

Widget _buildSubject(FrontingSession session) {
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
      activeSleepSessionProvider.overrideWith((ref) => Stream.value(null)),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value([session]),
      ),
      sleepStatsProvider.overrideWith(
        (ref) => Future.value(
          SleepStatsView(
            totalEverCount: 1,
            lastNight: session,
            avg7d: (count: 1, avgDuration: session.duration),
            avg7dPrior: (count: 0, avgDuration: null),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('tapping a sleep row opens session details', (tester) async {
    final session = _sleepSession();

    await tester.pumpWidget(_buildSubject(session));
    await tester.pumpAndSettle();

    expect(find.byType(SleepSessionRow), findsOneWidget);

    await tester.tap(find.byType(SleepSessionRow));
    await tester.pumpAndSettle();

    expect(find.text('detail-sleep-1'), findsOneWidget);
  });
}
