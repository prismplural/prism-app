import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/prism_shimmer_bar.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
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

  testWidgets('disableAnimations renders static bar with no running animations',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PrismShimmerBar(), disableAnimations: true),
    );
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('sweep gradient uses warmWhite alpha only (no color injection)',
      (tester) async {
    await tester.pumpWidget(_wrap(const PrismShimmerBar()));
    await tester.pump(const Duration(milliseconds: 100));

    final bar = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.gradient is LinearGradient;
        });
    final gradient = (bar.decoration as BoxDecoration).gradient as LinearGradient;

    for (final color in gradient.colors) {
      expect(color.r, equals(gradient.colors.first.r));
      expect(color.g, equals(gradient.colors.first.g));
      expect(color.b, equals(gradient.colors.first.b));
    }
  });
}
