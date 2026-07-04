import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

class TimelineGeometry {
  const TimelineGeometry({
    required this.viewStart,
    required this.viewEnd,
    required this.pixelsPerHour,
    required this.viewportHeight,
    required this.contentHeight,
    required this.scrollOffset,
    double? scrollableHeight,
    this.contentTopInViewport = 0,
  }) : scrollableHeight = scrollableHeight ?? contentHeight;

  final DateTime viewStart;
  final DateTime viewEnd;
  final double pixelsPerHour;
  final double viewportHeight;
  final double contentHeight;
  final double scrollableHeight;
  final double scrollOffset;
  final double contentTopInViewport;

  double timeToContentY(DateTime time) {
    final diff = time.difference(viewStart);
    return diff.inMilliseconds / Duration.millisecondsPerHour * pixelsPerHour;
  }

  DateTime contentYToTime(double y) {
    final millis =
        clampContentY(y) / pixelsPerHour * Duration.millisecondsPerHour;
    return viewStart.add(Duration(milliseconds: millis.round()));
  }

  double boundedScrollOffset() {
    final maxOffset = math.max(0.0, contentHeight - viewportHeight);
    return scrollOffset.clamp(0.0, maxOffset).toDouble();
  }

  double visualScrollOffset() {
    final maxOffset = math.max(0.0, scrollableHeight - viewportHeight);
    return scrollOffset.clamp(0.0, maxOffset).toDouble();
  }

  double clampContentY(double y) {
    return y.clamp(0.0, math.max(0.0, contentHeight)).toDouble();
  }

  double contentYToViewportY(double y) {
    return contentTopInViewport + y - visualScrollOffset();
  }

  double viewportYToContentY(double y) {
    return clampContentY(_rawViewportYToContentY(y));
  }

  DateTime timeAtViewportY(double viewportY) {
    return contentYToTime(viewportYToContentY(viewportY));
  }

  DateTime activeDayAtProbe(double probeY) {
    return startOfCalendarDay(timeAtViewportY(probeY));
  }

  DateTime startOfCalendarDay(DateTime value) {
    if (value is tz.TZDateTime) {
      return tz.TZDateTime(value.location, value.year, value.month, value.day);
    }
    return DateTime(value.year, value.month, value.day);
  }

  DateTime calendarDayOffset(DateTime day, int offset) {
    if (day is tz.TZDateTime) {
      return tz.TZDateTime(day.location, day.year, day.month, day.day + offset);
    }
    return DateTime(day.year, day.month, day.day + offset);
  }

  Iterable<DateTime> dayBoundariesNearViewport({double bleed = 80}) sync* {
    if (contentHeight <= 0 || pixelsPerHour <= 0) return;

    final topContentY = clampContentY(_rawViewportYToContentY(-bleed));
    final bottomContentY = clampContentY(
      _rawViewportYToContentY(viewportHeight + bleed),
    );
    if (bottomContentY < topContentY) return;

    final end = contentYToTime(bottomContentY);
    var day = startOfCalendarDay(contentYToTime(topContentY));
    if (day.isBefore(startOfCalendarDay(viewStart))) {
      day = startOfCalendarDay(viewStart);
    }

    while (!day.isAfter(end) && !day.isAfter(viewEnd)) {
      final y = timeToContentY(day);
      if (y >= topContentY && y <= bottomContentY && !day.isBefore(viewStart)) {
        yield day;
      }
      day = calendarDayOffset(day, 1);
    }
  }

  double _rawViewportYToContentY(double y) {
    return y - contentTopInViewport + visualScrollOffset();
  }
}

bool sameTimelineDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
