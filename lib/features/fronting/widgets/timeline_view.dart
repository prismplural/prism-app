import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_date_overlay.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// The timeline visualization of fronting history.
///
/// Vertical axis = time (scrollable, infinite), horizontal axis = members.
/// Scrolls vertically through all loaded history; loads more sessions
/// automatically as the user scrolls back in time.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  late ScrollController _verticalController;
  final ScrollController _horizontalController = ScrollController();
  Timer? _refreshTimer;
  bool _hasAutoScrolled = false;
  DateTime? _viewStart;
  bool _isLoadingMore = false;
  bool _scrollOffsetSyncScheduled = false;
  // Last successfully loaded data, kept as a fallback so first-frame reloads
  // never blank the timeline into a spinner.
  TimelineData? _lastData;
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(
    0.0,
  );

  static const double _headerRowHeight = 56.0;
  static const double _minColumnWidth = 36.0;
  static const double _maxColumnWidth = 48.0;
  static const double _wideMaxColumnWidth = 64.0;
  static const double _wideColumnBreakpoint = 900.0;
  static const double _columnPadding = 4.0;
  static const double _timeGutterWidth = 52.0;
  static const double _loadMoreThreshold = 500.0;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _verticalController.addListener(_onScroll);

    // Refresh every 30 seconds to update "now" line and active session bars.
    // Only the CustomPaint repaints — no setState rebuild of the whole widget.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _nowNotifier.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    _verticalController.removeListener(_onScroll);
    _verticalController.dispose();
    _horizontalController.dispose();
    _refreshTimer?.cancel();
    _nowNotifier.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_verticalController.hasClients) return;

    // Update scroll offset for viewport culling in painters.
    _scrollOffsetNotifier.value = _verticalController.offset;

    if (_isLoadingMore) return;
    if (ref.read(timelineFrontingHistoryProvider).isLoading ||
        ref.read(timelineRowsProvider).isLoading) {
      return;
    }

    // Load more when near the top (scrolling back in time)
    if (_verticalController.offset < _loadMoreThreshold) {
      _isLoadingMore = true;
      ref
          .read(timelineSessionLimitProvider.notifier)
          .increase(timelineSessionPageSize);
      // Brief cooldown to prevent rapid re-triggers
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timelineState = ref.watch(timelineStateProvider);
    final rowsAsync = ref.watch(timelineRowsProvider);
    final frontingTerms = watchFrontingTerms(context, ref);

    // Listen (not watch) for jump target — fires only on change, avoids
    // duplicate addPostFrameCallback registrations on rebuild.
    ref.listen<DateTime?>(timelineJumpTargetProvider, (_, target) {
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTime(target, timelineState.pixelsPerHour, animate: true);
          ref.read(timelineJumpTargetProvider.notifier).clear();
        });
      }
    });

    final bottomInset = NavBarInset.of(context);
    // Resolve which TimelineData to render. During load-more, the upstream
    // provider emits a bare AsyncLoading with no previous-data attached, so
    // we fall back to the last data we rendered. First load (no cache yet)
    // still shows the spinner.
    final TimelineData? data =
        rowsAsync.whenOrNull(
          data: (d) {
            _lastData = d;
            return d;
          },
        ) ??
        _lastData;

    if (rowsAsync is AsyncError && _lastData == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Center(child: Text(context.l10n.error)),
      );
    }

    if (data == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: const Center(child: PrismLoadingState()),
      );
    }

    final rows = data.memberRows;
    final sleepSessions = data.sleepSessions;
    if (rows.isEmpty && sleepSessions.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: EmptyState(
          icon: Icon(AppIcons.navTimeline),
          title: context.l10n.memberFrontingHistoryEmpty(
            frontingTerms.historyLabel.toLowerCase(),
          ),
          subtitle: context.l10n.frontingTimelineNoHistorySubtitle,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _timeGutterWidth;
        final maxColumnWidth = constraints.maxWidth >= _wideColumnBreakpoint
            ? _wideMaxColumnWidth
            : _maxColumnWidth;
        final idealColumnWidth = rows.isNotEmpty
            ? (availableWidth / rows.length - _columnPadding).clamp(
                _minColumnWidth,
                maxColumnWidth,
              )
            : maxColumnWidth;
        // Viewport height for the scrollable area:
        // total height minus header row and divider.
        final scrollableHeight = constraints.maxHeight - _headerRowHeight - 1;
        return _buildTimeline(
          context,
          theme,
          timelineState,
          rows,
          sleepSessions,
          idealColumnWidth,
          availableWidth,
          scrollableHeight,
        );
      },
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    ThemeData theme,
    TimelineState timelineState,
    List<TimelineMemberRow> rows,
    List<FrontingSession> sleepSessions,
    double columnWidth,
    double availableWidth,
    double scrollableViewportHeight,
  ) {
    final pxPerHour = timelineState.pixelsPerHour;
    final totalColumnWidth = columnWidth + _columnPadding;

    // Compute time range from loaded data
    final now = DateTime.now();
    final viewEnd = DateTime(now.year, now.month, now.day, now.hour + 2);

    // Find earliest session across both fronting and sleep history.
    DateTime earliest = now;
    for (final row in rows) {
      for (final session in row.sessions) {
        if (session.startTime.isBefore(earliest)) {
          earliest = session.startTime;
        }
      }
    }
    for (final session in sleepSessions) {
      if (session.startTime.isBefore(earliest)) {
        earliest = session.startTime;
      }
    }
    // Round down to start of day + 1 day buffer before earliest session
    final viewStart = DateTime(
      earliest.year,
      earliest.month,
      earliest.day,
    ).subtract(const Duration(days: 1));

    final totalHours =
        viewEnd.difference(viewStart).inMilliseconds /
        Duration.millisecondsPerHour;
    final totalHeight = totalHours * pxPerHour;
    _scheduleScrollOffsetSync();

    // Preserve scroll position when viewStart changes (more data loaded)
    if (_viewStart != null && viewStart.isBefore(_viewStart!)) {
      final deltaMs = _viewStart!.difference(viewStart).inMilliseconds;
      final deltaPixels = deltaMs / Duration.millisecondsPerHour * pxPerHour;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(_verticalController.offset + deltaPixels);
        }
      });
    }
    _viewStart = viewStart;

    // Auto-scroll to "now" on first build
    if (!_hasAutoScrolled) {
      _hasAutoScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTime(now, pxPerHour, animate: false);
      });
    }

    final columnsWidth = rows.isNotEmpty
        ? rows.length * totalColumnWidth
        : availableWidth;
    final needsHorizontalScroll = columnsWidth > availableWidth;
    final chartWidth = _timeGutterWidth + columnsWidth;
    final timelineViewportWidth = availableWidth + _timeGutterWidth;
    final chartViewportLeft = needsHorizontalScroll
        ? _timeGutterWidth
        : math.max(0.0, (timelineViewportWidth - chartWidth) / 2) +
              _timeGutterWidth;
    final chartViewportWidth = needsHorizontalScroll
        ? math.max(0.0, availableWidth)
        : columnsWidth;
    final timelineBottomInset = NavBarInset.of(context);

    final mergedListenable = Listenable.merge([
      _nowNotifier,
      _scrollOffsetNotifier,
    ]);

    Widget buildSessionColumns() {
      final painter = TimelinePainter(
        rows: rows,
        sleepSessions: sleepSessions,
        columnWidth: columnWidth,
        columnPadding: _columnPadding,
        pixelsPerHour: pxPerHour,
        viewStart: viewStart,
        viewEnd: viewEnd,
        primaryColor: theme.colorScheme.primary,
        surfaceColor: theme.colorScheme.surface,
        onSurfaceColor: theme.colorScheme.onSurface,
        surfaceContainerColor: theme.colorScheme.surfaceContainerHighest,
        brightness: theme.brightness,
        scrollOffsetNotifier: _scrollOffsetNotifier,
        viewportHeight: scrollableViewportHeight,
        shapes: PrismShapes.of(context),
        repaintListenable: mergedListenable,
      );
      final canvasSize = Size(columnsWidth, totalHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) =>
            _onTimelineTap(context, details.localPosition, painter, canvasSize),
        child: CustomPaint(size: canvasSize, painter: painter),
      );
    }

    Widget centerShortTimeline(Widget child) {
      if (needsHorizontalScroll) return child;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: chartWidth, child: child),
      );
    }

    Widget buildHeaderRow() {
      return Row(
        children: [
          const SizedBox(width: _timeGutterWidth),
          if (needsHorizontalScroll)
            Expanded(
              child: _HeaderRow(
                rows: rows,
                columnsWidth: columnsWidth,
                totalColumnWidth: totalColumnWidth,
                columnWidth: columnWidth,
                primaryColor: theme.colorScheme.primary,
                brightness: theme.brightness,
                controller: _horizontalController,
              ),
            )
          else
            _HeaderRow(
              rows: rows,
              columnsWidth: columnsWidth,
              totalColumnWidth: totalColumnWidth,
              columnWidth: columnWidth,
              primaryColor: theme.colorScheme.primary,
              brightness: theme.brightness,
            ),
        ],
      );
    }

    Widget buildScrollableRow() {
      return Row(
        children: [
          SizedBox(
            width: _timeGutterWidth,
            height: totalHeight,
            child: CustomPaint(
              size: Size(_timeGutterWidth, totalHeight),
              painter: TimelineTimeGutterPainter(
                pixelsPerHour: pxPerHour,
                viewStart: viewStart,
                viewEnd: viewEnd,
                textColor: theme.colorScheme.onSurfaceVariant,
                gridColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                scrollOffsetNotifier: _scrollOffsetNotifier,
                viewportHeight: scrollableViewportHeight,
                locale: context.dateLocale,
                textScaler: MediaQuery.textScalerOf(context),
                alwaysUse24HourFormat: MediaQuery.of(
                  context,
                ).alwaysUse24HourFormat,
                repaintListenable: _scrollOffsetNotifier,
              ),
            ),
          ),
          if (needsHorizontalScroll)
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    _horizontalController.jumpTo(notification.metrics.pixels);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: buildSessionColumns(),
                ),
              ),
            )
          else
            SizedBox(
              width: columnsWidth,
              height: totalHeight,
              child: buildSessionColumns(),
            ),
        ],
      );
    }

    return Column(
      children: [
        // Sticky header row: member avatars/names
        SizedBox(
          height: _headerRowHeight,
          child: centerShortTimeline(buildHeaderRow()),
        ),
        // Divider
        centerShortTimeline(
          Container(
            height: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        // Scrollable timeline area
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _verticalController,
                padding: EdgeInsets.only(bottom: timelineBottomInset),
                child: SizedBox(
                  height: totalHeight,
                  child: centerShortTimeline(buildScrollableRow()),
                ),
              ),
              if (chartViewportWidth > 0)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: chartViewportLeft,
                  width: chartViewportWidth,
                  child: TimelineDateOverlay(
                    viewStart: viewStart,
                    viewEnd: viewEnd,
                    pixelsPerHour: pxPerHour,
                    viewportHeight: scrollableViewportHeight,
                    contentHeight: totalHeight,
                    scrollableHeight: totalHeight + timelineBottomInset,
                    scrollOffsetListenable: _scrollOffsetNotifier,
                    nowListenable: _nowNotifier,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _onTimelineTap(
    BuildContext context,
    Offset localPosition,
    TimelinePainter painter,
    Size canvasSize,
  ) {
    final zones = painter.computeHitZones(canvasSize);
    for (final zone in zones) {
      if (zone.rect.contains(localPosition)) {
        _showSessionPreview(context, zone.session);
        return;
      }
    }
  }

  void _showSessionPreview(BuildContext context, FrontingSession session) {
    showAdaptiveDetailSurface<void>(
      context: context,
      builder: (_) => SessionDetailScreen(sessionId: session.id),
      route: (context) {
        PrismSheet.show(
          context: context,
          builder: (sheetContext) => _SessionPreviewSheet(session: session),
        );
      },
    );
  }

  void _scrollToTime(DateTime time, double pxPerHour, {bool animate = true}) {
    if (!_verticalController.hasClients || _viewStart == null) return;

    final targetY =
        time.difference(_viewStart!).inMilliseconds /
        Duration.millisecondsPerHour *
        pxPerHour;
    final viewportHeight = _verticalController.position.viewportDimension;
    final scrollTo = (targetY - viewportHeight / 2).clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );

    if (animate && (_verticalController.offset - scrollTo).abs() > 50) {
      _verticalController.animateTo(
        scrollTo,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _verticalController.jumpTo(scrollTo);
    }
  }

  void _scheduleScrollOffsetSync() {
    if (_scrollOffsetSyncScheduled) return;
    _scrollOffsetSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollOffsetSyncScheduled = false;
      if (!mounted || !_verticalController.hasClients) return;

      final position = _verticalController.position;
      final clampedScrollOffset = position.pixels
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - clampedScrollOffset).abs() > 0.5) {
        _verticalController.jumpTo(clampedScrollOffset);
      }

      if ((_scrollOffsetNotifier.value - clampedScrollOffset).abs() > 0.5) {
        _scrollOffsetNotifier.value = clampedScrollOffset;
      }
    });
  }
}

