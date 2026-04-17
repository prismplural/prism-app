import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/features/onboarding/widgets/prism_shimmer_bar.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// Top-level Consumer widget that composes the sync-pairing progress UI.
///
/// Renders [PhaseSegments], either [PrismSpinner] or [PrismShimmerBar]
/// depending on the current phase, a [LiveCountCard], phase titles/subtitles,
/// and reassurance copy. Fires haptic + accessibility announcements on phase
/// transitions.
class SyncProgressView extends ConsumerStatefulWidget {
  const SyncProgressView({super.key});

  @override
  ConsumerState<SyncProgressView> createState() => _SyncProgressViewState();
}

class _SyncProgressViewState extends ConsumerState<SyncProgressView> {
  Timer? _rebuildTimer;
  // Track whether we've already fired the restored-summary announcement for
  // the current phase transition so it only fires once.
  PairingProgressPhase? _lastAnnouncedPhase;

  @override
  void initState() {
    super.initState();
    _startRebuildTimer(slow: false);
  }

  void _startRebuildTimer({required bool slow}) {
    _rebuildTimer?.cancel();
    final interval =
        slow ? const Duration(seconds: 5) : const Duration(seconds: 1);
    _rebuildTimer = Timer.periodic(interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rebuildTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    // Switch to a slower rebuild cadence when reduced motion is requested.
    // This check is cheap and idempotent — only restarts the timer when
    // the interval actually needs to change.
    if (disableAnimations && (_rebuildTimer?.isActive ?? false)) {
      _startRebuildTimer(slow: true);
    }

    final state = ref.watch(syncSetupProgressProvider);

    // Listen for phase changes to fire haptics and accessibility announcements.
    ref.listen<SyncSetupProgressState>(syncSetupProgressProvider, (prev, next) {
      if (prev?.phase != next.phase) {
        // Haptic on phase change, unless reduced motion.
        if (!disableAnimations) {
          HapticFeedback.selectionClick();
        }

        // A11y: announce the new phase title.
        final phaseTitle = _phaseTitleFor(next.phase, l10n);
        SemanticsService.sendAnnouncement(
          View.of(context),
          l10n.onboardingSyncPhaseAnnouncement(phaseTitle),
          Directionality.of(context),
        );
      }

      // After a phase transition, announce the restored summary if there were
      // counts. Use a flag to ensure this fires at most once per transition.
      if (prev?.phase != next.phase &&
          prev != null &&
          _lastAnnouncedPhase != next.phase) {
        _lastAnnouncedPhase = next.phase;
        final members = prev.liveCounts['members'] ?? 0;
        final messages = prev.liveCounts['chat_messages'] ?? 0;
        if (members > 0 || messages > 0) {
          // Capture view + direction before the async gap to avoid
          // use_build_context_synchronously lint across the microtask.
          final view = View.of(context);
          final direction = Directionality.of(context);
          final summary = l10n.onboardingSyncRestoredSummary(members, messages);
          // Debounce via microtask so this fires after the phase-title
          // announcement.
          Future.microtask(() {
            SemanticsService.sendAnnouncement(view, summary, direction);
          });
        }
      }
    });

    // Resolve terminology for LiveCountCard.
    final terminologySetting = ref.watch(terminologySettingProvider);
    final terminology = terminologySetting.term;

    // Phase title and subtitle.
    final title = _phaseTitleFor(state.phase, l10n);
    final subtitle = _phaseSubtitleFor(state, l10n);

    // Reassurance: show after 30 seconds in the current phase.
    final elapsed = DateTime.now().difference(state.phaseStartedAt);
    final showReassurance = elapsed > const Duration(seconds: 30);

    final phase = state.phase;
    final showSpinner =
        phase == PairingProgressPhase.connecting ||
        phase == PairingProgressPhase.finishing;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhaseSegments(
              currentIndex: phase.index,
              totalPhases: 4,
            ),
            const SizedBox(height: 48),
            AnimatedSwitcher(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              child: showSpinner
                  ? const PrismSpinner(
                      key: ValueKey('spinner'),
                      color: AppColors.prismPurple,
                      size: 48,
                      duration: Duration(milliseconds: 2400),
                    )
                  : const PrismShimmerBar(key: ValueKey('shimmer')),
            ),
            const SizedBox(height: 32),
            Semantics(
              liveRegion: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.mutedTextDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Hero(
              tag: 'sync-progress-count-card',
              child: LiveCountCard(
                counts: state.liveCounts,
                terminology: terminology,
              ),
            ),
            const SizedBox(height: 16),
            if (showReassurance)
              Text(
                l10n.onboardingSyncReassurance,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedTextDark,
                ),
                textAlign: TextAlign.center,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  String _phaseTitleFor(PairingProgressPhase phase, AppLocalizations l10n) {
    return switch (phase) {
      PairingProgressPhase.connecting => l10n.onboardingSyncPhaseConnectTitle,
      PairingProgressPhase.downloading => l10n.onboardingSyncPhaseDownloadTitle,
      PairingProgressPhase.restoring => l10n.onboardingSyncPhaseRestoreTitle,
      PairingProgressPhase.finishing => l10n.onboardingSyncPhaseFinishTitle,
    };
  }

  String _phaseSubtitleFor(
    SyncSetupProgressState state,
    AppLocalizations l10n,
  ) {
    final phase = state.phase;

    // Disconnected during active download/restore phases.
    if (!state.wsConnected &&
        (phase == PairingProgressPhase.downloading ||
            phase == PairingProgressPhase.restoring)) {
      return l10n.onboardingSyncReconnecting;
    }

    // Timed-out during finishing phase.
    if (state.timedOut && phase == PairingProgressPhase.finishing) {
      return l10n.onboardingSyncStillPullingBackground;
    }

    // Empty system during restoring (≥2s elapsed, all counts are zero).
    if (phase == PairingProgressPhase.restoring) {
      final phaseElapsed = DateTime.now().difference(state.phaseStartedAt);
      final allZero =
          state.liveCounts.isEmpty ||
          state.liveCounts.values.every((v) => v == 0);
      if (allZero && phaseElapsed >= const Duration(seconds: 2)) {
        return l10n.onboardingSyncNoDataToRestore;
      }
    }

    // Default subtitle.
    return switch (phase) {
      PairingProgressPhase.connecting =>
        l10n.onboardingSyncPhaseConnectSubtitle,
      PairingProgressPhase.downloading =>
        l10n.onboardingSyncPhaseDownloadSubtitle,
      PairingProgressPhase.restoring => l10n.onboardingSyncPhaseRestoreSubtitle,
      PairingProgressPhase.finishing => l10n.onboardingSyncPhaseFinishSubtitle,
    };
  }
}
