import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';

/// Paints the timeline session bars and "now" indicator.
///
/// Vertical axis = time, horizontal axis = member columns.
class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.rows,
    required this.columnWidth,
    required this.columnPadding,
    required this.pixelsPerHour,
    required this.viewStart,
    required this.viewEnd,
    required this.primaryColor,
    required this.surfaceColor,
    required this.onSurfaceColor,
    required this.surfaceContainerColor,
    required this.brightness,
    ValueNotifier<DateTime>? nowNotifier,
  }) : _nowNotifier = nowNotifier,
       super(repaint: nowNotifier);

  final List<TimelineMemberRow> rows;
  final double columnWidth;
  final double columnPadding;
  final double pixelsPerHour;
  final DateTime viewStart;
  final DateTime viewEnd;
  final Color primaryColor;
  final Color surfaceColor;
  final Color onSurfaceColor;
  final Color surfaceContainerColor;
  final Brightness brightness;
  final ValueNotifier<DateTime>? _nowNotifier;

  DateTime get _now => _nowNotifier?.value ?? DateTime.now();

  double _timeToY(DateTime time) {
    final diff = time.difference(viewStart);
    return diff.inMilliseconds / Duration.millisecondsPerHour * pixelsPerHour;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawAlternatingColumns(canvas, size);
    _drawTimeGrid(canvas, size);
    _drawSessionBars(canvas, size);
    _drawNowLine(canvas, size);
  }

  void _drawAlternatingColumns(Canvas canvas, Size size) {
    final totalColumnWidth = columnWidth + columnPadding;
    final altPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.05);

    for (var i = 0; i < rows.length; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(
              i * totalColumnWidth, 0, totalColumnWidth, size.height),
          altPaint,
        );
      }
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Draw horizontal lines at each hour
    var hour = DateTime(
        viewStart.year, viewStart.month, viewStart.day, viewStart.hour);
    if (hour.isBefore(viewStart)) {
      hour = hour.add(const Duration(hours: 1));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      hour = hour.add(const Duration(hours: 1));
    }
  }

  void _drawSessionBars(Canvas canvas, Size size) {
    final now = _now;
    final totalColumnWidth = columnWidth + columnPadding;
    final barInset = columnPadding / 2;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final memberColor = row.resolveColor(i, primaryColor, brightness);
      final x = i * totalColumnWidth + barInset;

      for (final session in row.sessions) {
        final sessionStart = session.startTime;
        final sessionEnd = session.endTime ?? now;

        // Skip if entirely outside viewport
        if (sessionEnd.isBefore(viewStart) ||
            sessionStart.isAfter(viewEnd)) {
          continue;
        }

        final y1 = math.max(0.0, _timeToY(sessionStart));
        final y2 = math.min(size.height, _timeToY(sessionEnd));

        if (y2 - y1 < 1) continue; // too small to draw

        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y1, columnWidth, y2 - y1),
          const Radius.circular(6),
        );

        // Fill
        final barPaint = Paint()
          ..color =
              memberColor.withValues(alpha: session.isActive ? 0.8 : 0.65);
        canvas.drawRRect(barRect, barPaint);

        // Subtle border for active sessions
        if (session.isActive) {
          final borderPaint = Paint()
            ..color = memberColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(barRect, borderPaint);
        }
      }
    }
  }

  void _drawNowLine(Canvas canvas, Size size) {
    final now = _now;
    if (now.isBefore(viewStart) || now.isAfter(viewEnd)) return;

    final y = _timeToY(now);
    final paint = Paint()
      ..color = primaryColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    // Small circle at left
    canvas.drawCircle(Offset(4, y), 4, Paint()..color = primaryColor);
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.brightness != brightness;
  }
}

/// Paints the time labels in the left gutter.
///
/// At midnight boundaries, shows the date instead of "12 AM" and draws a
/// heavier separator line. This avoids the overlap of separate date labels.
class TimelineTimeGutterPainter extends CustomPainter {
  TimelineTimeGutterPainter({
    required this.pixelsPerHour,
    required this.viewStart,
    required this.viewEnd,
    required this.textColor,
    required this.gridColor,
  });

  final double pixelsPerHour;
  final DateTime viewStart;
  final DateTime viewEnd;
  final Color textColor;
  final Color gridColor;

  double _timeToY(DateTime time) {
    final diff = time.difference(viewStart);
    return diff.inMilliseconds / Duration.millisecondsPerHour * pixelsPerHour;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    final midnightPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;

    // Determine label interval based on zoom
    final int hourInterval;
    if (pixelsPerHour >= 80) {
      hourInterval = 1;
    } else if (pixelsPerHour >= 40) {
      hourInterval = 2;
    } else if (pixelsPerHour >= 20) {
      hourInterval = 4;
    } else {
      hourInterval = 6;
    }

    var hour = DateTime(
        viewStart.year, viewStart.month, viewStart.day, viewStart.hour);
    if (hour.isBefore(viewStart)) {
      hour = hour.add(const Duration(hours: 1));
    }

    // Align to interval
    while (hour.hour % hourInterval != 0) {
      hour = hour.add(const Duration(hours: 1));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour);
      final isMidnight = hour.hour == 0;

      // Tick mark (full-width heavier line at midnight)
      if (isMidnight) {
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          midnightPaint,
        );
      } else {
        canvas.drawLine(
          Offset(size.width - 8, y),
          Offset(size.width, y),
          gridPaint,
        );
      }

      // Label: show date at midnight, time at other hours
      final label = isMidnight
          ? '${_shortWeekday(hour.weekday)} ${hour.month}/${hour.day}'
          : _formatHour(hour);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: textColor,
            fontSize: isMidnight ? 9 : 10,
            fontWeight: isMidnight ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          size.width - 12 - textPainter.width,
          y - textPainter.height / 2,
        ),
      );

      hour = hour.add(Duration(hours: hourInterval));
    }
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _shortWeekday(int weekday) => _weekdays[weekday - 1];

  String _formatHour(DateTime time) {
    final h = time.hour;
    if (h == 0) return '12 AM';
    if (h == 12) return '12 PM';
    if (h < 12) return '$h AM';
    return '${h - 12} PM';
  }

  @override
  bool shouldRepaint(covariant TimelineTimeGutterPainter oldDelegate) {
    return oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd;
  }
}
