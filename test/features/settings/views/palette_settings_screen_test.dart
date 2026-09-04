import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/palette_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fronting_term_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject({
    required TargetPlatform platform,
    SystemSettings settings = const SystemSettings(),
    FrontingTerms? frontingTerms,
  }) {
    return ProviderScope(
      overrides: [
        targetPlatformProvider.overrideWithValue(platform),
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
        if (frontingTerms != null)
          frontingTermsSettingProvider.overrideWithValue(frontingTerms),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PaletteSettingsScreen(),
      ),
    );
  }

  group('PaletteSettingsScreen', () {
    test('palette previews keep neutral custom colors monochrome', () {
      for (final seed in const [
        Color(0xFFFFFFFF),
        Color(0xFF808080),
        Color(0xFF000000),
      ]) {
        for (final mood in PaletteMood.values) {
          final preview = PalettePreview.from(
            seedColor: seed,
            mood: mood,
            contrast: PaletteContrast.standard,
            brightness: Brightness.light,
          );

          for (final dot in preview.dots) {
            expect(
              _hslSaturation(dot),
              lessThan(0.01),
              reason:
                  'preview dots should stay monochrome for ${seed.toARGB32().toRadixString(16)} in ${mood.name}',
            );
          }
        }
      }
    });

    test('custom palette preview matches applied app theme colors', () {
      const seed = Color(0xFF16A34A);
      const contrast = PaletteContrast.high;
      final preview = PalettePreview.from(
        seedColor: seed,
        mood: PaletteMood.vibrant,
        contrast: contrast,
        brightness: Brightness.light,
      );
      final theme = AppTheme.materialYouLight(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#16A34A',
        paletteMood: PaletteMood.vibrant,
        paletteContrast: contrast,
      );

      expect(preview.scheme.primary, theme.colorScheme.primary);
      expect(
        preview.scheme.surfaceContainerHighest,
        theme.colorScheme.surfaceContainerHighest,
      );
    });

    testWidgets('hides source section when device colors are unsupported', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.iOS,
          settings: const SystemSettings(paletteSource: PaletteSource.device),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Source'), findsNothing);
      expect(find.text('Device colors'), findsNothing);
      expect(find.text('Custom color'), findsNothing);
      expect(find.text('Color'), findsOneWidget);
    });

    testWidgets('shows source section when device colors are supported', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Device colors'), findsOneWidget);
      expect(find.text('Custom color'), findsOneWidget);
    });

    testWidgets('long custom activity labels do not overflow the preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final customBundle = FrontingTermBundle.tryDecode({
        ...testFrontingTermBundle.toJson(),
        'activeSectionLabel':
            'Members currently participating in this very long activity',
      })!;

      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.iOS,
          frontingTerms: FrontingTerms.custom(customBundle),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

double _hslSaturation(Color color) => HSLColor.fromColor(color).saturation;
