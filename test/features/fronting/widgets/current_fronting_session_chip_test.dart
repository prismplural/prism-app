import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

void main() {
  testWidgets('shows current fronting period and opens session detail', (
    tester,
  ) async {
    final member = Member(
      id: 'member-1',
      name: 'Alice',
      createdAt: DateTime(2024),
    );
    final period = FrontingPeriod(
      start: DateTime.now().subtract(const Duration(hours: 2)),
      end: DateTime.now(),
      activeMembers: const ['member-1'],
      briefVisitors: const [],
      sessionIds: const ['session-1'],
      alwaysPresentMembers: const [],
      isOpenEnded: true,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: CurrentFrontingSessionChip()),
        ),
        GoRoute(
          path: '/session/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Session ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          derivedPeriodsProvider.overrideWith(
            (ref) => AsyncValue.data([period]),
          ),
          membersByIdsProvider.overrideWith(
            (ref, _) => Stream.value({'member-1': member}),
          ),
          allMemberListProvider.overrideWith((ref) => Stream.value([member])),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Session session-1'), findsOneWidget);
  });

  testWidgets('uses true open period start for cross-midnight current front', (
    tester,
  ) async {
    final member = Member(
      id: 'member-1',
      name: 'Alice',
      createdAt: DateTime(2024),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startedYesterday = today.subtract(const Duration(hours: 2));
    final period = FrontingPeriod(
      start: startedYesterday,
      end: now,
      activeMembers: const ['member-1'],
      briefVisitors: const [],
      sessionIds: const ['session-1'],
      alwaysPresentMembers: const [],
      isOpenEnded: true,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: CurrentFrontingSessionChip()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          derivedPeriodsProvider.overrideWith(
            (ref) => AsyncValue.data([period]),
          ),
          membersByIdsProvider.overrideWith(
            (ref, _) => Stream.value({'member-1': member}),
          ),
          allMemberListProvider.overrideWith((ref) => Stream.value([member])),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.pump();

    final durationText = tester.widget<FrontingDurationText>(
      find.byType(FrontingDurationText),
    );
    expect(durationText.startTime, startedYesterday);

    final chipContext = tester.element(find.byType(CurrentFrontingSessionChip));
    final expectedStartLabel = chipContext.formatDateTime(startedYesterday);
    expect(expectedStartLabel, contains('22:00'));
    expect(find.textContaining(expectedStartLabel), findsOneWidget);
    expect(find.textContaining('00:00 – ongoing'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
