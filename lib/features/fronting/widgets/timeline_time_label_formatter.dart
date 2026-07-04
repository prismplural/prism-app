import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' hide TextDirection;

class TimelineTimeLabelFormatter {
  TimelineTimeLabelFormatter({
    required this.locale,
    required this.alwaysUse24HourFormat,
  });

  final String locale;
  final bool alwaysUse24HourFormat;
  late final DateFormat _twentyFourHourFormat = DateFormat.Hm(locale);
  late final DateFormat _twelveHourFormat = DateFormat('h a', locale);

  String normalLabel(DateTime time) {
    if (alwaysUse24HourFormat) {
      return _normalizeSpaces(_twentyFourHourFormat.format(time));
    }
    return _normalizeSpaces(_twelveHourFormat.format(time));
  }

  String? compactLabel(DateTime time) {
    if (alwaysUse24HourFormat) {
      return time.hour.toString().padLeft(2, '0');
    }
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    if (!_usesEnglishCompactMarkers) return hour.toString();
    final marker = time.hour < 12 ? 'A' : 'P';
    return '$hour$marker';
  }

  String bestLabel({
    required DateTime time,
    required TextStyle style,
    required TextScaler textScaler,
    required double maxWidth,
    required TextDirection textDirection,
  }) {
    String? fallback;
    for (final label in candidateLabels(time)) {
      fallback = label;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        maxLines: 1,
        textScaler: textScaler,
      )..layout();
      if (painter.width <= maxWidth) {
        return label;
      }
    }
    return fallback ?? normalLabel(time);
  }

  Iterable<String> candidateLabels(DateTime time) sync* {
    final normal = normalLabel(time);
    yield normal;
    final compact = compactLabel(time);
    if (compact != null && compact != normal) {
      yield compact;
    }
  }

  int hourInterval({
    required double pixelsPerHour,
    required TextStyle style,
    required TextScaler textScaler,
  }) {
    var interval = _baseHourInterval(pixelsPerHour);
    final fontSize = style.fontSize ?? 10;
    final lineHeight = textScaler.scale(fontSize) * (style.height ?? 1.2);
    while (pixelsPerHour * interval < lineHeight + 8 && interval < 24) {
      interval *= 2;
    }
    return interval.clamp(1, 24);
  }

  bool get _usesEnglishCompactMarkers {
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    return language == 'en';
  }

  int _baseHourInterval(double pixelsPerHour) {
    if (pixelsPerHour >= 80) return 1;
    if (pixelsPerHour >= 40) return 2;
    if (pixelsPerHour >= 20) return 4;
    return 6;
  }

  String _normalizeSpaces(String value) {
    return value.replaceAll(RegExp(r'[\u00a0\u202f]'), ' ');
  }
}
