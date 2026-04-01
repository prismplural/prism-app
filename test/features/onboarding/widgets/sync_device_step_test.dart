import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';

void main() {
  testWidgets('defaults to request-to-join without legacy invite option', (
    tester,
  ) async {
    var completed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SyncDeviceStep(
              onBack: () {},
              onComplete: () => completed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Request to Join'), findsOneWidget);
    expect(find.text('Use a legacy invite instead'), findsNothing);
    expect(find.text('Scan legacy invite'), findsNothing);
    expect(completed, isFalse);
  });
}
