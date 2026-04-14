import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/features/settings/models/analytics_insight.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// A flat warm-surface card showing one auto-generated analytics insight.
///
/// Uses flat surfaceContainer color (no elevation, no glass/blur).
/// Phosphor icon (regular weight) + headline + body sentence.
class AnalyticsInsightCard extends StatelessWidget {
  const AnalyticsInsightCard({super.key, required this.insight});

  final AnalyticsInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${insight.headline}. ${insight.body}',
      excludeSemantics: true,
      child: PrismSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(
              _resolveIcon(insight.iconType),
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.headline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    insight.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  PhosphorIconData _resolveIcon(AnalyticsInsightIconType type) =>
      switch (type) {
        AnalyticsInsightIconType.clockCountdown =>
          PhosphorIcons.clockCountdown(),
        AnalyticsInsightIconType.moonStars => PhosphorIcons.moonStars(),
        AnalyticsInsightIconType.arrowsHorizontal =>
          PhosphorIcons.arrowsHorizontal(),
        AnalyticsInsightIconType.usersThree => PhosphorIcons.usersThree(),
        AnalyticsInsightIconType.sun => PhosphorIcons.sun(),
        AnalyticsInsightIconType.moon => PhosphorIcons.moon(),
      };
}
