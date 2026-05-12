import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

part 'fronting_analytics.freezed.dart';
part 'fronting_analytics.g.dart';

enum TimeBucket {
  morning, // 6am - 12pm
  afternoon, // 12pm - 6pm
  evening, // 6pm - 12am
  night; // 12am - 6am

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    TimeBucket.morning => l10n.timeOfDayMorning,
    TimeBucket.afternoon => l10n.timeOfDayAfternoon,
    TimeBucket.evening => l10n.timeOfDayEvening,
    TimeBucket.night => l10n.timeOfDayNight,
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
    /// System-wide median session length across the range. `Duration.zero`
    /// when there are no sessions.
    @Default(Duration.zero) Duration medianSession,
    @Default([]) List<CoFrontingPair> topCoFrontingPairs,
    /// Total clamped sleep time across the range. Sleep that overlaps a
    /// no-fronter window is already subtracted from [totalGapTime]; this
    /// exposes the underlying sleep total so UIs can surface it separately
    /// without re-querying the sleep DAO.
    @Default(Duration.zero) Duration totalSleepTime,
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

/// A pair of members who co-fronted, with their total shared time.
@freezed
abstract class CoFrontingPair with _$CoFrontingPair {
  const factory CoFrontingPair({
    /// Member ID that comes first alphabetically.
    required String memberIdA,
    required String memberIdB,
    required Duration totalTime,
  }) = _CoFrontingPair;

  factory CoFrontingPair.fromJson(Map<String, dynamic> json) =>
      _$CoFrontingPairFromJson(json);
}
