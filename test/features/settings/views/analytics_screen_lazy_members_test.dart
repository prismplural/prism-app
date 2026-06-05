// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/analytics_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets('member details only subscribe visible rows', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime(2026, 6, 1, 12);
    final members = {
      for (var i = 0; i < 80; i++)
        'member-$i': Member(
          id: 'member-$i',
          name: 'Member $i',
          createdAt: now,
          isActive: true,
        ),
    };
    final stats = [
      for (var i = 0; i < members.length; i++)
        MemberAnalytics(
          memberId: 'member-$i',
          totalTime: Duration(minutes: members.length - i),
          percentageOfTotal: 100 / members.length,
          sessionCount: 1,
          averageDuration: const Duration(minutes: 30),
          medianDuration: const Duration(minutes: 30),
          shortestSession: const Duration(minutes: 30),
          longestSession: const Duration(minutes: 30),
          timeOfDayBreakdown: const {},
        ),
    ];
    final analytics = FrontingAnalytics(
      rangeStart: now.subtract(const Duration(days: 30)),
      rangeEnd: now,
      totalTrackedTime: const Duration(hours: 40),
      totalGapTime: Duration.zero,
      totalSessions: stats.length,
      uniqueFronters: stats.length,
      switchesPerDay: 2,
      memberStats: stats,
      medianSession: const Duration(minutes: 30),
    );
    final watchedDetailIds = <String>{};

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          frontingAnalyticsProvider.overrideWith((ref) async => analytics),
          previousPeriodAnalyticsProvider.overrideWith((ref) async => null),
          analyticsInsightsProvider.overrideWith((ref) async => const []),
          membersByIdsProvider.overrideWith(
            (ref, idsKey) => Stream.value(members),
          ),
          activeMemberByIdProvider.overrideWith((ref, id) {
            watchedDetailIds.add(id);
            return AsyncValue.data(members[id]);
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: AnalyticsScreen(showBackButton: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(watchedDetailIds.length, lessThan(stats.length));
    final initiallyWatched = watchedDetailIds.length;

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(watchedDetailIds.length, greaterThan(initiallyWatched));
    expect(watchedDetailIds.length, lessThan(stats.length));
  });
}
