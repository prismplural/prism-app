import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
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

  testWidgets('keeps fronting-specific controls out of generic preferences', (
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
    expect(find.text('Accent Color'), findsNothing);
    expect(find.text('Fronting behavior'), findsNothing);
    expect(find.text('When adding a new front'), findsNothing);
    expect(find.text('When using quick front'), findsNothing);
  });
}
