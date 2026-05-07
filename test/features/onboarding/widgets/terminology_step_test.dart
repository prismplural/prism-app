import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
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

    expect(find.text('Terminology'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Headmates'), findsOneWidget);
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
}
