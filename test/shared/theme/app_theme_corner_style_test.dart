import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

void main() {
  group('AppTheme with CornerStyle', () {
    test('light with rounded attaches PrismShapes.rounded extension', () {
      final theme = AppTheme.light(cornerStyle: CornerStyle.rounded);
      final shapes = theme.extension<PrismShapes>();
      expect(shapes, isNotNull);
      expect(shapes!.cornerStyle, CornerStyle.rounded);
    });

    test('light with angular attaches PrismShapes.angular extension', () {
      final theme = AppTheme.light(cornerStyle: CornerStyle.angular);
      expect(theme.extension<PrismShapes>()!.cornerStyle, CornerStyle.angular);
    });

    test('dark with angular flattens CardTheme radius to 0', () {
      final theme = AppTheme.dark(cornerStyle: CornerStyle.angular);
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder?;
      expect(cardShape, isNotNull);
      final br = cardShape!.borderRadius as BorderRadius;
      expect(br.topLeft.x, 0);
      expect(br.topRight.x, 0);
    });

    test('light with angular returns non-circle FAB shape', () {
      final theme = AppTheme.light(cornerStyle: CornerStyle.angular);
      expect(
        theme.floatingActionButtonTheme.shape,
        isA<RoundedRectangleBorder>(),
      );
    });

    test('light with rounded returns CircleBorder FAB shape', () {
      final theme = AppTheme.light(cornerStyle: CornerStyle.rounded);
      expect(theme.floatingActionButtonTheme.shape, isA<CircleBorder>());
    });

    test('oled with angular still attaches the extension', () {
      final theme = AppTheme.oled(cornerStyle: CornerStyle.angular);
      expect(theme.extension<PrismShapes>()!.cornerStyle, CornerStyle.angular);
    });

    test('withoutDisplayFont clears display font family', () {
      final theme = AppTheme.light();

      expect(theme.textTheme.displayLarge?.fontFamily, 'Unbounded');
      expect(theme.textTheme.displayMedium?.fontFamily, 'Unbounded');
      expect(theme.textTheme.displaySmall?.fontFamily, 'Unbounded');
      expect(theme.textTheme.headlineLarge?.fontFamily, 'Unbounded');

      final stripped = AppTheme.withoutDisplayFont(theme);

      expect(stripped.textTheme.displayLarge?.fontFamily, isNull);
      expect(stripped.textTheme.displayMedium?.fontFamily, isNull);
      expect(stripped.textTheme.displaySmall?.fontFamily, isNull);
      expect(stripped.textTheme.headlineLarge?.fontFamily, isNull);
      expect(stripped.textTheme.headlineLarge?.letterSpacing, 0);
    });

    test('accessible font preserves enabled display font roles', () {
      final theme = AppTheme.light();
      final withAccessibleFont = AppTheme.withAppFontFamily(
        theme,
        'AtkinsonHyperlegible',
        preserveDisplayFont: true,
      );

      expect(
        withAccessibleFont.textTheme.bodyMedium?.fontFamily,
        'AtkinsonHyperlegible',
      );
      expect(
        withAccessibleFont.textTheme.displayLarge?.fontFamily,
        'Unbounded',
      );
      expect(
        withAccessibleFont.textTheme.headlineLarge?.fontFamily,
        'Unbounded',
      );
    });

    test('accessible font applies to disabled display font roles', () {
      final theme = AppTheme.withoutDisplayFont(AppTheme.light());
      final withAccessibleFont = AppTheme.withAppFontFamily(
        theme,
        'AtkinsonHyperlegible',
        preserveDisplayFont: false,
      );

      expect(
        withAccessibleFont.textTheme.bodyMedium?.fontFamily,
        'AtkinsonHyperlegible',
      );
      expect(
        withAccessibleFont.textTheme.displayLarge?.fontFamily,
        'AtkinsonHyperlegible',
      );
      expect(
        withAccessibleFont.textTheme.headlineLarge?.fontFamily,
        'AtkinsonHyperlegible',
      );
    });

    test('letter spacing preference applies to text and component themes', () {
      final theme = AppTheme.light();
      final adjusted = AppTheme.withLetterSpacing(theme, -0.4);

      expect(
        adjusted.textTheme.bodyMedium?.letterSpacing,
        closeTo(-0.4, 0.001),
      );
      expect(
        adjusted.textTheme.headlineLarge?.letterSpacing,
        closeTo(0.1, 0.001),
      );
      expect(
        adjusted.primaryTextTheme.bodyMedium?.letterSpacing,
        closeTo(-0.4, 0.001),
      );
      expect(
        adjusted.snackBarTheme.contentTextStyle?.letterSpacing,
        closeTo(-0.4, 0.001),
      );
      expect(
        adjusted.chipTheme.labelStyle?.letterSpacing,
        closeTo(-0.4, 0.001),
      );
      expect(
        adjusted.tooltipTheme.textStyle?.letterSpacing,
        closeTo(-0.4, 0.001),
      );
    });

    test('text themes do not install symbol fallbacks globally', () {
      final theme = AppTheme.light();
      final fallback = theme.textTheme.bodyMedium?.fontFamilyFallback;

      expect(
        fallback ?? const <String>[],
        isNot(contains('Noto Sans Symbols')),
      );
    });

    test(
      'Linux keeps color emoji fallback without text symbol fonts globally',
      () {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previousPlatform;
        });

        final fallback =
            AppTheme.light().textTheme.bodyMedium?.fontFamilyFallback;

        expect(fallback, isNotNull);
        expect(fallback, contains('NotoColorEmoji'));
        expect(fallback!, isNot(contains('Noto Sans Symbols')));
      },
    );
  });

  testWidgets(
    'MaterialApp with cornerStyleProvider.overrideWith(angular) propagates',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cornerStyleProvider.overrideWith((ref) => CornerStyle.angular),
          ],
          child: MaterialApp(
            theme: AppTheme.light(cornerStyle: CornerStyle.angular),
            home: Builder(
              builder: (context) {
                final shapes = Theme.of(context).extension<PrismShapes>();
                expect(shapes, isNotNull);
                expect(shapes!.cornerStyle, CornerStyle.angular);
                return const Scaffold();
              },
            ),
          ),
        ),
      );
    },
  );
}
