import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';

void main() {
  testWidgets('defaults to request-to-join without legacy invite option', (
    tester,
  ) async {
    var completed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
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
    expect(find.text('Self-hosted relay?'), findsOneWidget);
    expect(find.text('Relay URL'), findsNothing);
    expect(find.text('Registration token'), findsNothing);
    expect(find.text('Use a legacy invite instead'), findsNothing);
    expect(find.text('Scan legacy invite'), findsNothing);
    expect(completed, isFalse);
  });

  testWidgets('self-hosted relay fields can be expanded from the join prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SyncDeviceStep(onBack: () {}, onComplete: () {}),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Self-hosted relay?'));
    await tester.pumpAndSettle();

    expect(find.text('Relay URL'), findsOneWidget);
    expect(find.text('Registration token'), findsOneWidget);
  });

  testWidgets('validates typed relay URL even after section is collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SyncDeviceStep(onBack: () {}, onComplete: () {}),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Self-hosted relay?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'http://relay.local');

    await tester.tap(find.text('Self-hosted relay?'));
    await tester.pumpAndSettle();
    expect(find.text('Relay URL'), findsNothing);

    await tester.tap(find.text('Request to Join'));
    await tester.pumpAndSettle();

    expect(find.text('Relay URL'), findsOneWidget);
    expect(find.text('Relay URL must start with https://'), findsOneWidget);
  });
}
