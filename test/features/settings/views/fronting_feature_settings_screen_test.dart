import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/views/fronting_feature_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject(
    FakeSystemSettingsRepository repo, {
    FakeAppPreferenceRepository? appPrefs,
  }) {
    final prefs = appPrefs ?? FakeAppPreferenceRepository();
    addTearDown(prefs.close);
    return ProviderScope(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(repo),
        appPreferenceRepositoryProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: FrontingFeatureSettingsScreen(),
      ),
    );
  }

  group('FrontingFeatureSettingsScreen — session display & front behavior', () {
    testWidgets('renders the section header and four preference rows', (
      tester,
    ) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      expect(find.text('Display & Behavior'), findsOneWidget);
      expect(find.text('Session list view'), findsOneWidget);
      expect(find.text('Default Start Behavior'), findsOneWidget);
      expect(find.text('Quick Action Behavior'), findsOneWidget);
      expect(find.text('Long-running fronts'), findsOneWidget);
    });

    testWidgets('subtitles reflect the saved enum values', (tester) async {
      final repo = FakeSystemSettingsRepository()
        ..settings = const SystemSettings(
          frontingListViewMode: FrontingListViewMode.perMemberRows,
          addFrontDefaultBehavior: FrontStartBehavior.replace,
          quickFrontDefaultBehavior: FrontStartBehavior.replace,
        );

      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      // Each row's subtitle is the current option label. The default
      // terminology is 'headmates', so the {term} placeholder resolves to
      // 'headmate' here.
      expect(find.text('Per-headmate rows'), findsOneWidget);
      // Both the add-front row and the quick-front row read 'Replace current
      // fronters', so we expect two matches.
      expect(find.text('Replace current fronters'), findsNWidgets(2));
    });

    testWidgets('labels respond to the fronting terminology preference', (
      tester,
    ) async {
      final repo = FakeSystemSettingsRepository();
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          const FrontingTerms.preset(FrontingTermPreset.out),
        );

      await tester.pumpWidget(buildSubject(repo, appPrefs: appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('Out'), findsOneWidget);
      expect(find.text('Display & Behavior'), findsOneWidget);
      expect(find.text('Default Start Behavior'), findsOneWidget);
      expect(find.text('Quick Action Behavior'), findsOneWidget);
      expect(find.text('Long-running out sessions'), findsOneWidget);
    });

    testWidgets('tapping list-view-mode picker writes the selected value', (
      tester,
    ) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Session list view'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Combines overlapping fronting sessions into shared periods.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Shows each profile on a separate row.'),
        findsOneWidget,
      );
      expect(find.text('Shows activity over time.'), findsOneWidget);

      // Pick "Timeline" — appears in the dialog as a RadioListTile title.
      await tester.tap(find.text('Timeline').last);
      await tester.pumpAndSettle();

      expect(repo.settings.frontingListViewMode, FrontingListViewMode.timeline);
    });

    testWidgets('tapping add-front-behavior picker writes the selected value', (
      tester,
    ) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Default Start Behavior'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Replace current fronters').last);
      await tester.pumpAndSettle();

      expect(repo.settings.addFrontDefaultBehavior, FrontStartBehavior.replace);
      // Quick-front behavior is independent and must NOT have been touched.
      expect(
        repo.settings.quickFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    testWidgets(
      'tapping quick-front-behavior picker writes the selected value',
      (tester) async {
        final repo = FakeSystemSettingsRepository();
        await tester.pumpWidget(buildSubject(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Quick Action Behavior'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Replace current fronters').last);
        await tester.pumpAndSettle();

        expect(
          repo.settings.quickFrontDefaultBehavior,
          FrontStartBehavior.replace,
        );
        expect(
          repo.settings.addFrontDefaultBehavior,
          FrontStartBehavior.additive,
        );
      },
    );

    testWidgets('toggling auto-promote writes the saved value', (tester) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      expect(repo.settings.autoPromoteLongFrontingSessions, isFalse);
    });
  });
}
