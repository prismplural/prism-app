import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/features/onboarding/widgets/pin_setup_step.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// A fake [PinLockService] that records [storePin] calls without touching
/// platform secure storage.
class _FakePinLockService extends PinLockService {
  String? storedPin;

  @override
  Future<void> storePin(String pin) async {
    storedPin = pin;
  }

  @override
  Future<void> clearPin() async {
    storedPin = null;
  }

  @override
  Future<bool> isPinSet() async => storedPin != null;

  @override
  Future<bool> isBiometricAvailable() async => false;
}

Widget _buildWidget({
  required _FakePinLockService service,
  required FutureOr<void> Function(String) onPinConfirmed,
}) {
  return ProviderScope(
    overrides: [
      pinLockServiceProvider.overrideWithValue(service),
      isBiometricAvailableProvider.overrideWith((_) async => false),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: Scaffold(body: PinSetupStep(onPinConfirmed: onPinConfirmed)),
    ),
  );
}

/// Taps the numpad digits in [pin] on the currently displayed [PinInputScreen].
Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).first);
    await tester.pump();
  }
}

/// Finds the [PinInputScreen] and returns its mode.
PinInputMode _currentMode(WidgetTester tester) {
  final widget = tester.widget<PinInputScreen>(find.byType(PinInputScreen));
  return widget.mode;
}

void main() {
  tearDown(PrismToast.resetForTest);

  testWidgets('shows PinInputScreen in set mode initially', (tester) async {
    final service = _FakePinLockService();

    await tester.pumpWidget(
      _buildWidget(service: service, onPinConfirmed: (_) {}),
    );
    await tester.pump();

    expect(find.byType(PinInputScreen), findsOneWidget);
    expect(_currentMode(tester), PinInputMode.set);
    expect(find.text('Set PIN'), findsOneWidget);
    expect(find.text('Choose a 6-digit PIN'), findsOneWidget);
  });

  testWidgets('advances to confirm phase after pin entry', (tester) async {
    final service = _FakePinLockService();

    await tester.pumpWidget(
      _buildWidget(service: service, onPinConfirmed: (_) {}),
    );
    await tester.pump();

    expect(_currentMode(tester), PinInputMode.set);

    // Enter a 6-digit PIN on phase 1.
    await _enterPin(tester, '123456');
    await tester.pumpAndSettle();

    // PinSetupStep should now show the confirm screen.
    expect(_currentMode(tester), PinInputMode.confirm);
    expect(find.text('Confirm PIN'), findsOneWidget);
    expect(find.text('Re-enter your PIN to confirm'), findsOneWidget);
  });

  testWidgets('calls onPinConfirmed and storePin on match', (tester) async {
    final service = _FakePinLockService();
    String? confirmedPin;

    await tester.pumpWidget(
      _buildWidget(
        service: service,
        onPinConfirmed: (pin) => confirmedPin = pin,
      ),
    );
    await tester.pump();

    // Phase 1: enter the PIN.
    await _enterPin(tester, '654321');
    await tester.pumpAndSettle();

    expect(_currentMode(tester), PinInputMode.confirm);

    // Phase 2: confirm the same PIN.
    await _enterPin(tester, '654321');
    await tester.pumpAndSettle();

    expect(confirmedPin, '654321');
    expect(service.storedPin, '654321');
  });

  testWidgets('clears stored pin if onboarding key setup fails', (
    tester,
  ) async {
    final service = _FakePinLockService();

    await tester.pumpWidget(
      _buildWidget(
        service: service,
        onPinConfirmed: (_) async {
          throw StateError('key setup failed');
        },
      ),
    );
    await tester.pump();

    await _enterPin(tester, '123456');
    await tester.pumpAndSettle();
    await _enterPin(tester, '123456');
    await tester.pumpAndSettle();

    expect(service.storedPin, isNull);
    expect(_currentMode(tester), PinInputMode.confirm);
    expect(find.textContaining('Error completing setup'), findsOneWidget);
    PrismToast.resetForTest();
  });
}
