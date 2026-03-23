import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/habit.dart' as domain;

class HabitMapper {
  HabitMapper._();

  static domain.Habit toDomain(Habit row) {
    return domain.Habit(
      id: row.id,
      name: row.name,
      description: row.description,
      icon: row.icon,
      colorHex: row.colorHex,
      isActive: row.isActive,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
      frequency: domain.HabitFrequency.values.firstWhere(
        (f) => f.name == row.frequency,
        orElse: () => domain.HabitFrequency.daily,
      ),
      weeklyDays: row.weeklyDays != null
          ? (jsonDecode(row.weeklyDays!) as List).cast<int>()
          : null,
      intervalDays: row.intervalDays,
      reminderTime: row.reminderTime,
      notificationsEnabled: row.notificationsEnabled,
      notificationMessage: row.notificationMessage,
      assignedMemberId: row.assignedMemberId,
      onlyNotifyWhenFronting: row.onlyNotifyWhenFronting,
      isPrivate: row.isPrivate,
      currentStreak: row.currentStreak,
      bestStreak: row.bestStreak,
      totalCompletions: row.totalCompletions,
    );
  }

  static HabitsCompanion toCompanion(domain.Habit model) {
    return HabitsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      description: Value(model.description),
      icon: Value(model.icon),
      colorHex: Value(model.colorHex),
      isActive: Value(model.isActive),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
      frequency: Value(model.frequency.name),
      weeklyDays: Value(
          model.weeklyDays != null ? jsonEncode(model.weeklyDays) : null),
      intervalDays: Value(model.intervalDays),
      reminderTime: Value(model.reminderTime),
      notificationsEnabled: Value(model.notificationsEnabled),
      notificationMessage: Value(model.notificationMessage),
      assignedMemberId: Value(model.assignedMemberId),
      onlyNotifyWhenFronting: Value(model.onlyNotifyWhenFronting),
      isPrivate: Value(model.isPrivate),
      currentStreak: Value(model.currentStreak),
      bestStreak: Value(model.bestStreak),
      totalCompletions: Value(model.totalCompletions),
    );
  }
}
