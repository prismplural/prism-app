import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/router/onboarding_local_completion.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
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
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_logo_tile.dart';

// Geometry shared by the screen and its height budget. The widgets below use
// these same constants, so a measurement of the strip, the bar or the CTA can
// never drift from what is rendered.
const double kOnboardingStripVerticalPadding = 12;
const double kOnboardingStripActionSlot = 48;
const double kOnboardingStripCapsuleHeight = 4;
const double kOnboardingBarVerticalPadding = 16;
const double kOnboardingBarHorizontalPadding = 24;
const double kOnboardingBarGap = 12;
const double kCircleButtonSize = 48;
const double kPillHorizontalPadding = 32;
const double kPillVerticalPadding = 14;
const double kPillFontSize = 16;
const int kPillMaxLines = 2;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _isCompleting = false;
  bool _confirmingEmptyMembers = false;
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
    final importBusy = ref.watch(onboardingImportBusyProvider);
    final pendingFrontingTerms = resolveFrontingTerms(
      context.l10n,
      onboarding.pendingFrontingTerms,
    );
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

    // Layout policy for this flow, measured from the styles and geometry that are
    // actually rendered:
    //   * the readable minimum for the step header (its real title at its real
    //     style and width, up to two lines),
    //   * the smallest body that still shows a whole input (the name field's own
    //     style, padding and helper line),
    //   * the pinned chrome: the progress strip, and the bottom bar with the CTA's
    //     label measured at the width the pill really gets,
    //   * and whether those three fit the viewport.
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final showStrip = !isFullScreenStep && !isCompleteStep;
    final showBar = !isFullScreenStep && !isSelfManagedStep;
    final showsBack = !isFirstStep && !importBusy;
    final ctaLabel = isCompleteStep || isFirstStep
        ? context.l10n.onboardingGetStarted
        : context.l10n.onboardingContinue;
    final minimumHeaderExtent = showStrip
        ? _FlowLayoutBudget.minimumHeaderExtent(
            context,
            title: step.localizedTitle(
              context,
              frontingTerms: pendingFrontingTerms,
            ),
            titleStyle: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontSize: 28),
            availableWidth: viewportWidth,
          )
        : 0.0;
    final minimumInputExtent = _FlowLayoutBudget.minimumInputExtent(
      context,
      availableWidth: viewportWidth,
    );
    final pinnedChrome =
        (showStrip
            ? _FlowLayoutBudget.stripExtent(
                showsCloseAction: hasExistingData && !importBusy,
              )
            : 0.0) +
        (showBar
            ? _FlowLayoutBudget.barExtent(
                context,
                ctaLabel: ctaLabel,
                showsBack: showsBack,
                availableWidth: viewportWidth,
              )
            : 0.0);

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = constraints.maxHeight;
                  final tight = _FlowLayoutBudget.isTight(
                    viewportHeight: viewportHeight,
                    pinnedChrome: pinnedChrome,
                    minimumHeader: minimumHeaderExtent,
                    minimumInput: minimumInputExtent,
                  );
                  // Tight: lay the same column out taller than the viewport and
                  // let it scroll, so the header, the input and the footer are
                  // all reachable and the body keeps a whole input's height.
                  // Otherwise the column is exactly the viewport, as before, and
                  // the scroll view cannot move.
                  final flowHeight = tight && viewportHeight.isFinite
                      ? pinnedChrome +
                            minimumHeaderExtent +
                            minimumInputExtent +
                            1 // one dp of rounding slack for the text layout
                      : viewportHeight;
                  return SingleChildScrollView(
                    physics: tight
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      height: flowHeight.isFinite ? flowHeight : null,
                      child: Column(
                        children: [
                          if (!isFullScreenStep && !isCompleteStep)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: kOnboardingStripVerticalPadding,
                              ),
                              child: Row(
                                children: [
                                  if (hasExistingData && !importBusy)
                                    PrismInlineIconButton(
                                      onPressed: () {
                                        notifier.clearAppearancePreview();
                                        context.go(AppRoutePaths.home);
                                      },
                                      icon: AppIcons.close,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.8,
                                      ),
                                      tooltip: context
                                          .l10n
                                          .onboardingCloseOnboarding,
                                    )
                                  else
                                    const SizedBox(
                                      width: kOnboardingStripActionSlot,
                                    ),
                                  Expanded(
                                    child: _ProgressIndicator(
                                      steps: _progressSteps,
                                      currentStep: step,
                                      isDark: isDark,
                                      primary: primary,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: kOnboardingStripActionSlot,
                                  ),
                                ],
                              ),
                            ),

                          Expanded(
                            child: !isCompleteStep && !isFullScreenStep
                                // The step header and the step body share the space
                                // between the pinned progress strip and the pinned
                                // bottom bar. The header is a fixed block of 28pt text
                                // above a flexible body, so at large text on a compact
                                // phone it used to consume the whole viewport: the body
                                // was laid out at zero height and the Column reported a
                                // large overflow. The header now negotiates its height
                                // with this Column (see _StepHeaderBudget) and scrolls
                                // inside it, so the body always keeps a usable share and
                                // nothing is lost - the header text stays at the size the
                                // user asked for, just scrollable.
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      final headerMaxHeight =
                                          _StepHeaderBudget.headerMaxHeightFor(
                                            constraints.maxHeight,
                                            minBodyHeight: minimumInputExtent,
                                          );
                                      return Column(
                                        children: [
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxHeight: headerMaxHeight,
                                            ),
                                            child: SingleChildScrollView(
                                              child: _buildStepHeader(
                                                context: context,
                                                step: step,
                                                pendingFrontingTerms:
                                                    pendingFrontingTerms,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              child: _buildStepContent(
                                                onboarding,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  )
                                : AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: _buildStepContent(onboarding),
                                  ),
                          ),

                          if (!isFullScreenStep && !isSelfManagedStep)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: kOnboardingBarHorizontalPadding,
                                vertical: kOnboardingBarVerticalPadding,
                              ),
                              child: Row(
                                children: [
                                  if (!isFirstStep && !importBusy)
                                    _CircleButton(
                                      icon: AppIcons.arrowBack,
                                      onPressed: notifier.back,
                                    ),
                                  const SizedBox(width: kOnboardingBarGap),
                                  // The CTA takes the width left beside the Back
                                  // control so that at large text it wraps its label
                                  // inside the viewport instead of painting past the
                                  // right edge on a compact phone.
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _PillButton(
                                        label: isCompleteStep
                                            ? context.l10n.onboardingGetStarted
                                            : isFirstStep
                                            ? context.l10n.onboardingGetStarted
                                            : context.l10n.onboardingContinue,
                                        enabled:
                                            notifier.canProceed &&
                                            !_isCompleting &&
                                            !importBusy,
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
                                          // Empty is allowed but usually an accidental
                                          // skip — confirm first.
                                          if (step ==
                                              OnboardingStep.addMembers) {
                                            _confirmThenAdvance();
                                            return;
                                          }
                                          notifier.next();
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logo, title and subtitle for the current step.
  ///
  /// Pure presentation - no state, controllers or focus - so wrapping it in a
  /// scroll view cannot disturb the step body, the flow or the busy Back guard.
  Widget _buildStepHeader({
    required BuildContext context,
    required OnboardingStep step,
    required FrontingTermBundle pendingFrontingTerms,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = colorScheme.primary;
    final subtitle = step.localizedSubtitle(
      context,
      frontingTerms: pendingFrontingTerms,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        if (step == OnboardingStep.welcome)
          const PrismLogoTile(size: 56, logoSize: 56, shape: BoxShape.circle)
        else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.15),
            ),
            child: Center(
              child: PhosphorIcon(step.icon, size: 28, color: primary),
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            step.localizedTitle(context, frontingTerms: pendingFrontingTerms),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        if (subtitle != null) ...[
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
            ref.read(localOnboardingCompletionProvider.notifier).mark();
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
        ref.read(localOnboardingCompletionProvider.notifier).mark();
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

  /// Advances past the add-members step, first nudging the user if the system
  /// is still empty. Kept fire-and-forget so the tap handler stays sync.
  Future<void> _confirmThenAdvance() async {
    if (_confirmingEmptyMembers) return;
    _confirmingEmptyMembers = true;
    try {
      if (!await _confirmProceedWithoutMembers()) return;
      if (!mounted) return;
      // Re-check in case the step moved while the dialog was open.
      if (ref.read(onboardingProvider).currentStep ==
          OnboardingStep.addMembers) {
        ref.read(onboardingProvider.notifier).next();
      }
    } finally {
      _confirmingEmptyMembers = false;
    }
  }

  /// Confirms leaving the add-members step empty. An empty system is allowed,
  /// so this nudges rather than blocks.
  Future<bool> _confirmProceedWithoutMembers() async {
    final membersAsync = ref.read(userVisibleAllMemberListProvider);
    if (!membersAsync.hasValue) return false;
    final members = membersAsync.value ?? const [];
    if (members.isNotEmpty) return true;
    if (!mounted) return false;
    return PrismDialog.confirm(
      context: context,
      icon: AppIcons.duotoneMembers,
      title: context.l10n.onboardingNoMembersConfirmTitle,
      message: context.l10n.onboardingNoMembersConfirmMessage,
      confirmLabel: context.l10n.onboardingNoMembersConfirmProceed,
      cancelLabel: context.l10n.onboardingNoMembersConfirmCancel,
    );
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

    final semanticsLabel = context.l10n.onboardingProgressStep(
      currentIndex + 1,
      steps.length,
    );
    // The capsules are fixed geometry, not text, so they cannot shrink with
    // the scaler and 15 of them need 252dp (4dp margins + a double-width
    // current capsule). Inside the header slot on a 320dp phone only 184dp is
    // left, which overflowed by 68dp at *default* text. Keep the exact 24/12
    // geometry whenever it fits and scale both widths by the same factor
    // when the slot is narrower, so the strip never paints past its slot at
    // any width or text scale. The accessible step label is unaffected.
    return LayoutBuilder(
      builder: (context, constraints) {
        const idealUnitWidth = 12.0;
        const marginPerCapsule = 4.0;
        final margins = marginPerCapsule * steps.length;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : margins + idealUnitWidth * (steps.length + 1);
        final free = math.max(0.0, available - margins);
        final unitWidth = math.min(idealUnitWidth, free / (steps.length + 1));
        return Semantics(
          label: semanticsLabel,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(steps.length, (index) {
              final isCurrent = index == currentIndex;
              final isPast = index < currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(
                  horizontal: marginPerCapsule / 2,
                ),
                height: 4,
                width: unitWidth * (isCurrent ? 2 : 1),
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
      },
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
          width: kCircleButtonSize,
          height: kCircleButtonSize,
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
          padding: const EdgeInsets.symmetric(
            horizontal: kPillHorizontalPadding,
            vertical: kPillVerticalPadding,
          ),
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
                  // Same policy as PrismButton: two lines at the requested
                  // size, then ellipsis. The full label stays in semantics.
                  maxLines: kPillMaxLines,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: kPillFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Height [text] needs at [maxWidth], measured from the style the text really
/// renders with.
///
/// The explicit style is merged over the ambient `DefaultTextStyle` exactly as
/// `Text` does it, so family, weight, leading, locale and the text scaler all
/// come from the running app instead of a ratio invented here.
double _measuredTextHeight(
  BuildContext context, {
  required String text,
  required TextStyle? style,
  required double maxWidth,
  int? maxLines,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '\u2026',
    textHeightBehavior: prismTextHeightBehaviorFor(context),
  )..layout(maxWidth: math.max(0.0, maxWidth));
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Measured pieces the flow-height decision is made from.
///
/// Every number here comes from the real resolved styles and the geometry the
/// widgets render with (the same constants they use), never from a font ratio or
/// an assumed line count.
abstract final class _FlowLayoutBudget {
  /// Progress strip: its vertical padding plus the tallest thing inside it (the
  /// close action when it is shown, otherwise the capsules).
  static double stripExtent({required bool showsCloseAction}) {
    final inner = showsCloseAction
        ? kOnboardingStripActionSlot
        : kOnboardingStripCapsuleHeight;
    return 2 * kOnboardingStripVerticalPadding + inner;
  }

  /// Bottom bar: its vertical padding plus the taller of the Back circle and the
  /// CTA pill, where the pill's label is measured at the width the pill really
  /// gets, with its own style and line cap.
  static double barExtent(
    BuildContext context, {
    required String ctaLabel,
    required bool showsBack,
    required double availableWidth,
  }) {
    const barHorizontal = 2 * kOnboardingBarHorizontalPadding;
    final backExtent = showsBack ? kCircleButtonSize : 0.0;
    final pillMaxWidth = math.max(
      0.0,
      availableWidth -
          barHorizontal -
          backExtent -
          kOnboardingBarGap -
          2 * kPillHorizontalPadding,
    );
    final labelHeight = _measuredTextHeight(
      context,
      text: ctaLabel,
      style: const TextStyle(
        fontSize: kPillFontSize,
        fontWeight: FontWeight.w600,
      ),
      maxWidth: pillMaxWidth,
      maxLines: kPillMaxLines,
    );
    final pillHeight = 2 * kPillVerticalPadding + labelHeight;
    final rowHeight = math.max(showsBack ? kCircleButtonSize : 0.0, pillHeight);
    return 2 * kOnboardingBarVerticalPadding + rowHeight;
  }

  /// The header's readable minimum: the real step title at its real style and
  /// width, capped at two lines, so the header is never reduced to nothing just
  /// to grow the body.
  static double minimumHeaderExtent(
    BuildContext context, {
    required String title,
    required TextStyle? titleStyle,
    required double availableWidth,
  }) {
    return _measuredTextHeight(
      context,
      text: title,
      style: titleStyle,
      maxWidth: availableWidth - 48,
      maxLines: 2,
    );
  }

  /// The smallest body that still shows a whole input: the flow's tallest input
  /// is the system-name field, so its own style, padding and helper line are the
  /// model, measured rather than assumed.
  static double minimumInputExtent(
    BuildContext context, {
    required double availableWidth,
  }) {
    final fieldLine = _measuredTextHeight(
      context,
      text: 'Wg',
      style: SystemNameStep.fieldTextStyle(context),
      maxWidth:
          availableWidth - 2 * 32 - 2 * SystemNameStep.fieldHorizontalPadding,
      maxLines: 1,
    );
    final helperLine = _measuredTextHeight(
      context,
      text: 'Wg',
      style: SystemNameStep.helperTextStyle(context),
      maxWidth: availableWidth - 2 * 32,
      maxLines: 1,
    );
    // The field's own vertical padding plus a 1dp allowance for its rounded
    // border, then the gap and one helper line beneath it.
    return fieldLine +
        2 * SystemNameStep.fieldVerticalPadding +
        1 +
        SystemNameStep.fieldToHelperGap +
        helperLine;
  }

  /// Whether the pinned layout can still hold the header's readable minimum and
  /// a whole input between the strip and the bar.
  static bool isTight({
    required double viewportHeight,
    required double pinnedChrome,
    required double minimumHeader,
    required double minimumInput,
  }) {
    if (!viewportHeight.isFinite) return false;
    return viewportHeight < pinnedChrome + minimumHeader + minimumInput;
  }
}

/// Height negotiation between the onboarding step header and the step body.
///
/// The progress strip above them and the bottom bar below them are pinned, so
/// the header and the body split what is left. The header is fixed-size text
/// (a 28pt title plus a 15pt subtitle at the user's text scale) while the body
/// is the flexible one, so an unbounded header consumes the whole area: at
/// 3.375x on a 320x568 phone the title and subtitle alone are several hundred
/// dp, the body is laid out at zero height and the Column overflows - no step
/// control is reachable at all.
///
/// The header therefore keeps its natural height whenever that leaves the body
/// at least [minBodyHeight]; past that point the header is capped and scrolls.
/// Nothing is shrunk or hidden: the title and subtitle keep the size the user
/// asked for, they are only reachable by scrolling.
abstract final class _StepHeaderBudget {
  /// Never let the header take so much of [contentHeight] that the body would be
  /// squeezed below what a whole input needs.
  static double headerMaxHeightFor(
    double contentHeight, {
    required double minBodyHeight,
  }) {
    if (!contentHeight.isFinite) return double.infinity;
    // The body reserves exactly what a whole input needs and the header takes
    // the rest, scrolling inside it. When even that does not fit, the flow is in
    // the tight fallback and is laid out taller than the viewport on purpose, so
    // there is no case left where this would demand more than the column has.
    return math.max(0.0, contentHeight - minBodyHeight);
  }
}
