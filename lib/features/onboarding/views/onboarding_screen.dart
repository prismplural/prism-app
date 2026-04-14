import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/welcome_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/system_name_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/add_members_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/features_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/chat_setup_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/preferences_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/permissions_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/features/onboarding/widgets/whos_fronting_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/complete_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/pin_setup_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/recovery_phrase_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/confirm_phrase_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/biometric_setup_step.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';
import 'package:prism_plurality/features/onboarding/utils/onboarding_step_l10n.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _isCompleting = false;

  /// Steps that have progress capsules (all except complete and full-screen steps).
  static const _progressSteps = [
    OnboardingStep.welcome,
    OnboardingStep.pinSetup,
    OnboardingStep.recoveryPhrase,
    OnboardingStep.confirmPhrase,
    OnboardingStep.biometricSetup,
    OnboardingStep.importData,
    OnboardingStep.systemName,
    OnboardingStep.addMembers,
    OnboardingStep.features,
    OnboardingStep.chatSetup,
    OnboardingStep.preferences,
    OnboardingStep.permissions,
    OnboardingStep.whosFronting,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final step = onboarding.currentStep;
    final isFirstStep = step == OnboardingStep.welcome;
    final isCompleteStep = step == OnboardingStep.complete;
    final isFullScreenStep =
        step == OnboardingStep.syncDevice ||
        step == OnboardingStep.importedDataReady ||
        step == OnboardingStep.pinSetup ||
        step == OnboardingStep.recoveryPhrase ||
        step == OnboardingStep.confirmPhrase ||
        step == OnboardingStep.biometricSetup;

    // Check if user has existing data (re-running onboarding)
    final hasExistingData = ref.watch(hasCompletedOnboardingProvider);

    return PopScope(
      canPop: hasExistingData,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isFirstStep && !isFullScreenStep) {
          notifier.back();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Background color
            Container(color: isDark ? AppColors.charcoal : AppColors.parchment),
            // Ambient glow
            Positioned(
              top: -100,
              left: 0,
              right: 0,
              child: Container(
                height: 500,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.2,
                    colors: [
                      AppColors.prismPurple.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Noise texture overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: const AssetImage(
                        'assets/textures/noise_64x64.png',
                      ),
                      repeat: ImageRepeat.repeat,
                      opacity: isDark ? 0.06 : 0.03,
                    ),
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
              child: Column(
                children: [
                  // Top bar with close button and progress
                  if (!isFullScreenStep)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          if (hasExistingData)
                            PrismInlineIconButton(
                              onPressed: () => context.go(AppRoutePaths.home),
                              icon: AppIcons.close,
                              color: isDark
                                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                                  : AppColors.warmBlack.withValues(alpha: 0.8),
                              tooltip: context.l10n.onboardingCloseOnboarding,
                            )
                          else
                            const SizedBox(width: 48),
                          Expanded(
                            child: _ProgressIndicator(
                              steps: _progressSteps,
                              currentStep: step,
                              isDark: isDark,
                              primary: primary,
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),

                  // Step header
                  if (!isCompleteStep && !isFullScreenStep) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: PhosphorIcon(
                          step.icon as PhosphorIconData,
                          size: 28,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.localizedTitle(context),
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                            fontSize: 28,
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.warmBlack,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.localizedSubtitle(context),
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark
                            ? AppColors.mutedTextDark
                            : AppColors.mutedTextLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Step content
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildStepContent(onboarding),
                    ),
                  ),

                  // Navigation buttons (hidden during sync device flow)
                  if (!isFullScreenStep)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          if (!isFirstStep)
                            _CircleButton(
                              icon: AppIcons.arrowBack,
                              onPressed: notifier.back,
                              isDark: isDark,
                            ),
                          const Spacer(),
                          _PillButton(
                            label: isCompleteStep
                                ? context.l10n.onboardingGetStarted
                                : isFirstStep
                                ? context.l10n.onboardingGetStarted
                                : context.l10n.onboardingContinue,
                            enabled: notifier.canProceed && !_isCompleting,
                            isLoading: _isCompleting,
                            isDark: isDark,
                            primary: primary,
                            onPressed: () {
                              if (isCompleteStep) {
                                _completeOnboarding();
                              } else {
                                notifier.next();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(OnboardingState onboarding) {
    final step = onboarding.currentStep;
    final n = ref.read(onboardingProvider.notifier);
    return switch (step) {
      OnboardingStep.welcome => const WelcomeStep(key: ValueKey('welcome')),
      OnboardingStep.pinSetup => PinSetupStep(
        key: const ValueKey('pin-setup'),
        onPinConfirmed: n.onPinConfirmed,
      ),
      OnboardingStep.recoveryPhrase => RecoveryPhraseStep(
        key: const ValueKey('recovery-phrase'),
        words: onboarding.mnemonicWords,
        onContinue: n.onPhraseViewed,
      ),
      OnboardingStep.confirmPhrase => ConfirmPhraseStep(
        key: const ValueKey('confirm-phrase'),
        words: onboarding.mnemonicWords,
        onConfirmed: n.onPhraseConfirmed,
      ),
      OnboardingStep.biometricSetup => BiometricSetupStep(
        key: const ValueKey('biometric-setup'),
        dekBytes: onboarding.dekBytes,
        onEnrolled: n.onBiometricEnrolled,
        onSkipped: n.onBiometricSkipped,
      ),
      OnboardingStep.syncDevice => SyncDeviceStep(
        key: const ValueKey('sync-device'),
        onBack: () {
          final n = ref.read(onboardingProvider.notifier);
          n.leaveSyncDeviceFlow();
        },
        onComplete: () => context.go(AppRoutePaths.home),
      ),
      OnboardingStep.importedDataReady => OnboardingDataReadyView(
        key: const ValueKey('imported-data-ready'),
        title: context.l10n.onboardingImportCompleteTitle,
        description: context.l10n.onboardingImportCompleteDescription,
        summaryLabel: context.l10n.onboardingImportedDataLabel,
        counts: onboarding.importedDataCounts,
        actionLabel: context.l10n.onboardingGetStarted,
        onAction: () async {
          try {
            await ref
                .read(onboardingCommitServiceProvider)
                .completeImportedBootstrap();
            if (!mounted) return;
            context.go(AppRoutePaths.home);
          } catch (e) {
            if (!mounted) return;
            PrismToast.error(context, message: context.l10n.onboardingErrorCompletingSetup(e));
          }
        },
      ),
      OnboardingStep.importData => const ImportDataStep(
        key: ValueKey('import'),
      ),
      OnboardingStep.systemName => const SystemNameStep(key: ValueKey('name')),
      OnboardingStep.addMembers => const AddMembersStep(
        key: ValueKey('members'),
      ),
      OnboardingStep.features => const FeaturesStep(key: ValueKey('features')),
      OnboardingStep.chatSetup => const ChatSetupStep(key: ValueKey('chat')),
      OnboardingStep.preferences => const PreferencesStep(
        key: ValueKey('prefs'),
      ),
      OnboardingStep.permissions => const PermissionsStep(
        key: ValueKey('permissions'),
      ),
      OnboardingStep.whosFronting => const WhosFrontingStep(
        key: ValueKey('fronting'),
      ),
      OnboardingStep.complete => const CompleteStep(key: ValueKey('complete')),
    };
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    try {
      final onboarding = ref.read(onboardingProvider);
      await ref.read(onboardingCommitServiceProvider).complete(onboarding);

      if (mounted) {
        context.go(AppRoutePaths.home);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.onboardingErrorCompletingSetup(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }
}

/// Progress capsule indicators.
class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.steps,
    required this.currentStep,
    required this.isDark,
    required this.primary,
  });

  final List<OnboardingStep> steps;
  final OnboardingStep currentStep;
  final bool isDark;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final currentIndex = steps.indexOf(currentStep);

    return Semantics(
      label: context.l10n.onboardingProgressStep(currentIndex + 1, steps.length),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length, (index) {
          final isCurrent = index == currentIndex;
          final isPast = index < currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 4,
            width: isCurrent ? 24 : 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: isCurrent
                  ? primary
                  : isPast
                  ? primary.withValues(alpha: 0.5)
                  : primary.withValues(alpha: 0.2),
            ),
          );
        }),
      ),
    );
  }
}

/// Circle back button with press feedback.
class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final normalBg = widget.isDark
        ? AppColors.warmWhite.withValues(alpha: 0.15)
        : AppColors.warmBlack.withValues(alpha: 0.08);
    final pressedBg = widget.isDark
        ? AppColors.warmWhite.withValues(alpha: 0.3)
        : AppColors.warmBlack.withValues(alpha: 0.23);
    final iconColor = widget.isDark ? AppColors.warmWhite : AppColors.warmBlack;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? pressedBg : normalBg,
          ),
          child: Icon(widget.icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

/// Pill-shaped continue/get-started button with press feedback.
class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    required this.isDark,
    required this.primary,
    this.isLoading = false,
  });

  final String label;
  final bool enabled;
  final bool isLoading;
  final bool isDark;
  final Color primary;
  final VoidCallback onPressed;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final canPress = widget.enabled && !widget.isLoading;

    return GestureDetector(
      onTapDown: canPress ? (_) => setState(() => _pressed = true) : null,
      onTapUp: canPress
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: _pressed
                ? widget.primary.withValues(alpha: 0.8)
                : canPress
                ? widget.primary
                : widget.primary.withValues(alpha: 0.3),
            border: Border.all(
              color: widget.primary.withValues(alpha: canPress ? 0.5 : 0.2),
            ),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.warmBlack,
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: canPress
                        ? AppColors.warmBlack
                        : AppColors.warmBlack.withValues(alpha: 0.4),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
