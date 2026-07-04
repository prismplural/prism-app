import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:prism_plurality/features/fronting/widgets/timeline_geometry.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';

class TimelineDateOverlay extends StatelessWidget {
  const TimelineDateOverlay({
    super.key,
    required this.viewStart,
    required this.viewEnd,
    required this.pixelsPerHour,
    required this.viewportHeight,
    required this.contentHeight,
    required this.scrollOffsetListenable,
    this.scrollableHeight,
    this.contentTopInViewport = 0,
    this.nowListenable,
    this.now,
  });

  final DateTime viewStart;
  final DateTime viewEnd;
  final double pixelsPerHour;
  final double viewportHeight;
  final double contentHeight;
  final double? scrollableHeight;
  final ValueListenable<double> scrollOffsetListenable;
  final double contentTopInViewport;
  final ValueListenable<DateTime>? nowListenable;
  final DateTime? now;

  static const double _baseY = 8;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([scrollOffsetListenable, ?nowListenable]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth;
              if (chartWidth <= 0 ||
                  viewportHeight <= 0 ||
                  pixelsPerHour <= 0) {
                return const SizedBox.shrink();
              }

              final geometry = TimelineGeometry(
                viewStart: viewStart,
                viewEnd: viewEnd,
                pixelsPerHour: pixelsPerHour,
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollableHeight: scrollableHeight,
                scrollOffset: scrollOffsetListenable.value,
                contentTopInViewport: contentTopInViewport,
              );

              return _TimelineDateOverlayContents(
                geometry: geometry,
                chartWidth: chartWidth,
                now: nowListenable?.value ?? now ?? DateTime.now(),
              );
            },
          );
        },
      ),
    );
  }
}

class _TimelineDateOverlayContents extends StatelessWidget {
  const _TimelineDateOverlayContents({
    required this.geometry,
    required this.chartWidth,
    required this.now,
  });

  final TimelineGeometry geometry;
  final double chartWidth;
  final DateTime now;

  static const double _baseY = TimelineDateOverlay._baseY;
  static const double _gap = TimelineDateOverlay._gap;
  static const double _horizontalPadding = 8;
  static const double _maxChipWidth = 220;

  @override
  Widget build(BuildContext context) {
    final chipHeight = _estimatedChipHeight(context);
    final maxChipWidth = math.max(
      0.0,
      math.min(_maxChipWidth, chartWidth - _horizontalPadding * 2),
    );
    if (maxChipWidth <= 0) return const SizedBox.shrink();

    final activeDay = geometry.activeDayAtProbe(_baseY + 4);
    final today = geometry.startOfCalendarDay(now);
    final showFloating = !sameTimelineDay(activeDay, today);
    final children = <Widget>[];
    final occupiedRects = <Rect>[];

    if (showFloating) {
      final nextDay = geometry.calendarDayOffset(activeDay, 1);
      final nextBoundaryY = geometry.contentYToViewportY(
        geometry.timeToContentY(nextDay),
      );
      final stickyY = math.min(_baseY, nextBoundaryY - chipHeight - _gap);
      final floatingRect = _chipRect(stickyY, maxChipWidth, chipHeight);
      occupiedRects.add(floatingRect);
      if (stickyY > -chipHeight && stickyY < geometry.viewportHeight) {
        children.add(
          _positionedChip(
            top: stickyY,
            date: activeDay,
            maxWidth: maxChipWidth,
            includeSemantics: true,
            semanticHeader: false,
            semanticLabel: context.l10n.frontingTimelinePositionLabel(
              activeDay.toDayHeaderLabel(context.dateLocale),
            ),
          ),
        );
      }
    }

    for (final boundary in geometry.dayBoundariesNearViewport(
      bleed: chipHeight + _gap,
    )) {
      final boundaryY = geometry.contentYToViewportY(
        geometry.timeToContentY(boundary),
      );
      final top = boundaryY - chipHeight / 2;
      if (top <= -chipHeight || top >= geometry.viewportHeight) continue;

      final rect = _chipRect(top, maxChipWidth, chipHeight);
      if (occupiedRects.any(rect.overlaps)) continue;

      occupiedRects.add(rect);
      children.add(
        _positionedChip(
          top: top,
          date: boundary,
          maxWidth: maxChipWidth,
          includeSemantics: true,
        ),
      );
    }

    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }

  Rect _chipRect(double top, double width, double height) {
    return Rect.fromLTWH((chartWidth - width) / 2, top, width, height);
  }

  Widget _positionedChip({
    required double top,
    required DateTime date,
    required double maxWidth,
    required bool includeSemantics,
    bool semanticHeader = true,
    String? semanticLabel,
  }) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: DateChip(
          date: date,
          includeSemantics: includeSemantics,
          semanticHeader: semanticHeader,
          semanticLabel: semanticLabel,
          maxWidth: maxWidth,
        ),
      ),
    );
  }

  double _estimatedChipHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return math.max(24.0, textScaler.scale(11) + 12);
  }
}
