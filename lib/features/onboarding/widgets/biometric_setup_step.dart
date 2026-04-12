<<<<<<< HEAD
import 'dart:io';
=======
>>>>>>> worktree-agent-a6254940
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< HEAD
import 'package:prism_plurality/core/services/biometric_service_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that offers optional biometric (Face ID / Touch ID /
/// fingerprint) enrollment.
///
/// If biometrics are unavailable on this device, [onSkipped] is called
/// automatically after the first frame via a post-frame callback so the
/// onboarding flow can advance without the user seeing the step at all.
=======
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
>>>>>>> worktree-agent-a6254940
class BiometricSetupStep extends ConsumerStatefulWidget {
  const BiometricSetupStep({
    super.key,
    required this.dekBytes,
    required this.onEnrolled,
    required this.onSkipped,
  });

<<<<<<< HEAD
  /// The raw Data Encryption Key bytes to store in the biometric keychain.
  final Uint8List dekBytes;

  /// Called after the DEK has been successfully enrolled.
  final VoidCallback onEnrolled;

  /// Called when the user taps "Not now", or when biometrics are unavailable.
=======
  /// The raw DEK bytes — passed from OnboardingState where they were
  /// stored after initialize(). Reserved for future use (e.g. biometric-
  /// protected DEK storage). Not used directly in this implementation since
  /// we use PinLockService for biometric gating.
  final Uint8List? dekBytes;

  /// Called after biometric enrollment succeeds.
  final VoidCallback onEnrolled;

  /// Called when the user taps "Skip" or biometrics are unavailable.
>>>>>>> worktree-agent-a6254940
  final VoidCallback onSkipped;

  @override
  ConsumerState<BiometricSetupStep> createState() => _BiometricSetupStepState();
}

class _BiometricSetupStepState extends ConsumerState<BiometricSetupStep> {
<<<<<<< HEAD
  bool _isLoading = false;
=======
  bool _isEnrolling = false;
  bool _hasCheckedAvailability = false;
>>>>>>> worktree-agent-a6254940

  @override
  void initState() {
    super.initState();
<<<<<<< HEAD
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final service = ref.read(biometricServiceProvider);
      final available = await service.isAvailable();
      if (!mounted) return;
      if (!available) {
        widget.onSkipped();
      }
    });
  }

  Future<void> _enroll() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(biometricServiceProvider);
      await service.enroll(widget.dekBytes);
      if (mounted) widget.onEnrolled();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData get _platformIcon {
    if (Platform.isIOS) {
      // Face-capable iPhones: X and later.
      // There is no public API to distinguish Face ID from Touch ID at Dart
      // level without calling local_auth, so we use the face icon as default
      // for iOS (covers the majority of modern devices) and fingerprint for
      // older ones. A full implementation would read available biometrics from
      // LocalAuthentication, but that requires an extra async call — the
      // simple approach is sufficient for onboarding UI.
      return Icons.face_retouching_natural;
    }
    return Icons.fingerprint;
=======
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
>>>>>>> worktree-agent-a6254940
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
<<<<<<< HEAD
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Platform biometric icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.12),
            ),
            child: Icon(
              _platformIcon,
              size: 40,
              color: primary,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Use biometrics to unlock Prism',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Your encryption key will be protected by Face ID or Touch ID so '
            'only you can unlock Prism.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.mutedTextDark : AppColors.mutedTextLight,
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: PrismButton(
              label: 'Enable biometrics',
              onPressed: _enroll,
              tone: PrismButtonTone.filled,
              isLoading: _isLoading,
              expanded: true,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: PrismButton(
              label: 'Not now',
              onPressed: widget.onSkipped,
              tone: PrismButtonTone.subtle,
              expanded: true,
            ),
          ),
        ],
=======
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
>>>>>>> worktree-agent-a6254940
      ),
    );
  }
}
