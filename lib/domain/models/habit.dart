import 'package:freezed_annotation/freezed_annotation.dart';

part 'habit.freezed.dart';
part 'habit.g.dart';

enum HabitFrequency {
  daily,
  weekly,
  interval,
  custom;

  String get label => switch (this) {
        HabitFrequency.daily => 'Daily',
        HabitFrequency.weekly => 'Weekly',
        HabitFrequency.interval => 'Every X days',
        HabitFrequency.custom => 'Custom',
      };
}

enum StatisticsTimeframe {
  week,
  month,
  year,
  all;

  String get label => switch (this) {
        StatisticsTimeframe.week => 'Week',
        StatisticsTimeframe.month => 'Month',
        StatisticsTimeframe.year => 'Year',
        StatisticsTimeframe.all => 'All Time',
      };

  /// Returns the date range for this timeframe (start date, inclusive).
  DateTime get startDate {
    final now = DateTime.now();
    return switch (this) {
      StatisticsTimeframe.week =>
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7)),
      StatisticsTimeframe.month =>
        DateTime(now.year, now.month - 1, now.day),
      StatisticsTimeframe.year =>
        DateTime(now.year - 1, now.month, now.day),
      StatisticsTimeframe.all =>
        DateTime(2000),
    };
  }
}

class HabitStats {
  final int totalCompletions;
  final int expectedCompletions;
  final double completionRate;
  final int currentStreak;
  final int bestStreak;
  final double? averageRating;
  final Map<String, int> completionsByMember;

  const HabitStats({
    required this.totalCompletions,
    required this.expectedCompletions,
    required this.completionRate,
    required this.currentStreak,
    required this.bestStreak,
    this.averageRating,
    this.completionsByMember = const {},
  });
}

@freezed
abstract class Habit with _$Habit {
  const Habit._();

  const factory Habit({
    required String id,
    required String name,
    String? description,
    String? icon,
    String? colorHex,
    @Default(true) bool isActive,
    required DateTime createdAt,
    required DateTime modifiedAt,
    @Default(HabitFrequency.daily) HabitFrequency frequency,
    List<int>? weeklyDays,
    int? intervalDays,
    String? reminderTime,
    @Default(false) bool notificationsEnabled,
    String? notificationMessage,
    String? assignedMemberId,
    @Default(false) bool onlyNotifyWhenFronting,
    @Default(false) bool isPrivate,
    @Default(0) int currentStreak,
    @Default(0) int bestStreak,
    @Default(0) int totalCompletions,
  }) = _Habit;

  factory Habit.fromJson(Map<String, dynamic> json) => _$HabitFromJson(json);
}
