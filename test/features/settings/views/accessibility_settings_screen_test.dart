import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/views/accessibility_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  testWidgets('disables switches while accessibility preferences load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dimBackgroundBehindSheetsProvider.overrideWith(
            _LoadingDimBackgroundNotifier.new,
          ),
          forceCenteredSheetsProvider.overrideWith(
            _LoadingForceCenteredNotifier.new,
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AccessibilitySettingsScreen(),
        ),
      ),
    );

    final switches = tester.widgetList<Switch>(find.byType(Switch));

    expect(switches, hasLength(2));
    expect(
      switches.map((switchWidget) => switchWidget.onChanged),
      everyElement(isNull),
    );
  });

  testWidgets('shows an error when accessibility preferences fail to load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dimBackgroundBehindSheetsProvider.overrideWith(
            _ErrorDimBackgroundNotifier.new,
          ),
          forceCenteredSheetsProvider.overrideWith(
            _ErrorForceCenteredNotifier.new,
          ),
        ],
        child: const _AccessibilitySettingsTestApp(),
      ),
    );
    await tester.pump();

    expect(
      find.text('Could not load accessibility preferences.'),
      findsNWidgets(2),
    );
  });

  testWidgets('persists force-centered preference from the switch row', (
    tester,
  ) async {
    final prefs = FakeAppPreferenceRepository();
    addTearDown(prefs.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPreferenceRepositoryProvider.overrideWithValue(prefs)],
        child: const _AccessibilitySettingsTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use centered sheets'));
    await tester.pump();

    expect(await prefs.get(forceCenteredSheetsPreference), true);
  });
}

class _AccessibilitySettingsTestApp extends StatelessWidget {
  const _AccessibilitySettingsTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AccessibilitySettingsScreen(),
    );
  }
}

class _LoadingDimBackgroundNotifier extends DimBackgroundBehindSheetsNotifier {
  @override
  Future<bool> build() => Completer<bool>().future;
}

class _LoadingForceCenteredNotifier extends ForceCenteredSheetsNotifier {
  @override
  Future<bool> build() => Completer<bool>().future;
}

class _ErrorDimBackgroundNotifier extends DimBackgroundBehindSheetsNotifier {
  @override
  Future<bool> build() async => throw StateError('boom');
}

class _ErrorForceCenteredNotifier extends ForceCenteredSheetsNotifier {
  @override
  Future<bool> build() async => throw StateError('boom');
}
