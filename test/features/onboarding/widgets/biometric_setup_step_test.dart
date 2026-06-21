import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/features/onboarding/widgets/biometric_setup_step.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake PinLockService
// ---------------------------------------------------------------------------

class _FakePinLockService extends PinLockService {
  _FakePinLockService({this.available = true});

  bool available;
  int availabilityChecks = 0;

  @override
  Future<bool> isBiometricAvailable() async {
    availabilityChecks++;
    return available;
  }
}

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

Widget _buildStep({
  required _FakePinLockService fakeService,
  required VoidCallback onEnrolled,
  required VoidCallback onSkipped,
}) {
  return ProviderScope(
    overrides: [pinLockServiceProvider.overrideWithValue(fakeService)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: BiometricSetupStep(onEnrolled: onEnrolled, onSkipped: onSkipped),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('renders Enable and Not-now buttons when biometric available', (
    tester,
  ) async {
    final fake = _FakePinLockService(available: true);

    await tester.pumpWidget(
      _buildStep(fakeService: fake, onEnrolled: () {}, onSkipped: () {}),
    );

    // Settle the first frame.
    await tester.pump();

    expect(find.text('Enable biometrics'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('does not check availability before user taps Enable', (
    tester,
  ) async {
    final fake = _FakePinLockService(available: false);
    var skipped = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        onEnrolled: () {},
        onSkipped: () => skipped = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(fake.availabilityChecks, 0);
    expect(skipped, isFalse);
    expect(find.text('Enable biometrics'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Enable button checks availability then onEnrolled', (
    tester,
  ) async {
    final fake = _FakePinLockService(available: true);
    var enrolled = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        onEnrolled: () => enrolled = true,
        onSkipped: () {},
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Enable biometrics'));
    await tester.pump();

    expect(fake.availabilityChecks, 1);
    expect(enrolled, isTrue);
  });

  testWidgets('Enable button skips when biometric unavailable', (tester) async {
    final fake = _FakePinLockService(available: false);
    var skipped = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        onEnrolled: () {},
        onSkipped: () => skipped = true,
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Enable biometrics'));
    await tester.pump();

    expect(fake.availabilityChecks, 1);
    expect(skipped, isTrue);
  });

  testWidgets('Not-now button calls onSkipped', (tester) async {
    final fake = _FakePinLockService(available: true);
    var skipped = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        onEnrolled: () {},
        onSkipped: () => skipped = true,
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Not now'));
    await tester.pump();

    expect(skipped, isTrue);
  });
}
