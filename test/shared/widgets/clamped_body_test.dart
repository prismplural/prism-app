import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/clamped_body.dart';

void main() {
  testWidgets('clamps width without vertically centering short content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ClampedBody(
          child: SizedBox(key: Key('shortContent'), width: 100, height: 100),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byKey(const Key('shortContent')));

    expect(topLeft.dy, 0);
    expect(topLeft.dx, 450);
  });
}
