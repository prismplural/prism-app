import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  group('PrismSpinner', () {
    testWidgets('honors requested size inside tight parent constraints', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const SizedBox(
            width: 200,
            height: 200,
            child: PrismSpinner(color: Colors.purple, size: 24),
          ),
        ),
      );

      final paintRect = tester.getRect(
        find.descendant(
          of: find.byType(PrismSpinner),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paintRect.width, 24);
      expect(paintRect.height, 24);
    });

    testWidgets('keeps tight bounds inside loose bounded layouts', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const SizedBox(
            width: 200,
            height: 200,
            child: Align(
              alignment: Alignment.topLeft,
              child: PrismSpinner(color: Colors.purple, size: 24),
            ),
          ),
        ),
      );

      final spinnerRect = tester.getRect(find.byType(PrismSpinner));
      expect(spinnerRect.width, 24);
      expect(spinnerRect.height, 24);
    });
  });

  group('PrismLoadingState', () {
    testWidgets('uses a compact spinner inside short bounded layouts', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const SizedBox(width: 240, height: 48, child: PrismLoadingState()),
        ),
      );

      final spinner = tester.widget<PrismSpinner>(find.byType(PrismSpinner));
      expect(spinner.size, lessThan(40));
    });

    testWidgets('does not exceed tiny bounded layouts', (tester) async {
      await tester.pumpWidget(
        testApp(
          const SizedBox(width: 10, height: 10, child: PrismLoadingState()),
        ),
      );

      final spinner = tester.widget<PrismSpinner>(find.byType(PrismSpinner));
      expect(spinner.size, lessThanOrEqualTo(10));
    });
  });
}
