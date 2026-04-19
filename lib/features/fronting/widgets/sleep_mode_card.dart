import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/fronting/widgets/wake_up_sleep_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Card shown on the fronting screen when a sleep session is active.
class SleepModeCard extends ConsumerWidget {
  const SleepModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepAsync = ref.watch(activeSleepSessionProvider);

    return sleepAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (session) {
        if (session == null) return const SizedBox.shrink();
        return _ActiveSleepCard(session: session);
      },
    );
  }
}

class _ActiveSleepCard extends ConsumerStatefulWidget {
  const _ActiveSleepCard({required this.session});

  final FrontingSession session;

  @override
  ConsumerState<_ActiveSleepCard> createState() => _ActiveSleepCardState();
}

class _ActiveSleepCardState extends ConsumerState<_ActiveSleepCard> {
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the nudge threshold once per minute so it appears while
    // the user is still on-screen (FrontingDurationText ticks itself, but
    // that rebuild is local — this card needs its own tick to flip the flag).
    _nudgeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sleepColor = AppColors.sleep(theme.brightness);

    final wakeNudgeEnabled = ref.watch(wakeSuggestionEnabledProvider);
    final wakeNudgeHours = ref.watch(wakeSuggestionAfterHoursProvider);

    final elapsed = DateTime.now().difference(widget.session.startTime);
    final showNudge =
        wakeNudgeEnabled && elapsed.inMinutes >= (wakeNudgeHours * 60).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showNudge) ...[
          Text(
            context.l10n.sleepWakeSuggestionNudge(elapsed.toRoundedString()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: sleepColor.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(20)),
            border: Border.all(color: sleepColor.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(AppIcons.bedtimeRounded, size: 24, color: sleepColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FrontingDurationText(
                      startTime: widget.session.startTime,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: sleepColor,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      context.l10n.frontingSleepingLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PrismButton(
                label: context.l10n.frontingWakeUp,
                icon: AppIcons.wbSunnyRounded,
                onPressed: () =>
                    WakeUpSleepSheet.show(context, widget.session),
                density: PrismControlDensity.compact,
                tone: PrismButtonTone.filled,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
