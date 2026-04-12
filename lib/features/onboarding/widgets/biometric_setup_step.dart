import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that offers Face ID / Touch ID enrollment.
///
/// If biometrics are not available on this device, automatically calls
/// [onSkipped] so the user isn't shown a step that can't succeed.
///
/// When biometrics are available, the user can enroll or skip.
/// [onEnrolled] is called after a successful biometric prompt.
/// [onSkipped] is called if the user chooses to skip.
class BiometricSetupStep extends ConsumerStatefulWidget {
  const BiometricSetupStep({
    super.key,
    required this.dekBytes,
    required this.onEnrolled,
    required this.onSkipped,
  });

  /// The raw DEK bytes — passed from OnboardingState where they were
  /// stored after initialize(). Reserved for future use (e.g. biometric-
  /// protected DEK storage). Not used directly in this implementation since
  /// we use PinLockService for biometric gating.
  final Uint8List? dekBytes;

  /// Called after biometric enrollment succeeds.
  final VoidCallback onEnrolled;

  /// Called when the user taps "Skip" or biometrics are unavailable.
  final VoidCallback onSkipped;

  @override
  ConsumerState<BiometricSetupStep> createState() => _BiometricSetupStepState();
}

class _BiometricSetupStepState extends ConsumerState<BiometricSetupStep> {
  bool _isEnrolling = false;
  bool _hasCheckedAvailability = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAutoSkipIfUnavailable();
    });
  }

  Future<void> _checkAndAutoSkipIfUnavailable() async {
    final service = ref.read(pinLockServiceProvider);
    final available = await service.isBiometricAvailable();
    if (!mounted) return;
    setState(() => _hasCheckedAvailability = true);
    if (!available) {
      widget.onSkipped();
    }
  }

  Future<void> _enroll() async {
    setState(() => _isEnrolling = true);
    try {
      final service = ref.read(pinLockServiceProvider);
      final success = await service.authenticateBiometric();
      if (!mounted) return;
      if (success) {
        widget.onEnrolled();
      } else {
        setState(() => _isEnrolling = false);
        // User cancelled or failed — let them try again or skip
      }
    } catch (_) {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final biometricAsync = ref.watch(isBiometricAvailableProvider);
    final biometricAvailable = biometricAsync.value ?? false;

    if (!_hasCheckedAvailability || !biometricAvailable) {
      return const Center(child: CircularProgressIndicator());
    }

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.fingerprint,
                size: 72,
                color: accentColor,
              ),
              const SizedBox(height: 24),
              Text(
                'Unlock with biometrics',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Use Face ID or Touch ID to unlock Prism quickly, '
                'without entering your PIN every time.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              PrismButton(
                label: 'Enable biometrics',
                onPressed: _enroll,
                enabled: !_isEnrolling,
                isLoading: _isEnrolling,
                expanded: true,
              ),
              const SizedBox(height: 12),
              PrismButton(
                label: 'Skip for now',
                tone: PrismButtonTone.subtle,
                onPressed: widget.onSkipped,
                enabled: !_isEnrolling,
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
