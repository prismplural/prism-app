import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/services.dart';
import 'package:prism_plurality/domain/models/system_settings.dart'
    show PaletteContrast, PaletteMood, PaletteSource;
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';

var _prismGoldenFontsLoaded = false;

Future<void> loadPrismGoldenFonts() async {
  if (_prismGoldenFontsLoaded) return;

  await Future.wait([
    _loadFont('Lexend', ['assets/fonts/Lexend[wght].ttf']),
    _loadFont('Unbounded', [
      'assets/fonts/Unbounded-Bold.ttf',
      'assets/fonts/Unbounded-ExtraBold.ttf',
    ]),
    _loadFont('AtkinsonHyperlegible', [
      'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
      'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
      'assets/fonts/AtkinsonHyperlegible-Italic.ttf',
      'assets/fonts/AtkinsonHyperlegible-BoldItalic.ttf',
    ]),
    _loadFont('OpenDyslexic', [
      'assets/fonts/OpenDyslexic3-Regular.ttf',
      'assets/fonts/OpenDyslexic3-Bold.ttf',
    ]),
    _loadFont('NotoColorEmoji', ['assets/fonts/NotoColorEmoji.ttf']),
    _loadFont('Noto Color Emoji', ['assets/fonts/NotoColorEmoji.ttf']),
    _loadFont('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']),
    _loadFont('packages/phosphor_flutter/PhosphorRegular', [
      'packages/phosphor_flutter/lib/fonts/Phosphor.ttf',
    ]),
    _loadFont('packages/phosphor_flutter/PhosphorBold', [
      'packages/phosphor_flutter/lib/fonts/Phosphor-Bold.ttf',
    ]),
    _loadFont('packages/phosphor_flutter/PhosphorDuotone', [
      'packages/phosphor_flutter/lib/fonts/Phosphor-Duotone.ttf',
    ]),
    _loadFont('packages/phosphor_flutter/PhosphorFill', [
      'packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf',
    ]),
    _loadFont('packages/phosphor_flutter/PhosphorLight', [
      'packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
    ]),
    _loadFont('packages/phosphor_flutter/PhosphorThin', [
      'packages/phosphor_flutter/lib/fonts/Phosphor-Thin.ttf',
    ]),
  ]);
  _prismGoldenFontsLoaded = true;
}

Future<void> _loadFont(String family, List<String> assetKeys) async {
  final loader = FontLoader(family);
  for (final assetKey in assetKeys) {
    loader.addFont(_loadFontData(assetKey));
  }
  await loader.load();
}

Future<ByteData> _loadFontData(String assetKey) async {
  try {
    return await rootBundle.load(assetKey);
  } on FlutterError {
    final bytes = await File(assetKey).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

enum PrismGoldenThemeVariant { light, dark, oled, paletteLight, paletteDark }

const prismGoldenPaletteSeedColorHex = '#C6FF00';

class PrismGoldenDevice {
  const PrismGoldenDevice({required this.name, required this.size});

  final String name;
  final Size size;
}

const prismGoldenPhone = PrismGoldenDevice(name: 'phone', size: Size(390, 844));

const prismGoldenTablet = PrismGoldenDevice(
  name: 'tablet',
  size: Size(834, 1112),
);

class PrismGoldenScenario {
  const PrismGoldenScenario({
    required this.name,
    required this.child,
    this.width = 430,
  });

  final String name;
  final Widget child;
  final double width;
}

class PrismGoldenBoard extends StatelessWidget {
  const PrismGoldenBoard({super.key, required this.scenarios});

  final List<PrismGoldenScenario> scenarios;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFF4F1EA),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final scenario in scenarios)
                SizedBox(
                  width: scenario.width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle(
                        style: const TextStyle(
                          color: Color(0xFF2B2824),
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        child: Text(scenario.name),
                      ),
                      const SizedBox(height: 8),
                      scenario.child,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget prismGoldenApp({
  required Widget child,
  PrismGoldenThemeVariant themeVariant = PrismGoldenThemeVariant.light,
  PrismGoldenDevice device = prismGoldenPhone,
  double textScaleFactor = 1,
  List<Override> overrides = const [],
}) {
  final baseTheme = switch (themeVariant) {
    PrismGoldenThemeVariant.light => AppTheme.light(),
    PrismGoldenThemeVariant.dark => AppTheme.dark(),
    PrismGoldenThemeVariant.oled => AppTheme.oled(),
    PrismGoldenThemeVariant.paletteLight => _paletteTheme(isDark: false),
    PrismGoldenThemeVariant.paletteDark => _paletteTheme(isDark: true),
  };
  final theme = AppTheme.withAppFontFamily(
    baseTheme,
    'Lexend',
    preserveDisplayFont: true,
  );

  return SizedBox(
    width: device.size.width,
    height: device.size.height,
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamilyFallback: [
              'NotoColorEmoji',
              'Apple Color Emoji',
              'Segoe UI Emoji',
              'Noto Color Emoji',
            ],
          ),
          child: MediaQuery(
            data: MediaQueryData(
              size: device.size,
              devicePixelRatio: 1,
              textScaler: TextScaler.linear(textScaleFactor),
              disableAnimations: true,
              platformBrightness: theme.brightness,
            ),
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: device.size.width, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

ThemeData _paletteTheme({required bool isDark}) {
  return isDark
      ? AppTheme.materialYouDark(
          null,
          paletteSource: PaletteSource.custom,
          paletteSeedColorHex: prismGoldenPaletteSeedColorHex,
          paletteMood: PaletteMood.fidelity,
          paletteContrast: PaletteContrast.soft,
        )
      : AppTheme.materialYouLight(
          null,
          paletteSource: PaletteSource.custom,
          paletteSeedColorHex: prismGoldenPaletteSeedColorHex,
          paletteMood: PaletteMood.fidelity,
          paletteContrast: PaletteContrast.soft,
        );
}
