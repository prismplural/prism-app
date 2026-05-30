import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/prism_chip.dart';

void main() {
  const longLabel =
      'She/Her, Sae/Saers, Lace/Laces, Bliss/Blissful, Pure/Pures';

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('wraps a long label inside bounded width', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 220,
          child: PrismChip(label: longLabel, selected: false, onTap: null),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final label = tester.widget<Text>(find.text(longLabel));
    expect(label.maxLines, 2);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(longLabel)).height, greaterThan(20));
  });

  testWidgets('does not use flex in an unbounded horizontal scroller', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PrismChip(label: longLabel, selected: true, onTap: null),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(longLabel), findsOneWidget);
  });
}
