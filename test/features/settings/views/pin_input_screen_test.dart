import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Holds the biometric prompt open until the test completes [biometricGate].
class _GatedBiometricPinLockService extends PinLockService {
  final verifyCalls = <String>[];
  var biometricCalls = 0;
  final biometricGate = Completer<bool>();

  @override
  Future<bool> verifyStoredPin(String pin) async {
    verifyCalls.add(pin);
    return false;
  }

  @override
  Future<bool> authenticateBiometric() {
    biometricCalls++;
    return biometricGate.future;
  }
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).first);
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpUnlockScreen(
    WidgetTester tester, {
    required PinLockService service,
    required VoidCallback onSuccess,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(
              const SystemSettings(
                pinLockEnabled: true,
                biometricLockEnabled: true,
              ),
            ),
          ),
          isBiometricAvailableProvider.overrideWith((ref) async => true),
          pinLockServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: PinInputScreen(mode: PinInputMode.unlock, onSuccess: onSuccess),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // No pump between taps: build-time guards are still a frame stale, as with
  // taps delivered in one pointer packet.
  testWidgets('biometric prompt holds PIN entry and repeat prompts', (
    tester,
  ) async {
    final service = _GatedBiometricPinLockService();
    var successes = 0;
    await pumpUnlockScreen(
      tester,
      service: service,
      onSuccess: () => successes++,
    );

    await _enterPin(tester, '12345');
    await tester.tap(find.byIcon(AppIcons.fingerprint));
    await tester.tap(find.byIcon(AppIcons.fingerprint));
    await tester.tap(find.text('6').first);

    expect(service.biometricCalls, 1);
    expect(service.verifyCalls, isEmpty);

    service.biometricGate.complete(true);
    await tester.pumpAndSettle();

    expect(successes, 1);
    expect(service.biometricCalls, 1);
    expect(service.verifyCalls, isEmpty);
  });

  testWidgets('a declined biometric prompt re-enables PIN entry', (
    tester,
  ) async {
    final service = _GatedBiometricPinLockService();
    var successes = 0;
    await pumpUnlockScreen(
      tester,
      service: service,
      onSuccess: () => successes++,
    );

    await _enterPin(tester, '12345');
    await tester.tap(find.byIcon(AppIcons.fingerprint));
    service.biometricGate.complete(false);
    await tester.pumpAndSettle();

    await _enterPin(tester, '6');
    await tester.pumpAndSettle();

    expect(successes, 0);
    expect(service.verifyCalls, ['123456']);
  });
}
