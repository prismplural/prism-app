import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/views/fronting_feature_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject(FakeSystemSettingsRepository repo) {
    return ProviderScope(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: FrontingFeatureSettingsScreen(),
      ),
    );
  }

  group('FrontingFeatureSettingsScreen — session display & front behavior', () {
    testWidgets('renders the section header and three preference rows',
        (tester) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      expect(find.text('Session display & front behavior'), findsOneWidget);
      expect(find.text('Session list view'), findsOneWidget);
      expect(find.text('When adding a new front'), findsOneWidget);
      expect(find.text('When using quick front'), findsOneWidget);
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

      // Each row's subtitle is the current option label.
      expect(find.text('Per-member rows'), findsOneWidget);
      // Both the add-front row and the quick-front row read 'Replace current
      // fronters', so we expect two matches.
      expect(find.text('Replace current fronters'), findsNWidgets(2));
    });

    testWidgets('tapping list-view-mode picker writes the selected value',
        (tester) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Session list view'));
      await tester.pumpAndSettle();

      // Pick "Timeline" — appears in the dialog as a RadioListTile title.
      await tester.tap(find.text('Timeline').last);
      await tester.pumpAndSettle();

      expect(
        repo.settings.frontingListViewMode,
        FrontingListViewMode.timeline,
      );
    });

    testWidgets('tapping add-front-behavior picker writes the selected value',
        (tester) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('When adding a new front'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Replace current fronters').last);
      await tester.pumpAndSettle();

      expect(
        repo.settings.addFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
      // Quick-front behavior is independent and must NOT have been touched.
      expect(
        repo.settings.quickFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    testWidgets('tapping quick-front-behavior picker writes the selected value',
        (tester) async {
      final repo = FakeSystemSettingsRepository();
      await tester.pumpWidget(buildSubject(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('When using quick front'));
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
    });
  });
}
