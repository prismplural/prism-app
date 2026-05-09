import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/data/mappers/habit_mapper.dart';
import 'package:prism_plurality/data/mappers/habit_completion_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
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
    final existingRow = await _dao.getHabitByIdRow(habit.id);
    if (existingRow == null || existingRow.isDeleted) return;

    final changedFields = diffSyncFields(
      _habitFieldsFromRow(existingRow),
      _habitFields(habit),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialHabitCompanion(changedFields);
    final affected = await _dao.updateHabitById(habit.id, companion);
    if (affected != 1) return;

    await syncRecordUpdate(_habitTable, habit.id, changedFields);
  }

  @override
  Future<void> deleteHabit(String id) async {
    final completions = await _dao.deleteHabit(id);
    for (final completion in completions) {
      await syncRecordDelete(_completionTable, completion.id);
    }
    await syncRecordDelete(_habitTable, id);
  }

  @override
  Future<int> updateHabitFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    final existingRow = await _dao.getHabitByIdRow(id);
    if (existingRow == null || existingRow.isDeleted) return 0;

    final patch = diffSyncFields(
      _habitFieldsFromRow(existingRow),
      _knownHabitFields(changedFields),
    );
    if (patch.isEmpty) return 1; // no-op success for an active row

    final companion = _partialHabitCompanion(patch);
    final affected = await _dao.updateHabitById(id, companion);
    if (affected != 1) return affected;

    await syncRecordUpdate(_habitTable, id, patch);
    return affected;
  }

  @override
  Future<List<domain.HabitCompletion>> getAllCompletions() async {
    final rows = await _dao.getAllCompletions();
    return rows.map(HabitCompletionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.HabitCompletion>> watchAllCompletions() {
    return _dao.watchAllCompletions().map(
      (rows) => rows.map(HabitCompletionMapper.toDomain).toList(),
    );
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
    DateTime start,
    DateTime end,
  ) {
    return _dao
        .watchCompletionsForDateRange(start, end)
        .map((rows) => rows.map(HabitCompletionMapper.toDomain).toList());
  }

  @override
  Future<int> createCompletion(domain.HabitCompletion completion) async {
    final companion = HabitCompletionMapper.toCompanion(completion);
    final affected = await _dao.createCompletion(companion);
    if (affected != 1) return affected;
    await syncRecordCreate(
      _completionTable,
      completion.id,
      _completionFields(completion),
    );
    return affected;
  }

  @override
  Future<int> deleteCompletion(String id) async {
    final affected = await _dao.deleteCompletion(id);
    if (affected != 1) return affected;
    await syncRecordDelete(_completionTable, id);
    return affected;
  }

  @override
  Future<domain.HabitCompletion?> getCompletionById(String id) async {
    final row = await _dao.getCompletionByIdRow(id);
    if (row == null || row.isDeleted) return null;
    return HabitCompletionMapper.toDomain(row);
  }

  @override
  Future<int> updateCompletionFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    final existingRow = await _dao.getCompletionByIdRow(id);
    if (existingRow == null || existingRow.isDeleted) return 0;

    final patch = diffSyncFields(
      _completionFieldsFromRow(existingRow),
      _knownCompletionFields(changedFields),
    );
    if (patch.isEmpty) return 1; // no-op success for an active row

    final companion = _partialCompletionCompanion(patch);
    final affected = await _dao.updateCompletionById(id, companion);
    if (affected != 1) return affected;

    await syncRecordUpdate(_completionTable, id, patch);
    return affected;
  }

  db.HabitsCompanion _partialHabitCompanion(Map<String, dynamic> fields) {
    return db.HabitsCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      description: fields.containsKey('description')
          ? Value(fields['description'] as String?)
          : const Value.absent(),
      icon: fields.containsKey('icon')
          ? Value(fields['icon'] as String?)
          : const Value.absent(),
      colorHex: fields.containsKey('color_hex')
          ? Value(fields['color_hex'] as String?)
          : const Value.absent(),
      isActive: fields.containsKey('is_active')
          ? Value(fields['is_active'] as bool)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(_parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      modifiedAt: fields.containsKey('modified_at')
          ? Value(_parseSyncDateTime(fields['modified_at']))
          : const Value.absent(),
      frequency: fields.containsKey('frequency')
          ? Value(fields['frequency'] as String)
          : const Value.absent(),
      weeklyDays: fields.containsKey('weekly_days')
          ? Value(fields['weekly_days'] as String?)
          : const Value.absent(),
      intervalDays: fields.containsKey('interval_days')
          ? Value(fields['interval_days'] as int?)
          : const Value.absent(),
      reminderTime: fields.containsKey('reminder_time')
          ? Value(fields['reminder_time'] as String?)
          : const Value.absent(),
      notificationsEnabled: fields.containsKey('notifications_enabled')
          ? Value(fields['notifications_enabled'] as bool)
          : const Value.absent(),
      notificationMessage: fields.containsKey('notification_message')
          ? Value(fields['notification_message'] as String?)
          : const Value.absent(),
      assignedMemberId: fields.containsKey('assigned_member_id')
          ? Value(fields['assigned_member_id'] as String?)
          : const Value.absent(),
      onlyNotifyWhenFronting: fields.containsKey('only_notify_when_fronting')
          ? Value(fields['only_notify_when_fronting'] as bool)
          : const Value.absent(),
      isPrivate: fields.containsKey('is_private')
          ? Value(fields['is_private'] as bool)
          : const Value.absent(),
      currentStreak: fields.containsKey('current_streak')
          ? Value(fields['current_streak'] as int)
          : const Value.absent(),
      bestStreak: fields.containsKey('best_streak')
          ? Value(fields['best_streak'] as int)
          : const Value.absent(),
      totalCompletions: fields.containsKey('total_completions')
          ? Value(fields['total_completions'] as int)
          : const Value.absent(),
    );
  }

  db.HabitCompletionsCompanion _partialCompletionCompanion(
    Map<String, dynamic> fields,
  ) {
    return db.HabitCompletionsCompanion(
      completedAt: fields.containsKey('completed_at')
          ? Value(_parseSyncDateTime(fields['completed_at']))
          : const Value.absent(),
      completedByMemberId: fields.containsKey('completed_by_member_id')
          ? Value(fields['completed_by_member_id'] as String?)
          : const Value.absent(),
      notes: fields.containsKey('notes')
          ? Value(fields['notes'] as String?)
          : const Value.absent(),
      wasFronting: fields.containsKey('was_fronting')
          ? Value(fields['was_fronting'] as bool)
          : const Value.absent(),
      rating: fields.containsKey('rating')
          ? Value(fields['rating'] as int?)
          : const Value.absent(),
      modifiedAt: fields.containsKey('modified_at')
          ? Value(_parseSyncDateTime(fields['modified_at']))
          : const Value.absent(),
    );
  }

  DateTime _parseSyncDateTime(Object? value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static const _habitPatchKeys = {
    'name',
    'description',
    'icon',
    'color_hex',
    'is_active',
    'created_at',
    'modified_at',
    'frequency',
    'weekly_days',
    'interval_days',
    'reminder_time',
    'notifications_enabled',
    'notification_message',
    'assigned_member_id',
    'only_notify_when_fronting',
    'is_private',
    'current_streak',
    'best_streak',
    'total_completions',
  };

  static const _completionPatchKeys = {
    'completed_at',
    'completed_by_member_id',
    'notes',
    'was_fronting',
    'rating',
    'modified_at',
  };

  Map<String, dynamic> _knownHabitFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final entry in fields.entries) {
      if (_habitPatchKeys.contains(entry.key)) {
        out[entry.key] = _normalizePatchValue(entry.key, entry.value);
      }
    }
    return out;
  }

  Map<String, dynamic> _knownCompletionFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final entry in fields.entries) {
      if (_completionPatchKeys.contains(entry.key)) {
        out[entry.key] = _normalizePatchValue(entry.key, entry.value);
      }
    }
    return out;
  }

  Object? _normalizePatchValue(String key, Object? value) {
    if ((key == 'created_at' ||
            key == 'modified_at' ||
            key == 'completed_at') &&
        value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    return value;
  }

  Map<String, dynamic> _habitFields(domain.Habit h) {
    return {
      'name': h.name,
      'description': h.description,
      'icon': h.icon,
      'color_hex': h.colorHex,
      'is_active': h.isActive,
      'created_at': h.createdAt.toUtc().toIso8601String(),
      'modified_at': h.modifiedAt.toUtc().toIso8601String(),
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

  Map<String, dynamic> _habitFieldsFromRow(db.Habit h) {
    return {
      'name': h.name,
      'description': h.description,
      'icon': h.icon,
      'color_hex': h.colorHex,
      'is_active': h.isActive,
      'created_at': h.createdAt.toUtc().toIso8601String(),
      'modified_at': h.modifiedAt.toUtc().toIso8601String(),
      'frequency': h.frequency,
      'weekly_days': h.weeklyDays,
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
      'is_deleted': h.isDeleted,
    };
  }

  Map<String, dynamic> _completionFieldsFromRow(db.HabitCompletion c) {
    return {
      'habit_id': c.habitId,
      'completed_at': c.completedAt.toUtc().toIso8601String(),
      'completed_by_member_id': c.completedByMemberId,
      'notes': c.notes,
      'was_fronting': c.wasFronting,
      'rating': c.rating,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'modified_at': c.modifiedAt.toUtc().toIso8601String(),
      'is_deleted': c.isDeleted,
    };
  }

  Map<String, dynamic> debugHabitFields(domain.Habit h) => _habitFields(h);

  Map<String, dynamic> debugHabitChangedFields(
    domain.Habit previous,
    domain.Habit next,
  ) => diffSyncFields(_habitFields(previous), _habitFields(next));

  Map<String, dynamic> _completionFields(domain.HabitCompletion c) {
    return {
      'habit_id': c.habitId,
      'completed_at': c.completedAt.toUtc().toIso8601String(),
      'completed_by_member_id': c.completedByMemberId,
      'notes': c.notes,
      'was_fronting': c.wasFronting,
      'rating': c.rating,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'modified_at': c.modifiedAt.toUtc().toIso8601String(),
      'is_deleted': false,
    };
  }
}
