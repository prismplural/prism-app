import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/biometric_service.dart';
import 'package:prism_plurality/core/services/biometric_service_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/biometric_setup_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake BiometricService
// ---------------------------------------------------------------------------

class _FakeBiometricService implements BiometricService {
  bool available;
  bool enrollCalled = false;

  _FakeBiometricService({this.available = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> enroll(Uint8List dekBytes) async {
    enrollCalled = true;
  }

  @override
  Future<Uint8List?> authenticate() async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<bool> isEnrolled() async => false;
}

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

Widget _buildStep({
  required _FakeBiometricService fakeService,
  required Uint8List dek,
  required VoidCallback onEnrolled,
  required VoidCallback onSkipped,
}) {
  return ProviderScope(
    overrides: [
      biometricServiceProvider.overrideWithValue(fakeService),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: BiometricSetupStep(
          dekBytes: dek,
          onEnrolled: onEnrolled,
          onSkipped: onSkipped,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final dek = Uint8List.fromList(List.generate(32, (i) => i));

  testWidgets('renders Enable and Not-now buttons when biometric available', (
    tester,
  ) async {
    final fake = _FakeBiometricService(available: true);

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        dek: dek,
        onEnrolled: () {},
        onSkipped: () {},
      ),
    );

    // Allow the post-frame isAvailable check to complete.
    await tester.pump();

    expect(find.text('Enable biometrics'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('auto-calls onSkipped when biometric unavailable', (
    tester,
  ) async {
    final fake = _FakeBiometricService(available: false);
    var skipped = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        dek: dek,
        onEnrolled: () {},
        onSkipped: () => skipped = true,
      ),
    );

    // Post-frame callback fires, then async isAvailable resolves.
    await tester.pump();
    await tester.pump();

    expect(skipped, isTrue);
  });

  testWidgets('Enable button calls enroll then onEnrolled', (tester) async {
    final fake = _FakeBiometricService(available: true);
    var enrolled = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        dek: dek,
        onEnrolled: () => enrolled = true,
        onSkipped: () {},
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Enable biometrics'));
    await tester.pump();

    expect(fake.enrollCalled, isTrue);
    expect(enrolled, isTrue);
  });

  testWidgets('Not-now button calls onSkipped', (tester) async {
    final fake = _FakeBiometricService(available: true);
    var skipped = false;

    await tester.pumpWidget(
      _buildStep(
        fakeService: fake,
        dek: dek,
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
