import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  testWidgets('uses tooltip as semantic label', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          PrismGlassIconButton(
            icon: AppIcons.check,
            tooltip: 'Confirm selection',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Confirm selection'), findsOneWidget);
  });

  testWidgets('uses explicit semanticLabel when provided', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          PrismGlassIconButton(
            icon: AppIcons.close,
            tooltip: 'Close',
            semanticLabel: 'Dismiss sheet',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Dismiss sheet'), findsOneWidget);
  });

  testWidgets('asserts when neither tooltip nor semanticLabel is provided', (
    tester,
  ) async {
    expect(
      () => PrismGlassIconButton(icon: AppIcons.check, onPressed: () {}),
      throwsAssertionError,
    );
  });
}
