import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

/// Displays a date and time as two separate tappable pill buttons.
///
/// Tapping the date pill opens an inline iOS 14+ calendar picker.
/// Tapping the time pill opens an inline time picker.
/// Each can be edited independently without touching the other.
class PrismDateTimePills extends StatelessWidget {
  const PrismDateTimePills({
    super.key,
    required this.label,
    required this.dateTime,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.placeholder,
  });

  /// Label shown above the pills (e.g. "Start", "End").
  final String label;

  /// The current date/time value. If null, shows [placeholder].
  final DateTime? dateTime;

  /// Called when either the date or time is changed.
  final ValueChanged<DateTime> onChanged;

  /// Earliest selectable date.
  final DateTime? firstDate;

  /// Latest selectable date.
  final DateTime? lastDate;

  /// Text shown when [dateTime] is null.
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = dateTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (dt != null)
          Row(
            children: [
              _DatePill(
                dateTime: dt,
                firstDate: firstDate,
                lastDate: lastDate,
                onChanged: (newDate) {
                  onChanged(DateTime(
                    newDate.year,
                    newDate.month,
                    newDate.day,
                    dt.hour,
                    dt.minute,
                  ));
                },
              ),
              const SizedBox(width: 10),
              _TimePill(
                dateTime: dt,
                onChanged: (newTime) {
                  onChanged(DateTime(
                    dt.year,
                    dt.month,
                    dt.day,
                    newTime.hour,
                    newTime.minute,
                  ));
                },
              ),
            ],
          )
        else
          _PlaceholderPill(
            text: placeholder ?? context.l10n.tapToSet,
            onTap: () async {
              final date = await showPrismDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (date == null || !context.mounted) return;
              final time = await showPrismTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time == null || !context.mounted) return;
              onChanged(DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              ));
            },
          ),
      ],
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    required this.dateTime,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final DateTime dateTime;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat.yMMMd().format(dateTime);
    return _Pill(
      text: formatted,
      onTap: () async {
        final picked = await showPrismDatePicker(
          context: context,
          initialDate: dateTime,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.dateTime,
    required this.onChanged,
  });

  final DateTime dateTime;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(dateTime);
    return _Pill(
      text: time.format(context),
      onTap: () async {
        final picked = await showPrismTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.08)
                : AppColors.warmBlack.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
            border: Border.all(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.12)
                  : AppColors.warmBlack.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPill extends StatelessWidget {
  const _PlaceholderPill({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
            border: Border.all(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
