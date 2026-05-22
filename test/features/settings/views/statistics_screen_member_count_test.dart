import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/statistics_providers.dart';
import 'package:prism_plurality/features/settings/views/statistics_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  final members = [
    Member(id: 'm1', name: 'Alice', createdAt: DateTime.utc(2024)),
    Member(id: 'm2', name: 'Bob', createdAt: DateTime.utc(2024, 1, 2)),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        memberCountStatProvider.overrideWith((ref) async => members.length),
        allMembersStatProvider.overrideWith((ref) async => members),
        sessionCountStatProvider.overrideWith((ref) async => 0),
        allSessionsStatProvider.overrideWith((ref) async => const []),
        allConversationsCountProvider.overrideWith((ref) async => 0),
        allPollsCountProvider.overrideWith((ref) async => 0),
        topFrontersProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: StatisticsScreen(),
      ),
    );
  }

  group('StatisticsScreen member count', () {
    testWidgets('shows total member count by default', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Total headmates'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2 active, 0 inactive'), findsOneWidget);
    });

    testWidgets('hides total member count when local preference is enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hide_total_member_count': true,
      });

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Total headmates'), findsNothing);
      expect(find.text('2 active, 0 inactive'), findsNothing);
    });
  });
}