/// Preview bottom sheet shown when a session bar is tapped in the timeline.
///
/// Displays member avatar, name, start time, duration, and a button to navigate
/// to the full session detail screen.
class _SessionPreviewSheet extends ConsumerWidget {
  const _SessionPreviewSheet({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    // Each session bar represents one member's continuous presence.
    // TODO(§2.4): Phase 3 — rewrite to show the per-member session directly
    // and offer "see this period" to open the period-detail screen (§3.1).
    final memberIds = <String>{if (session.memberId != null) session.memberId!};
    final membersAsync = ref.watch(
      membersByIdsListProvider(memberIdsKey(memberIds)),
    );
    final membersMap = membersAsync.whenOrNull(data: (m) => m) ?? {};

    final member = session.memberId != null
        ? membersMap[session.memberId]
        : null;
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final memberName = member?.effectiveName(preferDisplayName: prefer);

    final String displayName;
    if (session.memberId == null) {
      displayName = context.l10n.unknown;
    } else {
      displayName = memberName ?? context.l10n.unknown;
    }

    final startLabel = context.formatTime(session.startTime);
    final dateLabel = session.startTime.toDateString(context.dateLocale);
    final duration = (session.endTime ?? now).difference(session.startTime);
    final durationLabel = session.isActive
        ? 'Active'
        : duration.toRoundedString();
    final bottomInset = modalBottomInsetOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Member row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              MemberAvatar(
                emoji: member?.emoji ?? '?',
                memberName: memberName,
                customColorEnabled: member?.customColorEnabled ?? false,
                customColorHex: member?.customColorHex,
                avatarImageData: member?.avatarImageData,
                memberId: member?.id,
                deferAvatarLookup: true,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateLabel · $startLabel · $durationLabel',
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
        const SizedBox(height: 16),
        // Action button
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 4 + bottomInset),
          child: PrismButton(
            label: 'View Details',
            icon: AppIcons.chevronRightRounded,
            tone: PrismButtonTone.filled,
            expanded: true,
            onPressed: () {
              // Compact preview keeps its width-only handoff.
              final useSheet = shouldUseDetailSideSheet(context);
              Navigator.of(context).pop();
              if (useSheet) {
                showDetailSideSheet(
                  context,
                  builder: (_) => SessionDetailScreen(sessionId: session.id),
                );
              } else {
                GoRouter.of(context).push(AppRoutePaths.session(session.id));
              }
            },
          ),
        ),
      ],
    );
  }
}

