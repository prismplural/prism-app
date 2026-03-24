import 'package:flutter/material.dart';
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
import 'package:prism_plurality/features/onboarding/widgets/whos_fronting_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/complete_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _isCompleting = false;

  /// Steps that have progress capsules (all except complete).
  static const _progressSteps = [
    OnboardingStep.welcome,
    OnboardingStep.importData,
    OnboardingStep.systemName,
    OnboardingStep.addMembers,
    OnboardingStep.features,
    OnboardingStep.chatSetup,
    OnboardingStep.preferences,
    OnboardingStep.whosFronting,
  ];

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final step = onboarding.currentStep;
    final isFirstStep = step == OnboardingStep.welcome;
    final isCompleteStep = step == OnboardingStep.complete;
    final isSyncDeviceStep = step == OnboardingStep.syncDevice;

    // Check if user has existing data (re-running onboarding)
    final hasExistingData = ref.watch(hasCompletedOnboardingProvider);

    return PopScope(
      canPop: hasExistingData,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isFirstStep && !isSyncDeviceStep) {
          notifier.back();
        }
      },
      child: Scaffold(
        body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              ...step.gradientColors,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with close button and progress
              if (!isSyncDeviceStep)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      if (hasExistingData)
                        IconButton(
                          onPressed: () => context.go(AppRoutePaths.home),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        )
                      else
                        const SizedBox(width: 48),
                      Expanded(
                        child: _ProgressIndicator(
                          steps: _progressSteps,
                          currentStep: step,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

              // Step header
              if (!isCompleteStep && !isSyncDeviceStep) ...[
                const SizedBox(height: 8),
                Icon(step.icon, size: 40, color: step.iconColor),
                const SizedBox(height: 12),
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.subtitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],

              // Step content
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildStepContent(step),
                ),
              ),

              // Navigation buttons (hidden during sync device flow)
              if (!isSyncDeviceStep)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    if (!isFirstStep)
                      _CircleButton(
                        icon: Icons.arrow_back,
                        onPressed: notifier.back,
                      ),
                    const Spacer(),
                    _PillButton(
                      label: isCompleteStep
                          ? 'Get Started'
                          : isFirstStep
                              ? 'Get Started'
                              : 'Continue',
                      enabled: notifier.canProceed && !_isCompleting,
                      isLoading: _isCompleting,
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
      ),
    ),
    );
  }

  Widget _buildStepContent(OnboardingStep step) {
    return switch (step) {
      OnboardingStep.welcome => const WelcomeStep(key: ValueKey('welcome')),
      OnboardingStep.syncDevice => SyncDeviceStep(
          key: const ValueKey('sync-device'),
          onBack: () {
            final n = ref.read(onboardingProvider.notifier);
            n.leaveSyncDeviceFlow();
          },
          onComplete: () => context.go(AppRoutePaths.home),
        ),
      OnboardingStep.importData =>
        const ImportDataStep(key: ValueKey('import')),
      OnboardingStep.systemName =>
        const SystemNameStep(key: ValueKey('name')),
      OnboardingStep.addMembers =>
        const AddMembersStep(key: ValueKey('members')),
      OnboardingStep.features =>
        const FeaturesStep(key: ValueKey('features')),
      OnboardingStep.chatSetup =>
        const ChatSetupStep(key: ValueKey('chat')),
      OnboardingStep.preferences =>
        const PreferencesStep(key: ValueKey('prefs')),
      OnboardingStep.whosFronting =>
        const WhosFrontingStep(key: ValueKey('fronting')),
      OnboardingStep.complete =>
        const CompleteStep(key: ValueKey('complete')),
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
        PrismToast.error(context, message: 'Error completing setup: $e');
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
  });

  final List<OnboardingStep> steps;
  final OnboardingStep currentStep;

  @override
  Widget build(BuildContext context) {
    final currentIndex = steps.indexOf(currentStep);

    return Row(
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
                ? Colors.white
                : isPast
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.2),
          ),
        );
      }),
    );
  }
}

/// Circle back button with press feedback.
class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
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
            color: _pressed
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.15),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 22),
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
    this.isLoading = false,
  });

  final String label;
  final bool enabled;
  final bool isLoading;
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
                ? Colors.white.withValues(alpha: 0.35)
                : canPress
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: canPress
                  ? Colors.white.withValues(alpha: _pressed ? 0.5 : 0.3)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: canPress
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
