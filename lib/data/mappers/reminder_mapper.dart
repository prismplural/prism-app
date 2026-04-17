import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;

class ReminderMapper {
  ReminderMapper._();

  static domain.Reminder toDomain(ReminderRow row) {
    final frequency = domain.ReminderFrequency.values.firstWhere(
      (f) => f.name == row.frequency,
      orElse: () => (row.intervalDays != null && row.intervalDays! > 1)
          ? domain.ReminderFrequency.interval
          : domain.ReminderFrequency.daily,
    );
    final trigger =
        row.trigger >= 0 && row.trigger < domain.ReminderTrigger.values.length
            ? domain.ReminderTrigger.values[row.trigger]
            // Corrupt/future-version row: default to scheduled (the common case
            // for existing reminders) instead of crashing.
            : domain.ReminderTrigger.scheduled;

    return domain.Reminder(
      id: row.id,
      name: row.name,
      message: row.message,
      trigger: trigger,
      frequency: frequency,
      weeklyDays: _parseWeeklyDays(row.weeklyDays),
      intervalDays: row.intervalDays,
      timeOfDay: row.timeOfDay,
      delayHours: row.delayHours,
      isActive: row.isActive,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  static RemindersCompanion toCompanion(domain.Reminder model) {
    return RemindersCompanion(
      id: Value(model.id),
      name: Value(model.name),
      message: Value(model.message),
      trigger: Value(model.trigger.index),
      frequency: Value(model.frequency.name),
      weeklyDays: model.weeklyDays != null
          ? Value(jsonEncode(model.weeklyDays))
          : const Value(null),
      intervalDays: Value(model.intervalDays),
      timeOfDay: Value(model.timeOfDay),
      delayHours: Value(model.delayHours),
      isActive: Value(model.isActive),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
    );
  }
}

/// Defensively parses the `weekly_days` JSON column.
///
/// Returns `null` for any of: null input, malformed JSON, non-list JSON
/// (e.g. `"{}"`), lists containing non-int elements, out-of-range weekday
/// values, or an empty list. A single bad row from a peer device must not
/// crash screens that load reminders.
List<int>? _parseWeeklyDays(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final out = <int>[];
    for (final v in decoded) {
      if (v is! int) return null;
      if (v < 0 || v > 6) return null;
      out.add(v);
    }
    if (out.isEmpty) return null;
    return out;
  } catch (_) {
    return null;
  }
}
