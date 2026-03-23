import 'package:freezed_annotation/freezed_annotation.dart';

part 'fronting_analytics.freezed.dart';
part 'fronting_analytics.g.dart';

enum TimeBucket {
  morning, // 6am - 12pm
  afternoon, // 12pm - 6pm
  evening, // 6pm - 12am
  night; // 12am - 6am

  String get label => switch (this) {
        TimeBucket.morning => 'Morning',
        TimeBucket.afternoon => 'Afternoon',
        TimeBucket.evening => 'Evening',
        TimeBucket.night => 'Night',
      };

  static TimeBucket fromHour(int hour) {
    if (hour >= 6 && hour < 12) return TimeBucket.morning;
    if (hour >= 12 && hour < 18) return TimeBucket.afternoon;
    if (hour >= 18) return TimeBucket.evening;
    return TimeBucket.night;
  }
}

@freezed
abstract class FrontingAnalytics with _$FrontingAnalytics {
  const factory FrontingAnalytics({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required Duration totalTrackedTime,
    required Duration totalGapTime,
    required int totalSessions,
    required int uniqueFronters,
    required double switchesPerDay,
    required List<MemberAnalytics> memberStats,
  }) = _FrontingAnalytics;

  factory FrontingAnalytics.fromJson(Map<String, dynamic> json) =>
      _$FrontingAnalyticsFromJson(json);
}

@freezed
abstract class MemberAnalytics with _$MemberAnalytics {
  const factory MemberAnalytics({
    required String memberId,
    required Duration totalTime,
    required double percentageOfTotal,
    required int sessionCount,
    required Duration averageDuration,
    required Duration medianDuration,
    required Duration shortestSession,
    required Duration longestSession,
    required Map<String, int> timeOfDayBreakdown,
  }) = _MemberAnalytics;

  factory MemberAnalytics.fromJson(Map<String, dynamic> json) =>
      _$MemberAnalyticsFromJson(json);
}
