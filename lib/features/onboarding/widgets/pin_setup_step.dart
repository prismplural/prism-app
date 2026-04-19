import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';

/// Onboarding step that collects and confirms a new 6-digit PIN, then stores it
/// for app lock.
///
/// Phase 1: [PinInputMode.set] — captures the PIN via [PinInputScreen.onPinEntered].
/// Phase 2: [PinInputMode.confirm] — verifies the PIN matches, then calls both
/// [PinLockService.storePin] and [onPinConfirmed].
class PinSetupStep extends ConsumerStatefulWidget {
  const PinSetupStep({super.key, required this.onPinConfirmed});

  /// Called with the confirmed PIN after it has been stored for app lock.
  final FutureOr<void> Function(String pin) onPinConfirmed;

  @override
  ConsumerState<PinSetupStep> createState() => _PinSetupStepState();
}

class _PinSetupStepState extends ConsumerState<PinSetupStep> {
  /// The PIN captured in phase 1; null means we are still in phase 1.
  String? _phase1Pin;

  @override
  Widget build(BuildContext context) {
    final phase1Pin = _phase1Pin;

    if (phase1Pin == null) {
      // Phase 1: set mode — capture the entered PIN.
      return PinInputScreen(
        key: const ValueKey('pin-setup-set'),
        mode: PinInputMode.set,
        embedded: true,
        onPinEntered: (pin) {
          setState(() => _phase1Pin = pin);
        },
        onSuccess: () {
          // onPinEntered fires before onSuccess; the setState above has already
          // been called, so this is intentionally a no-op.
        },
      );
    }

    // Phase 2: confirm mode — verify the re-entered PIN matches phase 1.
    return PinInputScreen(
      key: const ValueKey('pin-setup-confirm'),
      mode: PinInputMode.confirm,
      embedded: true,
      pinToConfirm: phase1Pin,
      onPinEntered: (pin) async {
        // Store the PIN for app lock, then notify the caller. If key setup
        // fails after the PIN is written, remove the partially-installed app
        // lock so a retry starts from a consistent state.
        final service = ref.read(pinLockServiceProvider);
        try {
          await service.storePin(pin);
          await widget.onPinConfirmed(pin);
        } catch (_) {
          await service.clearPin();
          rethrow;
        }
      },
      onSuccess: () {
        // onPinEntered handles persistence; nothing else needed here.
      },
    );
  }
}
