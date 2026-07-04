import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_geometry.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_time_label_formatter.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

/// A tappable region on the timeline canvas corresponding to one session bar.
typedef TimelineHitZone = ({
  Rect rect,
  FrontingSession session,
  int columnIndex,
});

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
  double _boundedScrollOffset(Size size) =>
      _geometry(size).boundedScrollOffset();

  double _visibleTop(Size size) => _boundedScrollOffset(size) - _bleed;
  double _visibleBottom(Size size) =>
      _boundedScrollOffset(size) + viewportHeight + _bleed;

  TimelineGeometry _geometry(Size size) {
    return TimelineGeometry(
      viewStart: viewStart,
      viewEnd: viewEnd,
      pixelsPerHour: pixelsPerHour,
      viewportHeight: viewportHeight,
      contentHeight: size.height,
      scrollOffset: _scrollOffset,
    );
  }

  double _timeToY(DateTime time, Size size) =>
      _geometry(size).timeToContentY(time);

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

        final y1 = math.max(0.0, _timeToY(sessionStart, size));
        final y2 = math.min(size.height, _timeToY(sessionEnd, size));

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
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
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

      final y1 = math.max(0.0, _timeToY(sessionStart, size));
      final y2 = math.min(size.height, _timeToY(sessionEnd, size));
      if (y2 < visibleTop || y1 > visibleBottom) continue;
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
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
    final totalColumnWidth = columnWidth + columnPadding;
    final altPaint = Paint()..color = onSurfaceColor.withValues(alpha: 0.05);

    // Only draw the visible vertical slice of each stripe.
    final top = math.max(0.0, visibleTop);
    final bottom = math.min(size.height, visibleBottom);
    if (top >= bottom) return;

    for (var i = 0; i < rows.length; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(
            i * totalColumnWidth,
            top,
            totalColumnWidth,
            bottom - top,
          ),
          altPaint,
        );
      }
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size) {
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
    final gridPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    final dayBoundaryPaint = Paint()
      ..color = onSurfaceColor.withValues(alpha: 0.18)
      ..strokeWidth = 1.0;

    // Calculate the first visible hour boundary from the scroll offset.
    final visibleStartHours = visibleTop / pixelsPerHour;
    final startHourOffset = math.max(0, visibleStartHours.floor());
    var hour = DateTime(
      viewStart.year,
      viewStart.month,
      viewStart.day,
      viewStart.hour,
    ).add(Duration(hours: startHourOffset));
    if (hour.isBefore(viewStart)) {
      hour = hour.add(const Duration(hours: 1));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour, size);
      if (y > visibleBottom) break;
      final paint = hour.hour == 0 ? dayBoundaryPaint : gridPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      hour = hour.add(const Duration(hours: 1));
    }
  }

  void _drawSessionBars(Canvas canvas, Size size) {
    final now = DateTime.now();
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
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
        if (sessionEnd.isBefore(viewStart) || sessionStart.isAfter(viewEnd)) {
          continue;
        }

        final y1 = math.max(0.0, _timeToY(sessionStart, size));
        final y2 = math.min(size.height, _timeToY(sessionEnd, size));

        // Skip bars entirely outside the visible viewport.
        if (y2 < visibleTop || y1 > visibleBottom) continue;

        if (y2 - y1 < 1) continue; // too small to draw

        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y1, columnWidth, y2 - y1),
          Radius.circular(shapes.radius(6)),
        );

        // Fill
        final barPaint = Paint()
          ..color = memberColor.withValues(
            alpha: session.isActive ? 0.8 : 0.65,
          );
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
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
    if (now.isBefore(viewStart) || now.isAfter(viewEnd)) return;

    final y = _timeToY(now, size);
    // Skip if the now-line is outside the visible viewport (with margin for circle radius).
    if (y < visibleTop || y > visibleBottom) return;

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
class TimelineTimeGutterPainter extends CustomPainter {
  TimelineTimeGutterPainter({
    required this.pixelsPerHour,
    required this.viewStart,
    required this.viewEnd,
    required this.textColor,
    required this.gridColor,
    required this.viewportHeight,
    required this.locale,
    required this.textScaler,
    required this.alwaysUse24HourFormat,
    this.scrollOffsetNotifier,
    Listenable? repaintListenable,
  }) : _formatter = TimelineTimeLabelFormatter(
         locale: locale,
         alwaysUse24HourFormat: alwaysUse24HourFormat,
       ),
       super(repaint: repaintListenable);

