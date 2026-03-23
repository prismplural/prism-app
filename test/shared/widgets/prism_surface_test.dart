import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('PrismSurface', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(buildApp(
        const PrismSurface(child: Text('Hello')),
      ));

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildApp(
        PrismSurface(
          onTap: () => tapped = true,
          child: const Text('Tap me'),
        ),
      ));

      await tester.tap(find.text('Tap me'));
      expect(tapped, isTrue);
    });

    testWidgets('fires onLongPress callback', (tester) async {
      var longPressed = false;
      await tester.pumpWidget(buildApp(
        PrismSurface(
          onTap: () {},
          onLongPress: () => longPressed = true,
          child: const Text('Hold me'),
        ),
      ));

      await tester.longPress(find.text('Hold me'));
      expect(longPressed, isTrue);
    });

    testWidgets('wraps content in ClipRRect for child clipping', (tester) async {
      await tester.pumpWidget(buildApp(
        const PrismSurface(child: Text('Clipped')),
      ));

      expect(find.byType(ClipRRect), findsOneWidget);
      final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clipRRect.clipBehavior, Clip.antiAlias);
    });

    testWidgets('does not wrap in InkWell when no onTap', (tester) async {
      await tester.pumpWidget(buildApp(
        const PrismSurface(child: Text('Static')),
      ));

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('wraps in InkWell when onTap is provided', (tester) async {
      await tester.pumpWidget(buildApp(
        PrismSurface(onTap: () {}, child: const Text('Tappable')),
      ));

      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('applies margin as outer Padding', (tester) async {
      await tester.pumpWidget(buildApp(
        const PrismSurface(
          margin: EdgeInsets.all(20),
          child: Text('Margined'),
        ),
      ));

      // The outermost Padding is the margin
      final padding = tester.widget<Padding>(find.byType(Padding).first);
      expect(padding.padding, const EdgeInsets.all(20));
    });

    for (final tone in PrismSurfaceTone.values) {
      testWidgets('renders with $tone tone', (tester) async {
        await tester.pumpWidget(buildApp(
          PrismSurface(tone: tone, child: Text(tone.name)),
        ));

        expect(find.text(tone.name), findsOneWidget);
      });
    }

    testWidgets('sets semantic label when tappable', (tester) async {
      await tester.pumpWidget(buildApp(
        PrismSurface(
          onTap: () {},
          semanticLabel: 'Card action',
          child: const Text('Content'),
        ),
      ));

      // Verify the Semantics widget is present with the label
      expect(
        find.bySemanticsLabel(RegExp('Card action')),
        findsOneWidget,
      );
    });
  });
}
