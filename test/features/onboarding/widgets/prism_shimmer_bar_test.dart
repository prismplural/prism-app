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

  testWidgets('has Semantics loading label', (tester) async {
    await tester.pumpWidget(_wrap(const PrismShimmerBar()));

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });
}
