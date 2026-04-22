import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders totalPhases segments', (tester) async {
    await tester.pumpWidget(
      _wrap(const PhaseSegments(currentIndex: 0, totalPhases: 4)),
    );

    // Each segment is a Container with a BoxDecoration that has a borderRadius.
    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        })
        .toList();

    expect(containers.length, 4);
  });

  testWidgets(
    'filled segments use full-alpha gradient, pending use low alpha',
    (tester) async {
      // currentIndex = 2 → indices 0 and 1 are filled, index 3 is pending.
      await tester.pumpWidget(
        _wrap(const PhaseSegments(currentIndex: 2, totalPhases: 4)),
      );

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration && d.borderRadius != null;
          })
          .toList();

      expect(containers.length, 4);

      // Filled segment (index 0): should have a gradient.
      final filledDecoration = containers[0].decoration as BoxDecoration;
      expect(filledDecoration.gradient, isNotNull);
      expect(filledDecoration.color, isNull);

      // Pending segment (index 3): should be a flat color with low alpha.
      final pendingDecoration = containers[3].decoration as BoxDecoration;
      expect(pendingDecoration.gradient, isNull);
      final pendingColor = pendingDecoration.color;
      expect(pendingColor, isNotNull);
      expect(pendingColor!.a, lessThan(0.5));
    },
  );

  testWidgets('respects disableAnimations — no running animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PhaseSegments(currentIndex: 1, totalPhases: 4),
        disableAnimations: true,
      ),
    );

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Semantics label includes current step position', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PhaseSegments(currentIndex: 2, totalPhases: 4),
        locale: const Locale('es'),
      ),
    );

    expect(find.bySemanticsLabel('Paso 3 de 4'), findsOneWidget);
  });
}
