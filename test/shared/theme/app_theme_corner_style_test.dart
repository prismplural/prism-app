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
