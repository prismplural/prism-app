import 'package:freezed_annotation/freezed_annotation.dart';

part 'habit_completion.freezed.dart';
part 'habit_completion.g.dart';

@freezed
abstract class HabitCompletion with _$HabitCompletion {
  const HabitCompletion._();

  const factory HabitCompletion({
    required String id,
    required String habitId,
    required DateTime completedAt,
    String? completedByMemberId,
    String? notes,
    @Default(false) bool wasFronting,
    int? rating,
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) = _HabitCompletion;

  factory HabitCompletion.fromJson(Map<String, dynamic> json) =>
      _$HabitCompletionFromJson(json);
}
