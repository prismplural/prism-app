import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

void main() {
  testWidgets('tinted glass shadow stays soft in light mode', (tester) async {
    final theme = ThemeData.light();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: TintedGlassSurface(
                width: 40,
                height: 40,
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    final decoration = _surfaceDecoration(tester);
    final shadow = _surfaceShadow(tester);
    final expectedBase = theme.colorScheme.surfaceContainerHigh.withValues(
      alpha: PrismTokens.tintedFillAlphaLight,
    );

    expect(
      decoration.color,
      Color.alphaBlend(
        theme.colorScheme.primary.withValues(
          alpha: PrismTokens.tintedDefaultTintAlphaLight,
        ),
        expectedBase,
      ),
    );
    expect(_surfaceHighlight(tester).colors.first.a, 0.10);
    expect(shadow.color.a, 0.03);
    expect(shadow.blurRadius, 4);
    expect(shadow.offset, const Offset(0, 1));
  });

  testWidgets('tinted glass shadow stays soft in dark mode', (tester) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: TintedGlassSurface(
                width: 40,
                height: 40,
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    final decoration = _surfaceDecoration(tester);
    final shadow = _surfaceShadow(tester);
    final expectedBase = theme.colorScheme.surfaceContainerHigh.withValues(
      alpha: PrismTokens.tintedFillAlphaDark * 2.4,
    );

    expect(
      decoration.color,
      Color.alphaBlend(
        theme.colorScheme.primary.withValues(
          alpha: PrismTokens.tintedDefaultTintAlphaDark,
        ),
        expectedBase,
      ),
    );
    expect(_surfaceHighlight(tester).colors.first.a, 0.10);
    expect(shadow.color.a, 0.10);
    expect(shadow.blurRadius, 4);
    expect(shadow.offset, const Offset(0, 1));
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester) {
  return _surfaceContainer(tester).decoration! as BoxDecoration;
}

LinearGradient _surfaceHighlight(WidgetTester tester) {
  final foreground = _surfaceContainer(tester).foregroundDecoration;
  if (foreground is BoxDecoration && foreground.gradient is LinearGradient) {
    return foreground.gradient! as LinearGradient;
  }
  throw TestFailure('Could not find tinted glass highlight.');
}

Container _surfaceContainer(WidgetTester tester) {
  for (final container in tester.widgetList<Container>(
    find.byType(Container),
  )) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration &&
        decoration.boxShadow != null &&
        decoration.boxShadow!.isNotEmpty) {
      return container;
    }
  }
  throw TestFailure('Could not find tinted glass decoration.');
}

BoxShadow _surfaceShadow(WidgetTester tester) {
  return _surfaceDecoration(tester).boxShadow!.single;
}
