import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

void main() {
  testWidgets('restart-required recovery screen tells user to reopen Prism', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResetRecoveryScreen(
          mode: ResetRecoveryScreenMode.restartRequired,
        ),
      ),
    );

    expect(find.text('Reset complete'), findsOneWidget);
    expect(
      find.text('Close Prism completely, then reopen it to start fresh.'),
      findsOneWidget,
    );

    final button = tester.widget<PrismButton>(
      find.widgetWithText(PrismButton, 'Close and reopen Prism'),
    );
    expect(button.enabled, isFalse);
  });
}
