import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/welcome_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/system_name_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/terminology_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/add_members_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/features_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/navigation_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/fronting_defaults_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/chat_setup_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/appearance_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/permissions_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/features/onboarding/widgets/whos_fronting_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/complete_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/pin_setup_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/recovery_phrase_onboarding_step.dart';
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
  static const _prismLogoAsset = 'assets/icon_layers/Prism-Logo-Foreground.png';

  bool _isCompleting = false;
  bool _replacePairingRedirectScheduled = false;

  /// Steps that have progress capsules (all except complete and full-screen steps).
  static const _progressSteps = [
    OnboardingStep.welcome,
    OnboardingStep.pinSetup,
    OnboardingStep.recoveryPhrase,
    OnboardingStep.biometricSetup,
    OnboardingStep.importData,
    OnboardingStep.systemName,
    OnboardingStep.terminology,
    OnboardingStep.addMembers,
    OnboardingStep.features,
    OnboardingStep.navigation,
    OnboardingStep.frontingDefaults,
    OnboardingStep.chatSetup,
    OnboardingStep.appearance,
    OnboardingStep.permissions,
    OnboardingStep.whosFronting,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = colorScheme.primary;
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final step = onboarding.currentStep;
    final isFirstStep = step == OnboardingStep.welcome;
    final isCompleteStep = step == OnboardingStep.complete;
    final isFullScreenStep =
        step == OnboardingStep.syncDevice ||
        step == OnboardingStep.importedDataReady ||
        step == OnboardingStep.biometricSetup;
    // Self-managed steps show the top bar/header but hide bottom nav and
    // block back navigation (they have their own Continue buttons).
    final isSelfManagedStep =
        step == OnboardingStep.pinSetup ||
        step == OnboardingStep.recoveryPhrase;

    final hasExistingData = ref.watch(hasCompletedOnboardingProvider);
    final disconnectMarker = ref
        .watch(syncDisconnectMarkerProvider)
        .whenOrNull(data: (marker) => marker);
    if (step == OnboardingStep.syncDevice) {
      _replacePairingRedirectScheduled = false;
    }
    if (!_replacePairingRedirectScheduled &&
        !hasExistingData &&
        disconnectMarker?.nextSetupConstraint ==
            SyncSetupConstraint.joinOnlyReplaceLocalData &&
        step != OnboardingStep.syncDevice) {
      _replacePairingRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(onboardingProvider.notifier).enterSyncDeviceFlowFromWelcome();
      });
    }

    return PopScope(
      canPop: hasExistingData,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          notifier.clearAppearancePreview();
          return;
        }
        if (!didPop &&
            !isFirstStep &&
            !isFullScreenStep &&
            !isSelfManagedStep) {
          notifier.back();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Container(color: colorScheme.surface),
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
                      colorScheme.primary.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
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
            SafeArea(
              child: Column(
                children: [
                  if (!isFullScreenStep && !isCompleteStep)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          if (hasExistingData)
                            PrismInlineIconButton(
                              onPressed: () {
                                notifier.clearAppearancePreview();
                                context.go(AppRoutePaths.home);
                              },
                              icon: AppIcons.close,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
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

                  if (!isCompleteStep && !isFullScreenStep) ...[
                    const SizedBox(height: 8),
                    if (step == OnboardingStep.welcome)
                      ClipOval(
                        child: Image.asset(
                          _prismLogoAsset,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        step.localizedTitle(context),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontSize: 28,
                              color: colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (step.localizedSubtitle(context)
                        case final subtitle?) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildStepContent(onboarding),
                    ),
                  ),

                  if (!isFullScreenStep && !isSelfManagedStep)
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
                            primary: primary,
                            onPressed: () {
                              if (isCompleteStep) {
                                _completeOnboarding();
                                return;
                              }
                              // If an import sub-flow has registered a
                              // pending action, run it instead of silently
                              // skipping past the inline import UI.
                              final pending = ref.read(
                                onboardingPendingImportActionProvider,
                              );
                              if (pending != null) {
                                pending();
                                return;
                              }
                              notifier.next();
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
      OnboardingStep.welcome => WelcomeStep(
        key: const ValueKey('welcome'),
        onSyncDevice: n.enterSyncDeviceFlowFromWelcome,
      ),
      OnboardingStep.pinSetup => PinSetupStep(
        key: const ValueKey('pin-setup'),
        onPinConfirmed: n.onPinConfirmed,
      ),
      OnboardingStep.recoveryPhrase => RecoveryPhraseOnboardingStep(
        key: const ValueKey('recovery-phrase'),
        words: onboarding.mnemonicWords,
        onContinue: n.onPhraseSaved,
      ),
      OnboardingStep.biometricSetup => BiometricSetupStep(
        key: const ValueKey('biometric-setup'),
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
            PrismToast.error(
              context,
              message: context.l10n.onboardingErrorCompletingSetup(e),
            );
          }
        },
      ),
      OnboardingStep.importData => const ImportDataStep(
        key: ValueKey('import'),
      ),
      OnboardingStep.systemName => const SystemNameStep(key: ValueKey('name')),
      OnboardingStep.terminology => const TerminologyStep(
        key: ValueKey('terminology'),
      ),
      OnboardingStep.addMembers => const AddMembersStep(
        key: ValueKey('members'),
      ),
      OnboardingStep.features => const FeaturesStep(key: ValueKey('features')),
      OnboardingStep.navigation => const NavigationStep(
        key: ValueKey('navigation'),
      ),
      OnboardingStep.frontingDefaults => const FrontingDefaultsStep(
        key: ValueKey('fronting-defaults'),
      ),
      OnboardingStep.chatSetup => const ChatSetupStep(key: ValueKey('chat')),
      OnboardingStep.appearance => const AppearanceStep(
        key: ValueKey('appearance'),
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
        ref.read(onboardingProvider.notifier).clearAppearancePreview();
        context.go(AppRoutePaths.home);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.onboardingErrorCompletingSetup(e),
        );
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
      label: context.l10n.onboardingProgressStep(
        currentIndex + 1,
        steps.length,
      ),
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
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(2),
              ),
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
  const _CircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalBg = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: 0.08),
      colorScheme.surface,
    );
    final pressedBg = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: 0.18),
      colorScheme.surface,
    );
    final iconColor = colorScheme.onSurface;

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
    required this.primary,
    this.isLoading = false,
  });

  final String label;
  final bool enabled;
  final bool isLoading;
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
    final colorScheme = Theme.of(context).colorScheme;
    final fillColor = _pressed
        ? widget.primary.withValues(alpha: 0.8)
        : canPress
        ? widget.primary
        : widget.primary.withValues(alpha: 0.3);
    final renderedFillColor = Color.alphaBlend(fillColor, colorScheme.surface);
    final foreground = highContrastForeground(renderedFillColor);
    final contentColor = canPress
        ? foreground
        : foreground.withValues(alpha: 0.82);

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
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(28),
            ),
            color: fillColor,
            border: Border.all(
              color: widget.primary.withValues(alpha: canPress ? 0.5 : 0.2),
            ),
          ),
          child: widget.isLoading
              ? PrismSpinner(color: contentColor, size: 20)
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
