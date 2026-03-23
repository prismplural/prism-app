import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/data/mappers/habit_mapper.dart';
import 'package:prism_plurality/data/mappers/habit_completion_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/habit.dart' as domain;
import 'package:prism_plurality/domain/models/habit_completion.dart' as domain;
import 'package:prism_plurality/domain/repositories/habit_repository.dart';

class DriftHabitRepository with SyncRecordMixin implements HabitRepository {
  final HabitsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _habitTable = 'habits';
  static const _completionTable = 'habit_completions';

  DriftHabitRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.Habit>> watchAllHabits() {
    return _dao.watchAllHabits().map(
      (rows) => rows.map(HabitMapper.toDomain).toList(),
    );
  }

  @override
  Stream<List<domain.Habit>> watchActiveHabits() {
    return _dao.watchActiveHabits().map(
      (rows) => rows.map(HabitMapper.toDomain).toList(),
    );
  }

  @override
  Stream<domain.Habit?> watchHabitById(String id) {
    return _dao
        .watchHabitById(id)
        .map((row) => row != null ? HabitMapper.toDomain(row) : null);
  }

  @override
  Future<domain.Habit?> getHabitById(String id) async {
    final row = await _dao.getHabitById(id);
    return row != null ? HabitMapper.toDomain(row) : null;
  }

  @override
  Future<List<domain.Habit>> getAllHabits() async {
    final rows = await _dao.getAllHabits();
    return rows.map(HabitMapper.toDomain).toList();
  }

  @override
  Future<void> createHabit(domain.Habit habit) async {
    final companion = HabitMapper.toCompanion(habit);
    await _dao.createHabit(companion);
    await syncRecordCreate(_habitTable, habit.id, _habitFields(habit));
  }

  @override
  Future<void> updateHabit(domain.Habit habit) async {
    final companion = HabitMapper.toCompanion(habit);
    await _dao.updateHabit(habit.id, companion);
    await syncRecordUpdate(_habitTable, habit.id, _habitFields(habit));
  }

  @override
  Future<void> deleteHabit(String id) async {
    // Fetch completions before the delete so we can emit ops for them.
    final completions = await _dao.getCompletionsForHabit(id);
    await _dao.deleteHabit(id);
    for (final completion in completions) {
      await syncRecordDelete(_completionTable, completion.id);
    }
    await syncRecordDelete(_habitTable, id);
  }

  @override
  Stream<List<domain.HabitCompletion>> watchCompletionsForHabit(
    String habitId,
  ) {
    return _dao
        .watchCompletionsForHabit(habitId)
        .map((rows) => rows.map(HabitCompletionMapper.toDomain).toList());
  }

  @override
  Future<List<domain.HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async {
    final rows = await _dao.getCompletionsForHabit(habitId, since: since);
    return rows.map(HabitCompletionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.HabitCompletion>> watchCompletionsForDate(DateTime date) {
    return _dao
        .watchCompletionsForDate(date)
        .map((rows) => rows.map(HabitCompletionMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.HabitCompletion>> watchCompletionsForDateRange(
      DateTime start, DateTime end) {
    return _dao
        .watchCompletionsForDateRange(start, end)
        .map((rows) => rows.map(HabitCompletionMapper.toDomain).toList());
  }

  @override
  Future<void> createCompletion(domain.HabitCompletion completion) async {
    final companion = HabitCompletionMapper.toCompanion(completion);
    await _dao.createCompletion(companion);
    await syncRecordCreate(_completionTable, completion.id, _completionFields(completion));
  }

  @override
  Future<void> deleteCompletion(String id) async {
    await _dao.deleteCompletion(id);
    await syncRecordDelete(_completionTable, id);
  }

  Map<String, dynamic> _habitFields(domain.Habit h) {
    return {
      'name': h.name,
      'description': h.description,
      'icon': h.icon,
      'color_hex': h.colorHex,
      'is_active': h.isActive,
      'created_at': h.createdAt.toIso8601String(),
      'modified_at': h.modifiedAt.toIso8601String(),
      'frequency': h.frequency.name,
      'weekly_days': h.weeklyDays != null ? jsonEncode(h.weeklyDays) : null,
      'interval_days': h.intervalDays,
      'reminder_time': h.reminderTime,
      'notifications_enabled': h.notificationsEnabled,
      'notification_message': h.notificationMessage,
      'assigned_member_id': h.assignedMemberId,
      'only_notify_when_fronting': h.onlyNotifyWhenFronting,
      'is_private': h.isPrivate,
      'current_streak': h.currentStreak,
      'best_streak': h.bestStreak,
      'total_completions': h.totalCompletions,
      'is_deleted': false,
    };
  }

  Map<String, dynamic> _completionFields(domain.HabitCompletion c) {
    return {
      'habit_id': c.habitId,
      'completed_at': c.completedAt.toIso8601String(),
      'completed_by_member_id': c.completedByMemberId,
      'notes': c.notes,
      'was_fronting': c.wasFronting,
      'rating': c.rating,
      'created_at': c.createdAt.toIso8601String(),
      'modified_at': c.modifiedAt.toIso8601String(),
      'is_deleted': false,
    };
  }
}
