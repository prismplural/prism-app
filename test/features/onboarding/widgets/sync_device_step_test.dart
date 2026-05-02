import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';

class _FakeDevicePairingNotifier extends DevicePairingNotifier {
  _FakeDevicePairingNotifier(this.initialState);

  final PairingState initialState;
  String? capturedPin;
  int completionCount = 0;
  int confirmSasCount = 0;
  int resetCount = 0;

  @override
  PairingState build() => initialState;

  @override
  Future<void> completeJoinerWithPin(String pin) async {
    capturedPin = pin;
    completionCount++;
  }

  @override
  void confirmSas() {
    confirmSasCount++;
  }

  @override
  void reset() {
    resetCount++;
    state = const PairingState();
  }
}

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

  testWidgets('PIN entry is secure-scoped and submits six digits', (
    tester,
  ) async {
    final notifier = _FakeDevicePairingNotifier(
      const PairingState(step: PairingStep.enterPin),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [devicePairingProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SyncDeviceStep(onBack: () {}, onComplete: () {}),
          ),
        ),
      ),
    );

    expect(find.byType(SecureScope), findsOneWidget);
    expect(find.text('Enter your sync PIN'), findsOneWidget);

    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(notifier.capturedPin, '123456');
    expect(notifier.completionCount, 1);
  });

  testWidgets('SAS step displays five words and no decimal fallback', (
    tester,
  ) async {
    final notifier = _FakeDevicePairingNotifier(
      const PairingState(
        step: PairingStep.showingSas,
        sasWords: ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [devicePairingProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SyncDeviceStep(onBack: () {}, onComplete: () {}),
          ),
        ),
      ),
    );

    expect(find.text('Verify Security Code'), findsOneWidget);
    for (final word in ['alpha', 'bravo', 'charlie', 'delta', 'echo']) {
      expect(find.text(word), findsOneWidget);
    }
    expect(find.text('123456'), findsNothing);

    await tester.tap(find.text('They Match'));
    await tester.pump();
    expect(notifier.confirmSasCount, 1);

    await tester.tap(find.text("They Don't Match"));
    await tester.pump();
    expect(notifier.resetCount, 1);
  });
}
