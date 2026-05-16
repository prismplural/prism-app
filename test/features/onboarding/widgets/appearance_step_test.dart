import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/appearance_step.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: AppearanceStep()),
      ),
    );
  }

  testWidgets('renders appearance controls without terminology choices', (
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

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Prism'), findsOneWidget);
    expect(find.text('OLED'), findsOneWidget);
    expect(find.text('Palette'), findsOneWidget);
    expect(find.text('Corner style'), findsOneWidget);
    expect(find.text('Accent Color'), findsOneWidget);
    expect(find.text('Terminology'), findsNothing);
  });

  testWidgets('updates onboarding appearance state independently', (
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

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OLED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.themeBrightness, ThemeBrightness.dark);
    expect(state.themeStyle, ThemeStyle.oled);
    expect(state.cornerStyle, CornerStyle.angular);
  });

  testWidgets('uses persisted settings as initial appearance selections', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository()
            ..settings = const SystemSettings(
              themeBrightness: ThemeBrightness.dark,
              themeStyle: ThemeStyle.oled,
              cornerStyle: CornerStyle.angular,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(container.read(onboardingProvider).themeBrightness, isNull);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Corner style'), findsOneWidget);
  });

  testWidgets('shows Palette off Android without normalizing the style', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository()
            ..settings = const SystemSettings(
              themeStyle: ThemeStyle.materialYou,
            ),
        ),
        targetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(find.text('Palette'), findsOneWidget);
    expect(container.read(onboardingProvider).themeStyle, isNull);
  });

  testWidgets('selects Palette off Android', (tester) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository(),
        ),
        targetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Palette'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).themeStyle,
      ThemeStyle.materialYou,
    );
  });

  testWidgets('shows Palette on Android', (tester) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(
          FakeSystemSettingsRepository()
            ..settings = const SystemSettings(
              themeStyle: ThemeStyle.materialYou,
            ),
        ),
        targetPlatformProvider.overrideWithValue(TargetPlatform.android),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(find.text('Palette'), findsOneWidget);
    expect(container.read(onboardingProvider).themeStyle, isNull);
  });

  test('onboarding shell pill derives content color from the filled color', () {
    final source = File(
      'lib/features/onboarding/views/onboarding_screen.dart',
    ).readAsStringSync();

    expect(source, contains('highContrastForeground(renderedFillColor)'));
    expect(source, contains('foreground.withValues(alpha: 0.82)'));
    expect(source, isNot(contains('PrismSpinner(color: AppColors.warmBlack')));
    expect(source, isNot(contains('color: AppColors.warmBlack')));
  });
}
