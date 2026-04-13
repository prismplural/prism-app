import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/features/onboarding/widgets/pin_setup_step.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// A fake [PinLockService] that records [storePin] calls without touching
/// platform secure storage.
class _FakePinLockService extends PinLockService {
  String? storedPin;

  @override
  Future<void> storePin(String pin) async {
    storedPin = pin;
  }

  @override
  Future<bool> isPinSet() async => storedPin != null;

  @override
  Future<bool> isBiometricAvailable() async => false;
}

Widget _buildWidget({
  required _FakePinLockService service,
  required void Function(String) onPinConfirmed,
}) {
  return ProviderScope(
    overrides: [
      pinLockServiceProvider.overrideWithValue(service),
      isBiometricAvailableProvider.overrideWith((_) async => false),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PinSetupStep(onPinConfirmed: onPinConfirmed),
      ),
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

void main() {
  testWidgets('shows PinInputScreen in set mode initially', (tester) async {
    final service = _FakePinLockService();

    await tester.pumpWidget(
      _buildWidget(service: service, onPinConfirmed: (_) {}),
    );
    await tester.pump();

    // In set mode the title shown by PinInputScreen is 'Set PIN'.
    expect(find.text('Set PIN'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsNothing);
  });

  testWidgets('advances to confirm phase after pin entry', (tester) async {
    final service = _FakePinLockService();

    await tester.pumpWidget(
      _buildWidget(service: service, onPinConfirmed: (_) {}),
    );
    await tester.pump();

    expect(find.text('Set PIN'), findsOneWidget);

    // Enter a 6-digit PIN on phase 1.
    await _enterPin(tester, '123456');
    await tester.pumpAndSettle();

    // PinSetupStep should now show the confirm screen.
    expect(find.text('Confirm PIN'), findsOneWidget);
    expect(find.text('Set PIN'), findsNothing);
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

    expect(find.text('Confirm PIN'), findsOneWidget);

    // Phase 2: confirm the same PIN.
    await _enterPin(tester, '654321');
    await tester.pumpAndSettle();

    expect(confirmedPin, '654321');
    expect(service.storedPin, '654321');
  });
}
