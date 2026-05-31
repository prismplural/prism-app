import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';

void main() {
  testWidgets('clamps the initial date inside the picker bounds', (
    tester,
  ) async {
    final maximum = DateTime(2026, 5, 31, 16, 22, 42, 232, 731);
    final initial = DateTime(2026, 5, 31, 16, 22, 43, 83, 930);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Builder(
              builder: (anchorContext) => TextButton(
                onPressed: () {
                  unawaited(
                    showPrismDatePicker(
                      context: context,
                      anchorContext: anchorContext,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: maximum,
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