  final double pixelsPerHour;
  final DateTime viewStart;
  final DateTime viewEnd;
  final Color textColor;
  final Color gridColor;
  final double viewportHeight;
  final String locale;
  final TextScaler textScaler;
  final bool alwaysUse24HourFormat;
  final ValueNotifier<double>? scrollOffsetNotifier;
  final TimelineTimeLabelFormatter _formatter;

  static const double _bleed = 20.0; // extra margin for text labels
  double get _scrollOffset => scrollOffsetNotifier?.value ?? 0.0;
  double _boundedScrollOffset(Size size) =>
      _geometry(size).boundedScrollOffset();

  double _visibleTop(Size size) => _boundedScrollOffset(size) - _bleed;
  double _visibleBottom(Size size) =>
      _boundedScrollOffset(size) + viewportHeight + _bleed;

  TimelineGeometry _geometry(Size size) {
    return TimelineGeometry(
      viewStart: viewStart,
      viewEnd: viewEnd,
      pixelsPerHour: pixelsPerHour,
      viewportHeight: viewportHeight,
      contentHeight: size.height,
      scrollOffset: _scrollOffset,
    );
  }

  double _timeToY(DateTime time, Size size) =>
      _geometry(size).timeToContentY(time);

  @override
  void paint(Canvas canvas, Size size) {
    final visibleTop = _visibleTop(size);
    final visibleBottom = _visibleBottom(size);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    final midnightPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;
    final labelStyle = TextStyle(color: textColor, fontSize: 10);
    final hourInterval = _formatter.hourInterval(
      pixelsPerHour: pixelsPerHour,
      style: labelStyle,
      textScaler: textScaler,
    );

    var hour = DateTime(
      viewStart.year,
      viewStart.month,
      viewStart.day,
      viewStart.hour,
    );
    if (hour.isBefore(viewStart)) {
      hour = hour.add(const Duration(hours: 1));
    }

    // Align to interval
    while (hour.hour % hourInterval != 0) {
      hour = hour.add(const Duration(hours: 1));
    }

    // Skip ahead to the first visible hour boundary.
    final visibleStartHours = visibleTop / pixelsPerHour;
    final skipHours = math.max(0, visibleStartHours.floor());
    // Advance by interval-aligned steps.
    final intervalsToSkip = (skipHours / hourInterval).floor();
    if (intervalsToSkip > 0) {
      hour = hour.add(Duration(hours: intervalsToSkip * hourInterval));
    }

    while (hour.isBefore(viewEnd)) {
      final y = _timeToY(hour, size);
      if (y > visibleBottom) break;
      final isMidnight = hour.hour == 0;

      // Tick mark (full-width heavier line at midnight)
      if (isMidnight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), midnightPaint);
      } else {
        canvas.drawLine(
          Offset(size.width - 8, y),
          Offset(size.width, y),
          gridPaint,
        );
      }

      final label = _formatter.bestLabel(
        time: hour,
        style: labelStyle,
        textScaler: textScaler,
        maxWidth: size.width - 14,
        textDirection: TextDirection.ltr,
      );
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: textScaler,
      )..layout();

      canvas.save();
      canvas.clipRect(Offset.zero & size);
      textPainter.paint(
        canvas,
        Offset(size.width - 12 - textPainter.width, y - textPainter.height / 2),
      );
      canvas.restore();

      hour = hour.add(Duration(hours: hourInterval));
    }
  }

  @override
  bool shouldRepaint(covariant TimelineTimeGutterPainter oldDelegate) {
    return oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.textColor != textColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.viewportHeight != viewportHeight ||
        oldDelegate.locale != locale ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.alwaysUse24HourFormat != alwaysUse24HourFormat;
  }
}
