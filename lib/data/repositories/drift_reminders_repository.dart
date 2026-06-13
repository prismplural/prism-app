import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/data/mappers/reminder_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';

class DriftRemindersRepository
    with SyncRecordMixin
    implements RemindersRepository {
  final RemindersDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  @override
  AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

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
    // Insert + create-op intent commit atomically; dispatch post-commit
    // (FFI outside the txn — reverted-revert invariant).
    await runSyncedWrite(() async {
      final companion = ReminderMapper.toCompanion(reminder);
      await _dao.create(companion);
      await syncRecordCreate(_table, reminder.id, _fields(reminder));
    });
  }

  @override
  Future<void> update(domain.Reminder reminder) async {
    // Read-diff-write + update-op intent in one atomic txn (dispatch
    // post-commit, FFI outside the txn).
    await runSyncedWrite(() async {
      final existingRow = await _dao.getById(reminder.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _reminderFieldsFromRow(existingRow),
        _fields(reminder),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialReminderCompanion(changedFields);
      await _dao.updateReminder(reminder.id, companion);
      await syncRecordUpdate(_table, reminder.id, changedFields);
    });
  }

  @override
  Future<void> delete(String id) async {
    // Tombstone path (unrecoverable): soft-delete + delete-op intent
    // commit atomically; dispatch post-commit (FFI outside the txn).
    await runSyncedWrite(() async {
      await _dao.softDelete(id);
      await syncRecordDelete(_table, id);
    });
  }

  /// Visible-for-testing: the field map this repository hands to the Rust
  /// sync engine. Exposed so a regression test can pin (a) target_member_id
  /// is emitted, and (b) every DateTime is Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugReminderFields(domain.Reminder r) => _fields(r);

  Map<String, dynamic> _fields(domain.Reminder r) => reminderFields(r);

  RemindersCompanion _partialReminderCompanion(Map<String, dynamic> fields) {
    return RemindersCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      message: fields.containsKey('message')
          ? Value(fields['message'] as String)
          : const Value.absent(),
      trigger: fields.containsKey('trigger')
          ? Value(fields['trigger'] as int)
          : const Value.absent(),
      intervalDays: fields.containsKey('interval_days')
          ? Value(fields['interval_days'] as int?)
          : const Value.absent(),
      timeOfDay: fields.containsKey('time_of_day')
          ? Value(fields['time_of_day'] as String?)
          : const Value.absent(),
      delayHours: fields.containsKey('delay_hours')
          ? Value(fields['delay_hours'] as int?)
          : const Value.absent(),
      targetMemberId: fields.containsKey('target_member_id')
          ? Value(fields['target_member_id'] as String?)
          : const Value.absent(),
      frequency: fields.containsKey('frequency')
          ? Value(fields['frequency'] as String?)
          : const Value.absent(),
      weeklyDays: fields.containsKey('weekly_days')
          ? Value(fields['weekly_days'] as String?)
          : const Value.absent(),
      isActive: fields.containsKey('is_active')
          ? Value(fields['is_active'] as bool)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      modifiedAt: fields.containsKey('modified_at')
          ? Value(parseSyncDateTime(fields['modified_at']))
          : const Value.absent(),
    );
  }

  Map<String, dynamic> _reminderFieldsFromRow(ReminderRow row) {
    // Canonicalize stored weekly_days through jsonSet so both sides of the
    // diff use the sorted-list encoding. A pre-migration row whose stored
    // JSON happens to be in non-canonical order will diff false-positive
    // once on the first edit; subsequent edits are clean. See
    // docs/plans/2026-05-25-drift-repo-patch-update-migration.md "Known
    // transients" for the rationale.
    final storedWeeklyDays = row.weeklyDays;
    String? canonicalWeeklyDays;
    if (storedWeeklyDays != null) {
      // Tolerate corrupt persisted JSON (bad encoding, wrong element type) —
      // bail out to the raw stored string so the diff falls back to a
      // one-time false-positive on the next edit rather than throwing and
      // taking the whole update path down with it. Mirrors the read-side
      // mapper's defensive parsing posture.
      try {
        final decoded = jsonDecode(storedWeeklyDays);
        if (decoded is List) {
          final ints = <int>[];
          for (final v in decoded) {
            if (v is int) {
              ints.add(v);
            } else {
              throw const FormatException('non-int element in weekly_days');
            }
          }
          canonicalWeeklyDays = jsonSet(ints);
        } else {
          canonicalWeeklyDays = storedWeeklyDays;
        }
      } on FormatException {
        canonicalWeeklyDays = storedWeeklyDays;
      }
    }

    return {
      'name': row.name,
      'message': row.message,
      'trigger': row.trigger,
      'interval_days': row.intervalDays,
      'time_of_day': row.timeOfDay,
      'delay_hours': row.delayHours,
      'target_member_id': row.targetMemberId,
      'frequency': row.frequency,
      'weekly_days': canonicalWeeklyDays,
      'is_active': row.isActive,
      'created_at': toSyncUtc(row.createdAt),
      'modified_at': toSyncUtc(row.modifiedAt),
      'is_deleted': row.isDeleted,
    };
  }

  /// Field-map builder for reminder sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `create()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> reminderFields(domain.Reminder r) {
    return {
      'name': r.name,
      'message': r.message,
      'trigger': r.trigger.index,
      'interval_days': r.intervalDays,
      'time_of_day': r.timeOfDay,
      'delay_hours': r.delayHours,
      'target_member_id': r.targetMemberId,
      'frequency': r.frequency.name,
      'weekly_days': r.weeklyDays != null ? jsonSet(r.weeklyDays!) : null,
      'is_active': r.isActive,
      'created_at': toSyncUtc(r.createdAt),
      'modified_at': toSyncUtc(r.modifiedAt),
      'is_deleted': false,
    };
  }
}
