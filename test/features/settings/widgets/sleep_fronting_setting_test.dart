import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/widgets/sleep_fronting_setting.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  testWidgets(
    'saves the shared preference and responds to repository changes',
    (tester) async {
      final prefs = FakeAppPreferenceRepository();
      addTearDown(prefs.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appPreferenceRepositoryProvider.overrideWithValue(prefs)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(body: SleepFrontingSetting()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PrismSwitchRow>(find.byType(PrismSwitchRow)).value,
        isFalse,
      );
      await tester.tap(find.text('Keep current fronters during sleep'));
      await tester.pumpAndSettle();
      expect(await prefs.get(keepFrontingDuringSleepPreference), isTrue);
      await prefs.set(keepFrontingDuringSleepPreference, false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PrismSwitchRow>(find.byType(PrismSwitchRow)).value,
        isFalse,
      );
    },
  );
}
