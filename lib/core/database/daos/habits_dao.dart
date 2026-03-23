import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/habits_table.dart';
import 'package:prism_plurality/core/database/tables/habit_completions_table.dart';

part 'habits_dao.g.dart';

@DriftAccessor(tables: [Habits, HabitCompletions])
class HabitsDao extends DatabaseAccessor<AppDatabase> with _$HabitsDaoMixin {
  HabitsDao(super.db);

  // ── Habits ───────────────────────────────────────────────────────

  Stream<List<Habit>> watchAllHabits() =>
      (select(habits)
            ..where((h) => h.isDeleted.equals(false))
            ..orderBy([(h) => OrderingTerm.desc(h.createdAt)]))
          .watch();

  Stream<List<Habit>> watchActiveHabits() =>
      (select(habits)
            ..where(
                (h) => h.isActive.equals(true) & h.isDeleted.equals(false))
            ..orderBy([(h) => OrderingTerm.desc(h.createdAt)]))
          .watch();

  Stream<Habit?> watchHabitById(String id) =>
      (select(habits)
            ..where((h) => h.id.equals(id) & h.isDeleted.equals(false)))
          .watchSingleOrNull();

  Future<Habit?> getHabitById(String id) =>
      (select(habits)
            ..where((h) => h.id.equals(id) & h.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<List<Habit>> getAllHabits() =>
      (select(habits)
            ..where((h) => h.isDeleted.equals(false))
            ..orderBy([(h) => OrderingTerm.desc(h.createdAt)]))
          .get();

  Future<int> createHabit(HabitsCompanion habit) =>
      into(habits).insert(habit);

  Future<void> updateHabit(String id, HabitsCompanion habit) =>
      (update(habits)..where((h) => h.id.equals(id))).write(habit);

  Future<void> deleteHabit(String id) async {
    // Soft-delete completions first
    await (update(habitCompletions)
          ..where((c) => c.habitId.equals(id)))
        .write(const HabitCompletionsCompanion(isDeleted: Value(true)));
    // Soft-delete the habit
    await (update(habits)..where((h) => h.id.equals(id))).write(
        const HabitsCompanion(isDeleted: Value(true)));
  }

  // ── Completions ──────────────────────────────────────────────────

  Stream<List<HabitCompletion>> watchCompletionsForHabit(
          String habitId) =>
      (select(habitCompletions)
            ..where((c) =>
                c.habitId.equals(habitId) & c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]))
          .watch();

  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) {
    final query = select(habitCompletions)
      ..where((c) => c.habitId.equals(habitId) & c.isDeleted.equals(false))
      ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]);
    if (since != null) {
      query.where((c) => c.completedAt.isBiggerOrEqualValue(since));
    }
    return query.get();
  }

  Stream<List<HabitCompletion>> watchCompletionsForDate(
      DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (select(habitCompletions)
          ..where((c) =>
              c.completedAt.isBiggerOrEqualValue(start) &
              c.completedAt.isSmallerThanValue(end) &
              c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]))
        .watch();
  }

  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
      DateTime start, DateTime end) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1));
    return (select(habitCompletions)
          ..where((c) =>
              c.completedAt.isBiggerOrEqualValue(rangeStart) &
              c.completedAt.isSmallerThanValue(rangeEnd) &
              c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]))
        .watch();
  }

  Future<int> createCompletion(HabitCompletionsCompanion completion) =>
      into(habitCompletions).insert(completion);

  Future<void> deleteCompletion(String id) =>
      (update(habitCompletions)..where((c) => c.id.equals(id))).write(
          const HabitCompletionsCompanion(isDeleted: Value(true)));
}
