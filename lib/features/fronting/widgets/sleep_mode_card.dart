import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';

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

class _ActiveSleepCard extends ConsumerWidget {
  const _ActiveSleepCard({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final sleepColor = Colors.indigo.shade300;
    final quality = session.quality ?? SleepQuality.unknown;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sleepColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(AppIcons.bedtimeRounded, size: 48, color: sleepColor),
            const SizedBox(height: 8),
            Text(
              context.l10n.frontingSleepingLabel,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.frontingSleepSince(session.startTime.toTimeString()),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            FrontingDurationText(
              startTime: session.startTime,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: sleepColor,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            if (session.notes != null && session.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                session.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            _QualityRating(
              quality: quality,
              onChanged: (rating) async {
                await ref
                    .read(sleepNotifierProvider.notifier)
                    .updateSleepQuality(session.id, rating);
              },
            ),
            const SizedBox(height: 16),
            PrismButton(
              label: context.l10n.frontingWakeUp,
              icon: AppIcons.wbSunnyRounded,
              onPressed: () {
                ref.read(sleepNotifierProvider.notifier).endSleep(session.id);
              },
              density: PrismControlDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityRating extends StatelessWidget {
  const _QualityRating({required this.quality, required this.onChanged});

  final SleepQuality quality;
  final ValueChanged<SleepQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Map quality levels 1-5 (skipping unknown at index 0)
    final qualityValues = [
      SleepQuality.veryPoor,
      SleepQuality.poor,
      SleepQuality.fair,
      SleepQuality.good,
      SleepQuality.excellent,
    ];

    return Column(
      children: [
        Text(
          quality == SleepQuality.unknown
              ? context.l10n.frontingSleepQualityUnrated
              : context.l10n.frontingSleepQualityRated(quality.label),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final q = qualityValues[index];
            final isSelected =
                quality != SleepQuality.unknown && quality.index >= q.index;
            return Semantics(
              button: true,
              selected: isSelected,
              label: context.l10n.frontingRateSleepAs(q.label),
              child: PrismInlineIconButton(
                onPressed: () => onChanged(q),
                icon: isSelected
                    ? AppIcons.starRounded
                    : AppIcons.starOutlineRounded,
                color: isSelected
                    ? Colors.amber
                    : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                size: 44,
                iconSize: 28,
                tooltip: q.label,
              ),
            );
          }),
        ),
      ],
    );
  }
}
