import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

/// Side-by-side (or stacked) stats cards for last-night sleep and 7-day average.
///
/// Hidden entirely when no sleep sessions have ever been recorded. Adapts to a
/// single-column layout on widths under 328 logical pixels.
class SleepStatCards extends ConsumerWidget {
  const SleepStatCards({super.key});

  // Breakpoint: 360dp page width − 32px horizontal padding = 328dp
  static const double _rowBreakpoint = 328;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sleepStatsProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (view) {
        if (view.totalEverCount == 0) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= _rowBreakpoint;
            final lastNightCard = _LastNightCard(session: view.lastNight);
            final avg7dCard = view.lastNight != null
                ? _Avg7dCard(avg7d: view.avg7d, avg7dPrior: view.avg7dPrior)
                : null;

            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lastNightCard),
                  if (avg7dCard != null) ...[
                    const SizedBox(width: 12),
                    Expanded(child: avg7dCard),
                  ],
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                lastNightCard,
                if (avg7dCard != null) ...[
                  const SizedBox(height: 12),
                  avg7dCard,
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Last-night card
// ─────────────────────────────────────────────────────────────────────────────

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.session});

  final FrontingSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sleepColor = AppColors.sleep(theme.brightness);
    final l10n = context.l10n;

    final quality = session?.quality ?? SleepQuality.unknown;
    final durationText = session != null ? session!.duration.toRoundedString() : '—';
    final qualityLabel = quality == SleepQuality.unknown
        ? l10n.sleepQualityNotRated
        : quality.localizedLabel(l10n);

    final semanticLabel = session != null
        ? '${l10n.sleepLastNightLabel}, $durationText, $qualityLabel'
        : '${l10n.sleepLastNightLabel}, —';

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: PrismSectionCard(
        accentColor: sleepColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sleepLastNightLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: sleepColor.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              durationText,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                PhosphorIcon(
                  _qualityIcon(quality),
                  size: 16,
                  color: sleepColor,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    qualityLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PhosphorIconData _qualityIcon(SleepQuality quality) => switch (quality) {
    SleepQuality.unknown => AppIcons.bedtimeRounded,
    SleepQuality.veryPoor => AppIcons.bedtimeRounded,
    SleepQuality.poor => AppIcons.bedtimeRounded,
    SleepQuality.fair => AppIcons.bedtimeRounded,
    SleepQuality.good => AppIcons.bedtimeRounded,
    SleepQuality.excellent => AppIcons.bedtimeRounded,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 7-day average card
// ─────────────────────────────────────────────────────────────────────────────

class _Avg7dCard extends StatelessWidget {
  const _Avg7dCard({required this.avg7d, required this.avg7dPrior});

  final ({int count, Duration? avgDuration}) avg7d;
  final ({int count, Duration? avgDuration}) avg7dPrior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sleepColor = AppColors.sleep(theme.brightness);
    final l10n = context.l10n;

    final avgDuration = avg7d.avgDuration;
    final durationText = avgDuration?.toRoundedString() ?? '—';

    final hasTrend = avg7dPrior.count > 0 &&
        avgDuration != null &&
        avg7dPrior.avgDuration != null;

    String? trendText;
    if (hasTrend) {
      // Both nullability guards are checked in hasTrend above.
      final delta = avgDuration - avg7dPrior.avgDuration!;
      trendText = l10n.sleepTrendVsPriorWeek(_formatDelta(delta));
    }

    final semanticLabel = hasTrend
        ? '${l10n.sleepSevenDayAvgLabel}, $durationText, $trendText'
        : '${l10n.sleepSevenDayAvgLabel}, $durationText';

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: PrismSectionCard(
        accentColor: sleepColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sleepSevenDayAvgLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: sleepColor.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              durationText,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            if (hasTrend) ...[
              const SizedBox(height: 6),
              Text(
                trendText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDelta(Duration delta) {
    final totalMinutes = delta.inMinutes;
    final sign = totalMinutes >= 0 ? '+' : '−';
    final abs = totalMinutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    if (h > 0 && m > 0) return '$sign${h}h ${m}m';
    if (h > 0) return '$sign${h}h 0m';
    return '$sign${m}m';
  }
}
