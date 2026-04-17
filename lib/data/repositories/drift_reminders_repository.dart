import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/data/mappers/reminder_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';

class DriftRemindersRepository
    with SyncRecordMixin
    implements RemindersRepository {
  final RemindersDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'reminders';

  DriftRemindersRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.Reminder>> watchAll() {
    return _dao.watchAll().map(
      (rows) => rows.map(ReminderMapper.toDomain).toList(),
    );
  }

  @override
  Stream<List<domain.Reminder>> watchActive() {
    return _dao.watchActive().map(
      (rows) => rows.map(ReminderMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.Reminder?> getById(String id) async {
    final row = await _dao.getById(id);
    return row != null ? ReminderMapper.toDomain(row) : null;
  }

  @override
  Future<void> create(domain.Reminder reminder) async {
    final companion = ReminderMapper.toCompanion(reminder);
    await _dao.create(companion);
    await syncRecordCreate(_table, reminder.id, _fields(reminder));
  }

  @override
  Future<void> update(domain.Reminder reminder) async {
    final companion = ReminderMapper.toCompanion(reminder);
    await _dao.updateReminder(reminder.id, companion);
    await syncRecordUpdate(_table, reminder.id, _fields(reminder));
  }

  @override
  Future<void> delete(String id) async {
    await _dao.softDelete(id);
    await syncRecordDelete(_table, id);
  }

  Map<String, dynamic> _fields(domain.Reminder r) {
    return {
      'name': r.name,
      'message': r.message,
      'trigger': r.trigger.index,
      'interval_days': r.intervalDays,
      'time_of_day': r.timeOfDay,
      'delay_hours': r.delayHours,
      'frequency': r.frequency.name,
      'weekly_days': r.weeklyDays != null ? jsonEncode(r.weeklyDays) : null,
      'is_active': r.isActive,
      'created_at': r.createdAt.toIso8601String(),
      'modified_at': r.modifiedAt.toIso8601String(),
      'is_deleted': false,
    };
  }
}
