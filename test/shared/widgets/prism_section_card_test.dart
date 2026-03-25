import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {

  group('PrismSectionCard', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(testApp(center: false,
        const PrismSectionCard(child: Text('Card content')),
      ));

      expect(find.text('Card content'), findsOneWidget);
    });

    testWidgets('delegates to PrismSurface', (tester) async {
      await tester.pumpWidget(testApp(center: false,
        const PrismSectionCard(child: Text('Hello')),
      ));

      expect(find.byType(PrismSurface), findsOneWidget);
    });

    testWidgets('forwards onTap to PrismSurface', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(center: false,
        PrismSectionCard(
          onTap: () => tapped = true,
          child: const Text('Tap target'),
        ),
      ));

      await tester.tap(find.text('Tap target'));
      expect(tapped, isTrue);
    });

    testWidgets('forwards onLongPress to PrismSurface', (tester) async {
      var longPressed = false;
      await tester.pumpWidget(testApp(center: false,
        PrismSectionCard(
          onTap: () {},
          onLongPress: () => longPressed = true,
          child: const Text('Hold target'),
        ),
      ));

      await tester.longPress(find.text('Hold target'));
      expect(longPressed, isTrue);
    });

    testWidgets('is not tappable when no callbacks provided', (tester) async {
      await tester.pumpWidget(testApp(center: false,
        const PrismSectionCard(child: Text('Static card')),
      ));

      // No InkWell when not tappable
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('forwards tone to PrismSurface', (tester) async {
      await tester.pumpWidget(testApp(center: false,
        const PrismSectionCard(
          tone: PrismSurfaceTone.strong,
          child: Text('Strong'),
        ),
      ));

      final surface = tester.widget<PrismSurface>(find.byType(PrismSurface));
      expect(surface.tone, PrismSurfaceTone.strong);
    });

    testWidgets('forwards accentColor to PrismSurface', (tester) async {
      await tester.pumpWidget(testApp(center: false,
        const PrismSectionCard(
          accentColor: Colors.red,
          child: Text('Accented'),
        ),
      ));

      final surface = tester.widget<PrismSurface>(find.byType(PrismSurface));
      expect(surface.accentColor, Colors.red);
    });
  });
}
