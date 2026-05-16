import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/prism_shimmer_bar.dart';

Widget _wrap(Widget child, {bool disableAnimations = false, ThemeData? theme}) {
  final resolvedTheme =
      theme ??
      ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C60)),
      );

  return MaterialApp(
    theme: resolvedTheme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('renders with 12px height and rounded corners', (tester) async {
    await tester.pumpWidget(_wrap(const PrismShimmerBar()));

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        })
        .toList();

    expect(containers.isNotEmpty, isTrue);

    final bar = containers.first;
    expect(bar.constraints?.maxHeight, 12.0);

    final decoration = bar.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('runs animation in default mode', (tester) async {
    await tester.pumpWidget(_wrap(const PrismShimmerBar()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets(
    'disableAnimations renders static bar with no running animations',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const PrismShimmerBar(), disableAnimations: true),
      );
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('sweep gradient derives from light theme primary color', (
    tester,
  ) async {
    const seed = Color(0xFF006C60);
    final colorScheme = ColorScheme.fromSeed(seedColor: seed);
    await tester.pumpWidget(
      _wrap(
        const PrismShimmerBar(),
        theme: ThemeData.from(colorScheme: colorScheme),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final bar = tester.widgetList<Container>(find.byType(Container)).firstWhere(
      (c) {
        final d = c.decoration;
        return d is BoxDecoration && d.gradient is LinearGradient;
      },
    );
    final gradient =
        (bar.decoration as BoxDecoration).gradient as LinearGradient;

    expect(gradient.colors[0], colorScheme.primary.withValues(alpha: 0));
    expect(gradient.colors[1], colorScheme.primary.withValues(alpha: 0.60));
    expect(gradient.colors[2], colorScheme.primary.withValues(alpha: 0));
  });

  testWidgets('reduced-motion static fill derives from light theme primary', (
    tester,
  ) async {
    const seed = Color(0xFF006C60);
    final colorScheme = ColorScheme.fromSeed(seedColor: seed);
    await tester.pumpWidget(
      _wrap(
        const PrismShimmerBar(),
        disableAnimations: true,
        theme: ThemeData.from(colorScheme: colorScheme),
      ),
    );
    await tester.pump();

    final bar = tester.widgetList<Container>(find.byType(Container)).firstWhere(
      (c) {
        final d = c.decoration;
        return d is BoxDecoration && d.borderRadius != null;
      },
    );
    final decoration = bar.decoration as BoxDecoration;

    expect(decoration.color, colorScheme.primary.withValues(alpha: 0.28));
  });
}
