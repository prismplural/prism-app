import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';

/// Control bar for the timeline with zoom and navigation buttons.
class TimelineControls extends ConsumerWidget {
  const TimelineControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(timelineStateProvider);
    final notifier = ref.read(timelineStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Jump to date
          GestureDetector(
            onTap: () => _pickDate(context, ref),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.calendarTodayRounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.frontingTimelineJumpToDate,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Today button
          PrismIconButton(
            icon: AppIcons.todayRounded,
            tooltip: context.l10n.frontingTimelineJumpToNow,
            onPressed: () {
              ref.read(timelineJumpTargetProvider.notifier).jumpTo(
                    DateTime.now(),
                  );
            },
            size: 36,
            iconSize: 18,
          ),
          const SizedBox(width: 4),

          // Zoom out
          PrismIconButton(
            icon: AppIcons.removeRounded,
            tooltip: context.l10n.frontingTimelineZoomOut,
            onPressed: notifier.zoomOut,
            size: 36,
            iconSize: 18,
            enabled: state.pixelsPerHour > TimelineState.minPixelsPerHour,
          ),
          const SizedBox(width: 4),

          // Zoom in
          PrismIconButton(
            icon: AppIcons.addRounded,
            tooltip: context.l10n.frontingTimelineZoomIn,
            onPressed: notifier.zoomIn,
            size: 36,
            iconSize: 18,
            enabled: state.pixelsPerHour < TimelineState.maxPixelsPerHour,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final picked = await showPrismDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      // Jump to noon on the picked date so the day is centered
      ref.read(timelineJumpTargetProvider.notifier).jumpTo(
            DateTime(picked.year, picked.month, picked.day, 12),
          );
    }
  }
}
