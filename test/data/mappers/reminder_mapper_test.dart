import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/reminder_mapper.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;

db.ReminderRow _row({
  String id = 'r-1',
  String name = 'Take meds',
  String message = 'Time to take meds',
  int trigger = 0,
  String? frequency,
  int? intervalDays,
  String? weeklyDays,
  String? timeOfDay = '09:00',
  int? delayHours,
  bool isActive = true,
  DateTime? createdAt,
  DateTime? modifiedAt,
  bool isDeleted = false,
}) {
  final now = DateTime(2026, 4, 16, 9, 0);
  return db.ReminderRow(
    id: id,
    name: name,
    message: message,
    trigger: trigger,
    frequency: frequency,
    intervalDays: intervalDays,
    weeklyDays: weeklyDays,
    timeOfDay: timeOfDay,
    delayHours: delayHours,
    isActive: isActive,
    createdAt: createdAt ?? now,
    modifiedAt: modifiedAt ?? now,
    isDeleted: isDeleted,
  );
}

void main() {
  group('ReminderMapper.toDomain frequency inference', () {
    test('null frequency + null intervalDays -> daily', () {
      final row = _row(frequency: null, intervalDays: null);
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.daily);
      expect(model.weeklyDays, isNull);
    });

    test('null frequency + intervalDays == 1 -> daily', () {
      final row = _row(frequency: null, intervalDays: 1);
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.daily);
    });

    test('null frequency + intervalDays == 3 -> interval', () {
      final row = _row(frequency: null, intervalDays: 3);
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.interval);
      expect(model.intervalDays, 3);
    });

    test('frequency = "weekly" with weekly_days = "[1,3,5]" -> weekly + parsed',
        () {
      final row = _row(
        frequency: 'weekly',
        weeklyDays: '[1,3,5]',
      );
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.weekly);
      expect(model.weeklyDays, [1, 3, 5]);
    });

    test('corrupt frequency "garbage" falls back to null-case logic (interval)',
        () {
      final row = _row(frequency: 'garbage', intervalDays: 5);
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.interval);
    });

    test('corrupt frequency "garbage" with null intervalDays -> daily', () {
      final row = _row(frequency: 'garbage', intervalDays: null);
      final model = ReminderMapper.toDomain(row);
      expect(model.frequency, domain.ReminderFrequency.daily);
    });

    test('corrupt frequency does not throw', () {
      expect(
        () => ReminderMapper.toDomain(_row(frequency: 'garbage')),
        returnsNormally,
      );
    });
  });

  group('ReminderMapper round-trip', () {
    test('weekly with weeklyDays [0, 6] survives domain -> companion -> row',
        () {
      final createdAt = DateTime(2026, 4, 16, 9, 0);
      final modifiedAt = DateTime(2026, 4, 16, 10, 0);
      final original = domain.Reminder(
        id: 'r-weekly',
        name: 'Weekend check-in',
        message: 'How are you?',
        trigger: domain.ReminderTrigger.scheduled,
        frequency: domain.ReminderFrequency.weekly,
        weeklyDays: const [0, 6],
        timeOfDay: '20:30',
        isActive: true,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
      );

      final companion = ReminderMapper.toCompanion(original);
      expect(companion.frequency.value, 'weekly');
      expect(companion.weeklyDays.value, jsonEncode(const [0, 6]));

      final row = db.ReminderRow(
        id: companion.id.value,
        name: companion.name.value,
        message: companion.message.value,
        trigger: companion.trigger.value,
        frequency: companion.frequency.value,
        intervalDays: companion.intervalDays.value,
        weeklyDays: companion.weeklyDays.value,
        timeOfDay: companion.timeOfDay.value,
        delayHours: companion.delayHours.value,
        isActive: companion.isActive.value,
        createdAt: companion.createdAt.value,
        modifiedAt: companion.modifiedAt.value,
        isDeleted: false,
      );

      final restored = ReminderMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.message, original.message);
      expect(restored.trigger, original.trigger);
      expect(restored.frequency, original.frequency);
      expect(restored.weeklyDays, original.weeklyDays);
      expect(restored.timeOfDay, original.timeOfDay);
      expect(restored.isActive, original.isActive);
      expect(restored.createdAt, original.createdAt);
      expect(restored.modifiedAt, original.modifiedAt);
    });

    test('daily with null weeklyDays round-trips', () {
      final now = DateTime(2026, 4, 16, 9, 0);
      final original = domain.Reminder(
        id: 'r-daily',
        name: 'Daily',
        message: 'Daily message',
        frequency: domain.ReminderFrequency.daily,
        weeklyDays: null,
        timeOfDay: '08:00',
        createdAt: now,
        modifiedAt: now,
      );

      final companion = ReminderMapper.toCompanion(original);
      expect(companion.frequency.value, 'daily');
      expect(companion.weeklyDays.value, isNull);

      final row = db.ReminderRow(
        id: companion.id.value,
        name: companion.name.value,
        message: companion.message.value,
        trigger: companion.trigger.value,
        frequency: companion.frequency.value,
        intervalDays: companion.intervalDays.value,
        weeklyDays: companion.weeklyDays.value,
        timeOfDay: companion.timeOfDay.value,
        delayHours: companion.delayHours.value,
        isActive: companion.isActive.value,
        createdAt: companion.createdAt.value,
        modifiedAt: companion.modifiedAt.value,
        isDeleted: false,
      );

      final restored = ReminderMapper.toDomain(row);
      expect(restored.frequency, domain.ReminderFrequency.daily);
      expect(restored.weeklyDays, isNull);
    });
  });
}
