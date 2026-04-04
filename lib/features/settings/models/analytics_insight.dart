import 'package:freezed_annotation/freezed_annotation.dart';

part 'analytics_insight.freezed.dart';

enum AnalyticsInsightType {
  gapAlert,
  quietMember,
  sessionDrift,
  coFrontingHighlight,
  timeOfDayShift,
}

enum AnalyticsInsightIconType {
  clockCountdown,
  moonStars,
  arrowsHorizontal,
  usersThree,
  sun,
  moon,
}

@freezed
abstract class AnalyticsInsight with _$AnalyticsInsight {
  const factory AnalyticsInsight({
    required AnalyticsInsightType type,
    required AnalyticsInsightIconType iconType,
    required String headline,
    required String body,
    required int signalStrength,
  }) = _AnalyticsInsight;
  // No fromJson — not persisted
}
