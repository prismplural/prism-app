import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
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
          appPreferenceRepositoryProvider.overrideWithValue(
            FakeAppPreferenceRepository(),
          ),
          systemSettingsRepositoryProvider.overrideWithValue(
            FakeSystemSettingsRepository(),
          ),
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

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();

    expect(switches, hasLength(2));
    expect(
      switches.where((switchWidget) => switchWidget.onChanged == null),
      hasLength(2),
    );
  });

  testWidgets('shows an error when accessibility preferences fail to load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(
            FakeAppPreferenceRepository(),
          ),
          systemSettingsRepositoryProvider.overrideWithValue(
            FakeSystemSettingsRepository(),
          ),
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
    final settings = FakeSystemSettingsRepository();
    addTearDown(prefs.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(prefs),
          systemSettingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const _AccessibilitySettingsTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use centered sheets'));
    await tester.pump();

    expect(await prefs.get(forceCenteredSheetsPreference), true);
  });

  testWidgets('persists letter spacing from the typography slider', (
    tester,
  ) async {
    final prefs = FakeAppPreferenceRepository();
    final settings = FakeSystemSettingsRepository()
      ..settings = const SystemSettings(fontFamily: FontFamily.openDyslexic);
    addTearDown(prefs.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(prefs),
          systemSettingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const _AccessibilitySettingsTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Typography'), findsOneWidget);
    expect(find.text('Letter spacing'), findsOneWidget);

    final fontSizeSlider = tester.widget<Slider>(find.byType(Slider).first);
    expect(fontSizeSlider.min, 0.7);

    final letterSpacingSlider = tester.widget<Slider>(
      find.byType(Slider).at(1),
    );
    letterSpacingSlider.onChanged!(0.4);
    await tester.pump();

    expect(await prefs.get(typographyLetterSpacingPreference), 0.4);
  });

  testWidgets('typography reset preserves display font preference', (
    tester,
  ) async {
    final prefs = FakeAppPreferenceRepository();
    final settings = FakeSystemSettingsRepository()
      ..settings = const SystemSettings(
        fontFamily: FontFamily.openDyslexic,
        displayFontInAppBar: false,
      );
    addTearDown(prefs.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(prefs),
          systemSettingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const _AccessibilitySettingsTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset to default'));
    await tester.pump();

    expect(settings.settings.fontFamily, FontFamily.system);
    expect(settings.settings.fontScale, 1.0);
    expect(settings.settings.displayFontInAppBar, isFalse);
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
