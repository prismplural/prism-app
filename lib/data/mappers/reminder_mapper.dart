import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;

class ReminderMapper {
  ReminderMapper._();

  static domain.Reminder toDomain(ReminderRow row) {
    return domain.Reminder(
      id: row.id,
      name: row.name,
      message: row.message,
      trigger: domain.ReminderTrigger.values[row.trigger],
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
      intervalDays: Value(model.intervalDays),
      timeOfDay: Value(model.timeOfDay),
      delayHours: Value(model.delayHours),
      isActive: Value(model.isActive),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
    );
  }
}
