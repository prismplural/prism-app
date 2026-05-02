import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
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
  // Last successfully loaded data, kept so the timeline stays visible while
  // load-more refetches with a higher limit. Without this, every limit bump
  // creates a fresh `frontingHistoryProvider(N)` family instance whose initial
  // AsyncLoading has no `previous` attached, and the view blanks out into a
  // spinner — which is what the user saw past ~1–2 weeks of history.
  TimelineData? _lastData;
  final ValueNotifier<DateTime> _nowNotifier =
      ValueNotifier<DateTime>(DateTime.now());
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0.0);

  static const double _headerRowHeight = 56.0;
  static const double _minColumnWidth = 36.0;
  static const double _maxColumnWidth = 48.0;
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

    // Load more when near the top (scrolling back in time)
    if (_verticalController.offset < _loadMoreThreshold) {
      _isLoadingMore = true;
      ref.read(timelineSessionLimitProvider.notifier).increase(100);
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
    final TimelineData? data = rowsAsync.whenOrNull(
      data: (d) {
        _lastData = d;
        return d;
      },
    ) ?? _lastData;

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
          title: context.l10n.frontingTimelineNoHistory,
          subtitle: context.l10n.frontingTimelineNoHistorySubtitle,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _timeGutterWidth;
        final idealColumnWidth = rows.isNotEmpty
            ? (availableWidth / rows.length - _columnPadding).clamp(
                _minColumnWidth,
                _maxColumnWidth,
              )
            : _maxColumnWidth;
        // Viewport height for the scrollable area:
        // total height minus header row and divider.
        final scrollableHeight =
            constraints.maxHeight - _headerRowHeight - 1;
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
        child: CustomPaint(
          size: canvasSize,
          painter: painter,
        ),
      );
    }

    return Column(
      children: [
        // Sticky header row: member avatars/names
        SizedBox(
          height: _headerRowHeight,
          child: Row(
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
          ),
        ),
        // Divider
        Container(
          height: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        // Scrollable timeline area
        Expanded(
          child: SingleChildScrollView(
            controller: _verticalController,
            padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            child: SizedBox(
              height: totalHeight,
              child: Row(
                children: [
                  // Time gutter (sticky left labels)
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
                        gridColor: theme.colorScheme.onSurface.withValues(
                          alpha: 0.12,
                        ),
                        scrollOffsetNotifier: _scrollOffsetNotifier,
                        viewportHeight: scrollableViewportHeight,
                        repaintListenable: _scrollOffsetNotifier,
                      ),
                    ),
                  ),
                  // Session columns
                  if (needsHorizontalScroll)
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification) {
                            _horizontalController.jumpTo(
                              notification.metrics.pixels,
                            );
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
                    Expanded(child: buildSessionColumns()),
                ],
              ),
            ),
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
    PrismSheet.show(
      context: context,
      builder: (sheetContext) => _SessionPreviewSheet(session: session),
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
    final memberIds = <String>{
      if (session.memberId != null) session.memberId!,
    };
    final membersAsync =
        ref.watch(membersByIdsProvider(memberIdsKey(memberIds)));
    final membersMap = membersAsync.whenOrNull(data: (m) => m) ?? {};

    final member =
        session.memberId != null ? membersMap[session.memberId] : null;

    final String displayName;
    if (session.memberId == null) {
      displayName = 'Unknown';
    } else {
      displayName = member?.name ?? 'Unknown';
    }

    final startLabel = session.startTime.toTimeString();
    final dateLabel = session.startTime.toDateString();
    final duration = (session.endTime ?? now).difference(session.startTime);
    final durationLabel =
        session.isActive ? 'Active' : duration.toRoundedString();

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
                memberName: member?.name,
                customColorEnabled: member?.customColorEnabled ?? false,
                customColorHex: member?.customColorHex,
                avatarImageData: member?.avatarImageData,
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: PrismButton(
            label: 'View Details',
            icon: AppIcons.chevronRightRounded,
            tone: PrismButtonTone.filled,
            expanded: true,
            onPressed: () {
              Navigator.of(context).pop();
              GoRouter.of(context).push(AppRoutePaths.session(session.id));
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
class _MemberHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = row.resolveColor(rowIndex, primaryColor, brightness);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MemberAvatar(
            emoji: row.member.emoji,
            memberName: row.member.name,
            customColorEnabled: row.member.customColorEnabled,
            customColorHex: row.member.customColorHex,
            avatarImageData: row.member.avatarImageData,
            size: 28,
            tintOverride: color,
          ),
          const SizedBox(height: 2),
          Text(
            row.member.name,
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
