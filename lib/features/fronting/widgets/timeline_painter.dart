import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

/// A tappable region on the timeline canvas corresponding to one session bar.
typedef TimelineHitZone = ({Rect rect, FrontingSession session, int columnIndex});

/// Paints the timeline session bars and "now" indicator.
///
/// Vertical axis = time, horizontal axis = member columns.
class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.rows,
    required this.sleepSessions,
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
    required this.viewportHeight,
    required this.shapes,
    this.scrollOffsetNotifier,
    Listenable? repaintListenable,
  }) : super(repaint: repaintListenable);

  final List<TimelineMemberRow> rows;
  final List<FrontingSession> sleepSessions;
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
  final double viewportHeight;
  final PrismShapes shapes;
  final ValueNotifier<double>? scrollOffsetNotifier;

  /// Visible Y range with a small bleed margin to avoid clipping at edges.
  static const double _bleed = 10.0;
  double get _scrollOffset => scrollOffsetNotifier?.value ?? 0.0;
  double get _visibleTop => _scrollOffset - _bleed;
  double get _visibleBottom => _scrollOffset + viewportHeight + _bleed;

  double _timeToY(DateTime time) {
    final diff = time.difference(viewStart);
    return diff.inMilliseconds / Duration.millisecondsPerHour * pixelsPerHour;
  }

  /// Computes hit-test rectangles for all session bars, using the same geometry
  /// as [_drawSessionBars]. Call this from a [GestureDetector] to map a tap
  /// position back to a [FrontingSession].
  List<TimelineHitZone> computeHitZones(Size size) {
    final now = DateTime.now();
    final totalColumnWidth = columnWidth + columnPadding;
    final barInset = columnPadding / 2;
    final zones = <TimelineHitZone>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final x = i * totalColumnWidth + barInset;

      for (final session in row.sessions) {
        final sessionStart = session.startTime;
        final sessionEnd = session.endTime ?? now;

        if (sessionEnd.isBefore(viewStart) || sessionStart.isAfter(viewEnd)) {
          continue;
        }

        final y1 = math.max(0.0, _timeToY(sessionStart));
        final y2 = math.min(size.height, _timeToY(sessionEnd));

        if (y2 - y1 < 1) continue;

        zones.add((
          rect: Rect.fromLTWH(x, y1, columnWidth, y2 - y1),
          session: session,
          columnIndex: i,
        ));
      }
    }

    return zones;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawSleepBars(canvas, size);
    _drawAlternatingColumns(canvas, size);
    _drawTimeGrid(canvas, size);
    _drawSessionBars(canvas, size);
    _drawNowLine(canvas, size);
  }

  void _drawSleepBars(Canvas canvas, Size size) {
    final now = DateTime.now();
    final sleepFillPaint = Paint()
      ..color = Colors.indigo.withValues(alpha: 0.16);
    final sleepBorderPaint = Paint()
      ..color = Colors.indigo.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final session in sleepSessions) {
      final sessionStart = session.startTime;
      final sessionEnd = session.endTime ?? now;

      if (sessionEnd.isBefore(viewStart) || sessionStart.isAfter(viewEnd)) {
        continue;
      }

      final y1 = math.max(0.0, _timeToY(sessionStart));
      final y2 = math.min(size.height, _timeToY(sessionEnd));
      if (y2 < _visibleTop || y1 > _visibleBottom) continue;
      if (y2 - y1 < 1) continue;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y1, size.width, y2 - y1),
        Radius.circular(shapes.radius(10)),
      );

      canvas.drawRRect(rect, sleepFillPaint);
      if (session.isActive) {
        canvas.drawRRect(rect, sleepBorderPaint);
      }
    }
  }

  void _drawAlternatingColumns(Canvas canvas, Size size) {
    final totalColumnWidth = columnWidth + columnPadding;
    final altPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.05);

    // Only draw the visible vertical slice of each stripe.
    final top = math.max(0.0, _visibleTop);
    final bottom = math.min(size.height, _visibleBottom);
    if (top >= bottom) return;

    for (var i = 0; i < rows.length; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(i * totalColumnWidth, top, totalColumnWidth, bottom - top),
          altPaint,
        );
      }
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Calculate the first visible hour boundary from the scroll offset.
    final visibleStartHours = _visibleTop / pixelsPerHour;
    final startHourOffset = math.max(0, visibleStartHours.floor());
    var hour = DateTime(
        viewStart.year, viewStart.month, viewStart.day, viewStart.hour)
        .add(Duration(hours: startHourOffset));
    if (hour.isBefore(viewStart)) {
      hour = hour.add(const Duration(hours: 1));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour);
      if (y > _visibleBottom) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      hour = hour.add(const Duration(hours: 1));
    }
  }

  void _drawSessionBars(Canvas canvas, Size size) {
    final now = DateTime.now();
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

        // Skip bars entirely outside the visible viewport.
        if (y2 < _visibleTop || y1 > _visibleBottom) continue;

        if (y2 - y1 < 1) continue; // too small to draw

        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y1, columnWidth, y2 - y1),
          Radius.circular(shapes.radius(6)),
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
    final now = DateTime.now();
    if (now.isBefore(viewStart) || now.isAfter(viewEnd)) return;

    final y = _timeToY(now);
    // Skip if the now-line is outside the visible viewport (with margin for circle radius).
    if (y < _visibleTop || y > _visibleBottom) return;

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
        oldDelegate.sleepSessions != sleepSessions ||
        oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.brightness != brightness ||
        oldDelegate.viewportHeight != viewportHeight;
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
    required this.viewportHeight,
    this.scrollOffsetNotifier,
    Listenable? repaintListenable,
  }) : super(repaint: repaintListenable);

  final double pixelsPerHour;
  final DateTime viewStart;
  final DateTime viewEnd;
  final Color textColor;
  final Color gridColor;
  final double viewportHeight;
  final ValueNotifier<double>? scrollOffsetNotifier;

  static const double _bleed = 20.0; // extra margin for text labels
  double get _scrollOffset => scrollOffsetNotifier?.value ?? 0.0;
  double get _visibleTop => _scrollOffset - _bleed;
  double get _visibleBottom => _scrollOffset + viewportHeight + _bleed;

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

    // Skip ahead to the first visible hour boundary.
    final visibleStartHours = _visibleTop / pixelsPerHour;
    final skipHours = math.max(0, visibleStartHours.floor());
    // Advance by interval-aligned steps.
    final intervalsToSkip = (skipHours / hourInterval).floor();
    if (intervalsToSkip > 0) {
      hour = hour.add(Duration(hours: intervalsToSkip * hourInterval));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour);
      if (y > _visibleBottom) break;
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
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
