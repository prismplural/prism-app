import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tabRetapProvider, (_, _) {
      ref.read(timelineJumpTargetProvider.notifier).jumpTo(DateTime.now());
    });

    final state = ref.watch(timelineStateProvider);
    final notifier = ref.read(timelineStateProvider.notifier);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.navTimeline,
        leading: Builder(
          builder: (anchorContext) => PrismTopBarAction(
            icon: AppIcons.calendarTodayRounded,
            tooltip: context.l10n.frontingTimelineJumpToDate,
            onPressed: () => _pickDate(context, anchorContext, ref),
          ),
        ),
        actions: [
          PrismTopBarAction(
            icon: AppIcons.removeRounded,
            tooltip: context.l10n.frontingTimelineZoomOut,
            onPressed: state.pixelsPerHour > TimelineState.minPixelsPerHour
                ? notifier.zoomOut
                : null,
          ),
          PrismTopBarAction(
            icon: AppIcons.addRounded,
            tooltip: context.l10n.frontingTimelineZoomIn,
            onPressed: state.pixelsPerHour < TimelineState.maxPixelsPerHour
                ? notifier.zoomIn
                : null,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      safeAreaBottom: false,
      body: const TimelineView(),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    BuildContext anchorContext,
    WidgetRef ref,
  ) async {
    final picked = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref
          .read(timelineJumpTargetProvider.notifier)
          .jumpTo(DateTime(picked.year, picked.month, picked.day, 12));
    }
  }
}
