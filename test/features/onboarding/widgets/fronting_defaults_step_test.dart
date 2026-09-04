import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/fronting_defaults_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: FrontingDefaultsStep()),
      ),
    );
  }

  testWidgets('renders home view and fronting behavior controls', (
    tester,
  ) async {
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

    expect(find.text('Home view'), findsOneWidget);
    expect(find.text('Home Display'), findsOneWidget);
    expect(find.text('Combined'), findsOneWidget);
    expect(find.text('Individual'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Log Front'), findsOneWidget);
    expect(find.text('Starting Activity'), findsOneWidget);
    expect(find.text('Log Front'), findsOneWidget);
    expect(find.text('Quick Front'), findsOneWidget);
  });

  testWidgets('updates onboarding state independently', (tester) async {
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

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(
      container.read(onboardingProvider).frontingListViewMode,
      FrontingListViewMode.timeline,
    );
    expect(container.read(onboardingProvider).addFrontDefaultBehavior, isNull);

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
  });

  testWidgets('uses persisted settings as initial selections', (tester) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository()
            ..settings = const SystemSettings(
              frontingListViewMode: FrontingListViewMode.perMemberRows,
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
      find.text('Shows each fronting session on its own row.'),
      findsOneWidget,
    );
    expect(
      find.text('Ends the current activity, then starts the selected person.'),
      findsNWidgets(2),
    );
  });
}
