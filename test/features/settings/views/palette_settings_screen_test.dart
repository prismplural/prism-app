import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/palette_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject({
    required TargetPlatform platform,
    SystemSettings settings = const SystemSettings(),
  }) {
    return ProviderScope(
      overrides: [
        targetPlatformProvider.overrideWithValue(platform),
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PaletteSettingsScreen(),
      ),
    );
  }

  group('PaletteSettingsScreen', () {
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
  });
}
