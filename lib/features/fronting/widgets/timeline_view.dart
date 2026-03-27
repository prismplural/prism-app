import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_controls.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

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

    return Column(
      children: [
        const TimelineControls(),
        const SizedBox(height: 4),
        Expanded(
          child: rowsAsync.when(
            loading: () => const Center(child: PrismLoadingState()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.timeline_rounded,
                  title: 'No fronting history',
                  subtitle:
                      'Start a fronting session to see it appear on the timeline.',
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth =
                      constraints.maxWidth - _timeGutterWidth;
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
                    idealColumnWidth,
                    availableWidth,
                    scrollableHeight,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    ThemeData theme,
    TimelineState timelineState,
    List<TimelineMemberRow> rows,
    double columnWidth,
    double availableWidth,
    double scrollableViewportHeight,
  ) {
    final pxPerHour = timelineState.pixelsPerHour;
    final totalColumnWidth = columnWidth + _columnPadding;

    // Compute time range from loaded data
    final now = DateTime.now();
    final viewEnd = DateTime(now.year, now.month, now.day, now.hour + 2);

    // Find earliest session across all rows
    DateTime earliest = now;
    for (final row in rows) {
      for (final session in row.sessions) {
        if (session.startTime.isBefore(earliest)) {
          earliest = session.startTime;
        }
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

    final columnsWidth = rows.length * totalColumnWidth;
    final needsHorizontalScroll = columnsWidth > availableWidth;

    Widget buildHeaderColumns({ScrollController? controller}) {
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
            primaryColor: theme.colorScheme.primary,
            brightness: theme.brightness,
          ),
        ),
      );
    }

    final mergedListenable = Listenable.merge([
      _nowNotifier,
      _scrollOffsetNotifier,
    ]);

    Widget buildSessionColumns() {
      return CustomPaint(
        size: Size(columnsWidth, totalHeight),
        painter: TimelinePainter(
          rows: rows,
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
          repaintListenable: mergedListenable,
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
                  child: buildHeaderColumns(
                    controller: _horizontalController,
                  ),
                )
              else
                buildHeaderColumns(),
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
