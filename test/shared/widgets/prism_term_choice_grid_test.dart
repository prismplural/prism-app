import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';

void main() {
  testWidgets('does not inherit safe-area padding inside a parent layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                child: PrismTermChoiceGrid<int>(
                  choices: const [
                    PrismTermChoice(value: 1, label: 'One'),
                    PrismTermChoice(value: 2, label: 'Two'),
                  ],
                  selected: 1,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gridTop = tester.getTopLeft(find.byType(GridView)).dy;
    final firstTileTop = tester
        .getTopLeft(find.byType(AnimatedContainer).first)
        .dy;

    expect(firstTileTop, gridTop);
  });
}
