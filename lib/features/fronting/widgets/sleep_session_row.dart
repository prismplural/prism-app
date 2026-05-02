import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class SleepSessionRow extends StatelessWidget {
  const SleepSessionRow({
    super.key,
    required this.session,
    required this.onTap,
    required this.onLongPress,
  });

  final FrontingSession session;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sleepColor = AppColors.sleep(theme.brightness);

    final duration = session.duration;
    final durationLabel = duration.toShortString();

    final dateLabel = DateFormat('EEE · MMM d').format(session.startTime);

    final startTimeStr =
        DateFormat.jm().format(session.startTime);
    final endTimeStr = session.endTime != null
        ? DateFormat.jm().format(session.endTime!)
        : '–';
    final timeRange = '$startTimeStr → $endTimeStr';

    final qualityLabel = session.quality != null
        ? session.quality!.localizedLabel(l10n)
        : l10n.sleepQualityNotRated;

    final isFutureDate = session.startTime.isAfter(DateTime.now());

    final hasNotes =
        session.notes != null && session.notes!.isNotEmpty;

    final semanticDurationWords = _semanticDuration(duration);
    final qualityWord = session.quality?.localizedLabel(l10n) ??
        l10n.sleepQualityNotRated;
    final semanticLabel =
        'Sleep on $dateLabel, $semanticDurationWords, quality $qualityWord';

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: 'Long press for options',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dateLabel,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          durationLabel,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: sleepColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            timeRange,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PhosphorIcon(
                              AppIcons.bedtimeRounded,
                              size: 14,
                              color: sleepColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              qualityLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: sleepColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (hasNotes) ...[
                      const SizedBox(height: 2),
                      Text(
                        session.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (isFutureDate) ...[
                      const SizedBox(height: 4),
                      _DateWarningChip(sleepColor: sleepColor),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final parts = <String>[];
    if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
    if (minutes > 0) {
      parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
    }
    if (parts.isEmpty) return '0 minutes';
    return parts.join(' ');
  }
}

class _DateWarningChip extends StatelessWidget {
  const _DateWarningChip({required this.sleepColor});

  final Color sleepColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.warningAmberRounded,
            size: 12,
            color: AppColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            'Date looks off',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
