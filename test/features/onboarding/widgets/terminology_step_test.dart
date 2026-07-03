import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/terminology_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: TerminologyStep()),
      ),
    );
  }

  testWidgets('renders terminology choices without appearance controls', (
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

    expect(find.text('Member terminology'), findsOneWidget);
    expect(find.text('System terminology'), findsOneWidget);
    expect(find.text('Fronting terminology'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Headmates'), findsOneWidget);
    expect(find.text('member'), findsOneWidget);
    expect(find.text('headmate'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Collective'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Constellation'), findsOneWidget);
    expect(find.text('Collectives'), findsNothing);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Out Members'), findsOneWidget);
    expect(find.text('Accent Color'), findsNothing);
    expect(find.text('Theme'), findsNothing);
  });

  testWidgets('updates onboarding terminology state', (tester) async {
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

    await tester.tap(find.text('Parts'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).selectedTerminology,
      SystemTerminology.parts,
    );
  });

  testWidgets('updates onboarding system terminology state', (tester) async {
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

    await tester.ensureVisible(find.text('Custom').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Collective');
    await tester.enterText(fields.at(1), 'Collectives');

    final state = container.read(onboardingProvider);
    expect(state.useCustomSystemTerminology, isTrue);
    expect(state.selectedSystemTermPreset, isNull);
    expect(state.customSystemTermSingular, 'Collective');
    expect(state.customSystemTermPlural, 'Collectives');
  });

  testWidgets('selects a system terminology preset', (tester) async {
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

    await tester.tap(find.text('Collective'));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.useCustomSystemTerminology, isFalse);
    expect(state.selectedSystemTermPreset, SystemTermPreset.collective);
  });

  testWidgets('updates onboarding fronting terminology state', (tester) async {
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

    await tester.ensureVisible(find.text('Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).pendingFrontingTerms,
      const FrontingTerms.preset(FrontingTermPreset.out),
    );

    await tester.tap(find.text('Fronting'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).pendingFrontingTerms,
      FrontingTerms.unset,
    );
  });
}
