import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart';

void main() {
  group('arrangeOverflowRows', () {
    test('returns empty when tabs or columns are empty', () {
      expect(arrangeOverflowRows<String>([], 4), isEmpty);
      expect(arrangeOverflowRows(['A'], 0), isEmpty);
    });

    test('fills a single row when tabs fit in one row', () {
      expect(arrangeOverflowRows(['A', 'B', 'C'], 4), [
        ['A', 'B', 'C'],
      ]);
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D', 'E'], 5), [
        ['A', 'B', 'C', 'D', 'E'],
      ]);
    });

    test('puts the partial row on top centered, full row on bottom', () {
      // 5 items in 4 cols: 1 on top (centered-ish), 4 on bottom.
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D', 'E'], 4), [
        [null, 'A', null, null],
        ['B', 'C', 'D', 'E'],
      ]);

      // 6 items in 4 cols: 2 on top (centered), 4 on bottom.
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D', 'E', 'F'], 4), [
        [null, 'A', 'B', null],
        ['C', 'D', 'E', 'F'],
      ]);
    });

    test('keeps all rows full when tabs divide evenly', () {
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D'], 2), [
        ['A', 'B'],
        ['C', 'D'],
      ]);
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'], 4), [
        ['A', 'B', 'C', 'D'],
        ['E', 'F', 'G', 'H'],
      ]);
    });

    test('handles multi-row overflow with partial top row', () {
      // 7 items in 3 cols: 1 partial + 2 full rows.
      expect(arrangeOverflowRows(['A', 'B', 'C', 'D', 'E', 'F', 'G'], 3), [
        [null, 'A', null],
        ['B', 'C', 'D'],
        ['E', 'F', 'G'],
      ]);
    });
  });

  test('kMaxAdaptiveOverflowColumns is 5', () {
    // The overflow menu should allow up to 5 columns so 5 overflow items
    // can fit in a single row when labels are short enough.
    expect(kMaxAdaptiveOverflowColumns, 5);
  });

  testWidgets(
    'navBarLabelTextStyle uses shared nav metrics instead of ambient DefaultTextStyle',
    (tester) async {
      TextStyle? style;

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTextStyle(
            style: const TextStyle(fontSize: 30, letterSpacing: 4),
            child: Builder(
              builder: (context) {
                style = navBarLabelTextStyle(context, isSelected: true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(style?.fontSize, kNavBarLabelFontSize);
      expect(style?.letterSpacing, 0);
      expect(style?.fontWeight, FontWeight.w600);
    },
  );
}
