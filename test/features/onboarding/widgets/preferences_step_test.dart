import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/preferences_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: PreferencesStep()),
      ),
    );
  }

  testWidgets(
    'renders fronting behavior controls and updates onboarding state',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          systemSettingsRepositoryProvider.overrideWithValue(
            FakeSystemSettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildSubject(container));
      await tester.pumpAndSettle();

      expect(find.text('Fronting behavior'), findsOneWidget);
      expect(find.text('When adding a new front'), findsOneWidget);
      expect(find.text('When using quick front'), findsOneWidget);

      await tester.tap(find.text('Replace').first);
      await tester.pumpAndSettle();

      expect(
        container.read(onboardingProvider).addFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
      expect(
        container.read(onboardingProvider).quickFrontDefaultBehavior,
        isNull,
      );

      await tester.tap(find.text('Replace').last);
      await tester.pumpAndSettle();

      expect(
        container.read(onboardingProvider).quickFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
    },
  );

  testWidgets('uses persisted fronting behavior as the initial selection', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository()
            ..settings = const SystemSettings(
              addFrontDefaultBehavior: FrontStartBehavior.replace,
              quickFrontDefaultBehavior: FrontStartBehavior.replace,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(
      find.text('Ends the current front first, then starts the new member.'),
      findsNWidgets(2),
    );
  });
}
