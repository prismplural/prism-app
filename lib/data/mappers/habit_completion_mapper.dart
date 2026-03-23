import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart' as domain;

class HabitCompletionMapper {
  HabitCompletionMapper._();

  static domain.HabitCompletion toDomain(HabitCompletion row) {
    return domain.HabitCompletion(
      id: row.id,
      habitId: row.habitId,
      completedAt: row.completedAt,
      completedByMemberId: row.completedByMemberId,
      notes: row.notes,
      wasFronting: row.wasFronting,
      rating: row.rating,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  static HabitCompletionsCompanion toCompanion(
      domain.HabitCompletion model) {
    return HabitCompletionsCompanion(
      id: Value(model.id),
      habitId: Value(model.habitId),
      completedAt: Value(model.completedAt),
      completedByMemberId: Value(model.completedByMemberId),
      notes: Value(model.notes),
      wasFronting: Value(model.wasFronting),
      rating: Value(model.rating),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
    );
  }
}
