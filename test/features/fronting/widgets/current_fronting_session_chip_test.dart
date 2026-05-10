import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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
}
