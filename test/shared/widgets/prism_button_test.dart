import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {

  group('PrismButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(testApp(
        PrismButton(label: 'Save', onPressed: () {}),
      ));

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(testApp(
        PrismButton(label: 'Add', icon: Icons.add, onPressed: () {}),
      ));

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('fires onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(
        PrismButton(label: 'Go', onPressed: () => tapped = true),
      ));

      await tester.tap(find.text('Go'));
      expect(tapped, isTrue);
    });

    testWidgets('does not fire onPressed when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(
        PrismButton(
          label: 'Go',
          onPressed: () => tapped = true,
          enabled: false,
        ),
      ));

      await tester.tap(find.text('Go'));
      expect(tapped, isFalse);
    });

    testWidgets('does not fire onPressed when loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(
        PrismButton(
          label: 'Go',
          onPressed: () => tapped = true,
          isLoading: true,
        ),
      ));

      // Label is hidden during loading, tap the progress indicator area
      await tester.tap(find.byType(PrismButton));
      expect(tapped, isFalse);
    });

    testWidgets('shows CircularProgressIndicator when loading', (tester) async {
      await tester.pumpWidget(testApp(
        PrismButton(label: 'Go', onPressed: () {}, isLoading: true),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Go'), findsNothing);
    });

    testWidgets('uses semanticLabel when provided', (tester) async {
      await tester.pumpWidget(testApp(
        PrismButton(
          label: 'X',
          onPressed: () {},
          semanticLabel: 'Close dialog',
        ),
      ));

      final semantics = tester.getSemantics(find.byType(PrismButton));
      expect(semantics.label, contains('Close dialog'));
    });

    group('tones', () {
      for (final tone in PrismButtonTone.values) {
        testWidgets('renders with $tone tone', (tester) async {
          await tester.pumpWidget(testApp(
            PrismButton(label: tone.name, onPressed: () {}, tone: tone),
          ));

          expect(find.text(tone.name), findsOneWidget);
          // Verify it doesn't crash and renders an AnimatedContainer
          expect(find.byType(AnimatedContainer), findsOneWidget);
        });
      }
    });

    group('expanded', () {
      testWidgets('uses MainAxisSize.min by default', (tester) async {
        await tester.pumpWidget(testApp(
          PrismButton(label: 'Narrow', onPressed: () {}),
        ));

        final row = tester.widget<Row>(find.byType(Row));
        expect(row.mainAxisSize, MainAxisSize.min);
      });

      testWidgets('uses MainAxisSize.max when expanded', (tester) async {
        await tester.pumpWidget(testApp(
          PrismButton(label: 'Wide', onPressed: () {}, expanded: true),
        ));

        final row = tester.widget<Row>(find.byType(Row));
        expect(row.mainAxisSize, MainAxisSize.max);
      });
    });

    group('density', () {
      testWidgets('compact density uses smaller padding', (tester) async {
        await tester.pumpWidget(testApp(
          PrismButton(
            label: 'Compact',
            onPressed: () {},
            density: PrismControlDensity.compact,
          ),
        ));

        final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final padding = container.padding as EdgeInsets;
        expect(padding.left, 16.0);
        expect(padding.top, 8.0);
      });

      testWidgets('regular density uses larger padding', (tester) async {
        await tester.pumpWidget(testApp(
          PrismButton(
            label: 'Regular',
            onPressed: () {},
            density: PrismControlDensity.regular,
          ),
        ));

        final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final padding = container.padding as EdgeInsets;
        expect(padding.left, 24.0);
        expect(padding.top, 12.0);
      });
    });
  });

  group('PrismIconButton', () {
    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(testApp(
        PrismIconButton(icon: Icons.settings, onPressed: () {}),
      ));

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('fires onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(
        PrismIconButton(icon: Icons.add, onPressed: () => tapped = true),
      ));

      await tester.tap(find.byType(PrismIconButton));
      expect(tapped, isTrue);
    });

    testWidgets('does not fire when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(testApp(
        PrismIconButton(
          icon: Icons.add,
          onPressed: () => tapped = true,
          enabled: false,
        ),
      ));

      await tester.tap(find.byType(PrismIconButton));
      expect(tapped, isFalse);
    });

    testWidgets('shows tooltip when provided', (tester) async {
      await tester.pumpWidget(testApp(
        PrismIconButton(
          icon: Icons.add,
          onPressed: () {},
          tooltip: 'Add item',
        ),
      ));

      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('fires onLongPress', (tester) async {
      var longPressed = false;
      await tester.pumpWidget(testApp(
        PrismIconButton(
          icon: Icons.add,
          onPressed: () {},
          onLongPress: () => longPressed = true,
        ),
      ));

      await tester.longPress(find.byType(PrismIconButton));
      expect(longPressed, isTrue);
    });
  });
}
