import 'package:prism_plurality/domain/models/habit.dart' as domain;
import 'package:prism_plurality/domain/models/habit_completion.dart' as domain;

abstract class HabitRepository {
  Stream<List<domain.Habit>> watchAllHabits();
  Stream<List<domain.Habit>> watchActiveHabits();
  Stream<domain.Habit?> watchHabitById(String id);
  Future<domain.Habit?> getHabitById(String id);
  Future<List<domain.Habit>> getAllHabits();
  Future<void> createHabit(domain.Habit habit);
  Future<void> updateHabit(domain.Habit habit);
  Future<void> deleteHabit(String id);

  Future<List<domain.HabitCompletion>> getAllCompletions();
  Stream<List<domain.HabitCompletion>> watchAllCompletions();
  Stream<List<domain.HabitCompletion>> watchCompletionsForHabit(String habitId);
  Future<List<domain.HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  });
  Stream<List<domain.HabitCompletion>> watchCompletionsForDate(DateTime date);
  Stream<List<domain.HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  );
  Future<void> createCompletion(domain.HabitCompletion completion);
  Future<void> deleteCompletion(String id);

  /// Returns the completion by ID, or null if it's tombstoned/missing.
  Future<domain.HabitCompletion?> getCompletionById(String id);

  /// Updates a completion using a partial-fields patch keyed by sync wire-format
  /// names (e.g., 'notes', 'rating', 'completed_at'). Only the keys present in
  /// [changedFields] are written to the DAO and emitted via syncRecordUpdate.
  /// Unspecified fields preserve whatever value is currently in the DB —
  /// critical for field-level LWW: if another device sync-updated a different
  /// field while the editor was open, that synced value isn't clobbered here.
  ///
  /// Returns affected row count (0 if tombstoned/missing, 1 on success).
  /// Caller is responsible for including `modified_at` in [changedFields]
  /// (so CRDT field-level LWW has a fresh HLC stamp on each updated field).
  Future<int> updateCompletionFields(String id, Map<String, dynamic> changedFields);
}
