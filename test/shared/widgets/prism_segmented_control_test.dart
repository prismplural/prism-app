import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

enum _Tab { a, b }

Widget _harness({
  required int? badgeACount,
  String? badgeASemanticLabel,
  int? badgeBCount,
  String? badgeBSemanticLabel,
  _Tab selected = _Tab.a,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: PrismSegmentedControl<_Tab>(
            segments: [
              PrismSegment(
                value: _Tab.a,
                label: 'Alpha',
                badgeCount: badgeACount,
                badgeSemanticLabel: badgeASemanticLabel,
              ),
              PrismSegment(
                value: _Tab.b,
                label: 'Beta',
                badgeCount: badgeBCount,
                badgeSemanticLabel: badgeBSemanticLabel,
              ),
            ],
            selected: selected,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('PrismSegmentedControl badges', () {
    testWidgets('renders no badge text when badgeCount is null', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(badgeACount: null));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('9+'), findsNothing);
    });

    testWidgets('renders no badge text when badgeCount is 0', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 0));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders the count when badgeCount is 5', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 5));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('caps at "9+" when badgeCount exceeds 9', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 15));
      await tester.pumpAndSettle();

      expect(find.text('9+'), findsOneWidget);
      expect(find.text('15'), findsNothing);
    });

    testWidgets('exposes badgeSemanticLabel via Semantics', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(
          badgeACount: 3,
          badgeASemanticLabel: '3 unread direct messages',
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      // Badge Semantics wraps the Text child, so the merged label contains
      // both the caller-provided semantic label and the raw "3".
      expect(
        find.bySemanticsLabel(RegExp(r'3 unread direct messages')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('PrismSegmentedControl colors', () {
    test('stay separated from sheet surfaces in soft and regular palettes', () {
      const minRgbSeparation = 0.08;

      for (final contrast in [PaletteContrast.soft, PaletteContrast.standard]) {
        for (final theme in [
          AppTheme.materialYouLight(
            null,
            paletteSource: PaletteSource.custom,
            paletteSeedColorHex: '#9070A0',
            paletteContrast: contrast,
          ),
          AppTheme.materialYouDark(
            null,
            paletteSource: PaletteSource.custom,
            paletteSeedColorHex: '#9070A0',
            paletteContrast: contrast,
          ),
        ]) {
          final controlColors = PrismSegmentedControlColors.resolve(
            theme,
            highContrast: false,
          );
          final sheetSurface = theme.bottomSheetTheme.backgroundColor!;

          expect(controlColors.trackColor.toARGB32() >>> 24, 0xFF);
          expect(
            _rgbDistance(controlColors.trackColor, sheetSurface),
            greaterThanOrEqualTo(minRgbSeparation),
            reason: '${theme.brightness.name} ${contrast.name} track',
          );
          expect(
            _rgbDistance(controlColors.pillColor, sheetSurface),
            greaterThanOrEqualTo(minRgbSeparation),
            reason: '${theme.brightness.name} ${contrast.name} pill',
          );
          expect(
            _rgbDistance(controlColors.pillColor, controlColors.trackColor),
            greaterThanOrEqualTo(minRgbSeparation),
            reason: '${theme.brightness.name} ${contrast.name} selector',
          );
        }
      }
    });
  });
}

double _rgbDistance(Color a, Color b) {
  final dr = (a.r - b.r).abs();
  final dg = (a.g - b.g).abs();
  final db = (a.b - b.b).abs();
  return (dr + dg + db) / 3;
}