/// The row of member headers pinned above the timeline.
///
/// Extracted as a standalone widget so Flutter can skip rebuilds when only the
/// vertical scroll offset changes (the header depends on member data, not on
/// scroll position).
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.rows,
    required this.columnsWidth,
    required this.totalColumnWidth,
    required this.columnWidth,
    required this.primaryColor,
    required this.brightness,
    this.controller,
  });

  final List<TimelineMemberRow> rows;
  final double columnsWidth;
  final double totalColumnWidth;
  final double columnWidth;
  final Color primaryColor;
  final Brightness brightness;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: columnsWidth,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: controller != null
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: rows.length,
        itemExtent: totalColumnWidth,
        itemBuilder: (context, i) => _MemberHeader(
          row: rows[i],
          rowIndex: i,
          width: totalColumnWidth,
          columnWidth: columnWidth,
          primaryColor: primaryColor,
          brightness: brightness,
        ),
      ),
    );
  }
}

/// A member avatar + name in the sticky top header row.
class _MemberHeader extends ConsumerWidget {
  const _MemberHeader({
    required this.row,
    required this.rowIndex,
    required this.width,
    required this.columnWidth,
    required this.primaryColor,
    required this.brightness,
  });

  final TimelineMemberRow row;
  final int rowIndex;
  final double width;
  final double columnWidth;
  final Color primaryColor;
  final Brightness brightness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = row.resolveColor(rowIndex, primaryColor, brightness);
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final name = row.member.effectiveName(preferDisplayName: prefer);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MemberAvatar(
            emoji: row.member.emoji,
            memberName: name,
            customColorEnabled: row.member.customColorEnabled,
            customColorHex: row.member.customColorHex,
            avatarImageData: row.member.avatarImageData,
            memberId: row.member.id,
            deferAvatarLookup: true,
            size: 28,
            tintOverride: color,
          ),
          const SizedBox(height: 2),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: color,
              fontSize: columnWidth > 44 ? 11 : 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
