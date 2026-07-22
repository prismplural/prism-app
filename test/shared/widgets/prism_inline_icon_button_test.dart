import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  testWidgets('fires onSecondaryTap callback', (tester) async {
    var secondaryTapped = false;

    await tester.pumpWidget(
      testApp(
        PrismInlineIconButton(
          icon: AppIcons.moreVert,
          semanticLabel: 'More options',
          onPressed: () {},
          onSecondaryTap: () => secondaryTapped = true,
        ),
      ),
    );

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.byType(PrismInlineIconButton)));
    await tester.pump();
    await gesture.up();

    expect(secondaryTapped, isTrue);
  });

  testWidgets('does not fire onSecondaryTap when disabled', (tester) async {
    var secondaryTapped = false;

    await tester.pumpWidget(
      testApp(
        PrismInlineIconButton(
          icon: AppIcons.moreVert,
          semanticLabel: 'More options',
          enabled: false,
          onPressed: () {},
          onSecondaryTap: () => secondaryTapped = true,
        ),
      ),
    );

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.byType(PrismInlineIconButton)));
    await tester.pump();
    await gesture.up();

    expect(secondaryTapped, isFalse);
  });
}
