import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/reminder.dart';

void main() {
  late AppDatabase db;
  late RemindersDao dao;
  late DriftRemindersRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = RemindersDao(db);
    // Pass null for sync handle — tests run without sync.
    repo = DriftRemindersRepository(dao, null);
  });

  tearDown(() => db.close());

  Reminder makeReminder({
    required String id,
    String name = 'Test Reminder',
    String message = 'Test message',
    ReminderTrigger trigger = ReminderTrigger.scheduled,
    int? intervalDays,
    String? timeOfDay,
    int? delayHours,
    bool isActive = true,
  }) {
    final now = DateTime(2026, 1, 15);
    return Reminder(
      id: id,
      name: name,
      message: message,
      trigger: trigger,
      intervalDays: intervalDays,
      timeOfDay: timeOfDay,
      delayHours: delayHours,
      isActive: isActive,
      createdAt: now,
      modifiedAt: now,
    );
  }

  group('create + watchAll round-trip', () {
    test('created reminder appears in watchAll stream', () async {
      final reminder = makeReminder(id: 'r1', name: 'Daily Check');

      await repo.create(reminder);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'r1');
      expect(all.first.name, 'Daily Check');
      expect(all.first.message, 'Test message');
      expect(all.first.trigger, ReminderTrigger.scheduled);
      expect(all.first.isActive, isTrue);
    });

    test('multiple reminders appear in watchAll', () async {
      await repo.create(makeReminder(id: 'r1', name: 'First'));
      await repo.create(makeReminder(id: 'r2', name: 'Second'));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });
  });

  group('update', () {
    test('update changes fields', () async {
      final original = makeReminder(
        id: 'r1',
        name: 'Original',
        message: 'Old message',
        isActive: true,
      );
      await repo.create(original);

      final updated = original.copyWith(
        name: 'Updated',
        message: 'New message',
        isActive: false,
        modifiedAt: DateTime(2026, 2, 1),
      );
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.name, 'Updated');
      expect(all.first.message, 'New message');
      expect(all.first.isActive, isFalse);
    });

    test('update trigger type', () async {
      final original = makeReminder(
        id: 'r1',
        trigger: ReminderTrigger.scheduled,
        intervalDays: 7,
      );
      await repo.create(original);

      final updated = original.copyWith(
        trigger: ReminderTrigger.onFrontChange,
        delayHours: 2,
      );
      await repo.update(updated);

      final all = await repo.watchAll().first;
      expect(all.first.trigger, ReminderTrigger.onFrontChange);
      expect(all.first.delayHours, 2);
    });
  });

  group('delete', () {
    test('soft-delete removes from watchAll', () async {
      await repo.create(makeReminder(id: 'r1'));
      await repo.create(makeReminder(id: 'r2'));

      await repo.delete('r1');

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'r2');
    });

    test('soft-deleted reminder not returned by getById', () async {
      await repo.create(makeReminder(id: 'r1'));
      await repo.delete('r1');

      final result = await repo.getById('r1');
      expect(result, isNull);
    });
  });

  group('watchActive', () {
    test('only returns active reminders', () async {
      await repo.create(makeReminder(id: 'r1', isActive: true));
      await repo.create(makeReminder(id: 'r2', isActive: false));
      await repo.create(makeReminder(id: 'r3', isActive: true));

      final active = await repo.watchActive().first;
      expect(active, hasLength(2));
      final ids = active.map((r) => r.id).toSet();
      expect(ids, containsAll(['r1', 'r3']));
    });

    test('soft-deleted active reminder excluded from watchActive', () async {
      await repo.create(makeReminder(id: 'r1', isActive: true));
      await repo.delete('r1');

      final active = await repo.watchActive().first;
      expect(active, isEmpty);
    });
  });

  group('getById', () {
    test('returns reminder when it exists', () async {
      await repo.create(makeReminder(
        id: 'r1',
        name: 'Find Me',
        trigger: ReminderTrigger.onFrontChange,
        delayHours: 3,
      ));

      final found = await repo.getById('r1');
      expect(found, isNotNull);
      expect(found!.name, 'Find Me');
      expect(found.trigger, ReminderTrigger.onFrontChange);
      expect(found.delayHours, 3);
    });

    test('returns null for non-existent id', () async {
      final found = await repo.getById('nonexistent');
      expect(found, isNull);
    });
  });

  // Sync field-map contract (Fix X). Pins both (a) `target_member_id` is
  // present in the emitted field map (was silently dropped before — the
  // sync_schema_parity_test surfaced it), and (b) every DateTime is
  // Z-suffixed UTC even when the input is a local DateTime.
  group('debugReminderFields sync contract', () {
    test('target_member_id is emitted in the field map', () {
      final reminder = makeReminder(id: 'r1').copyWith(
        targetMemberId: 'member-42',
      );
      final fields = repo.debugReminderFields(reminder);
      expect(fields.containsKey('target_member_id'), isTrue);
      expect(fields['target_member_id'], 'member-42');
    });

    test('null target_member_id is emitted as null (not omitted)', () {
      final reminder = makeReminder(id: 'r1');
      final fields = repo.debugReminderFields(reminder);
      expect(fields.containsKey('target_member_id'), isTrue);
      expect(fields['target_member_id'], isNull);
    });

    test(
      'created_at and modified_at emit Z-suffixed UTC even when input is '
      'a local DateTime',
      () {
        final localCreated = DateTime(2026, 4, 27, 10, 0);
        final localModified = DateTime(2026, 4, 27, 11, 30);
        final reminder = makeReminder(id: 'r1').copyWith(
          createdAt: localCreated,
          modifiedAt: localModified,
        );

        final fields = repo.debugReminderFields(reminder);
        final createdStr = fields['created_at'] as String;
        final modifiedStr = fields['modified_at'] as String;

        expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
        expect(modifiedStr.endsWith('Z'), isTrue, reason: modifiedStr);
        expect(
          DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
          isTrue,
        );
        expect(
          DateTime.parse(modifiedStr).isAtSameMomentAs(localModified.toUtc()),
          isTrue,
        );
      },
    );
  });

  group('update (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    Reminder makeBase({
      String id = 'r1',
      String name = 'Original name',
      String message = 'Original message',
      ReminderTrigger trigger = ReminderTrigger.scheduled,
      ReminderFrequency frequency = ReminderFrequency.daily,
      List<int>? weeklyDays,
      int? intervalDays,
      String? timeOfDay = '09:00',
      int? delayHours,
      String? targetMemberId,
      bool isActive = true,
      DateTime? createdAt,
      DateTime? modifiedAt,
    }) {
      return Reminder(
        id: id,
        name: name,
        message: message,
        trigger: trigger,
        frequency: frequency,
        weeklyDays: weeklyDays,
        intervalDays: intervalDays,
        timeOfDay: timeOfDay,
        delayHours: delayHours,
        targetMemberId: targetMemberId,
        isActive: isActive,
        createdAt: createdAt ?? baseTime,
        modifiedAt: modifiedAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.create(makeBase());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final later = baseTime.add(const Duration(hours: 1));
      await repo.update(
        makeBase(name: 'New name', modifiedAt: later),
      );

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'reminders');
      expect(captured.single.entityId, 'r1');
      expect(captured.single.fields.keys.toSet(), {'name', 'modified_at'});
      expect(captured.single.fields['name'], 'New name');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.create(makeBase());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeBase());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.create(
        makeBase(
          targetMemberId: 'm1',
          timeOfDay: '08:30',
          weeklyDays: [1, 3, 5],
          frequency: ReminderFrequency.weekly,
        ),
      );

      await repo.update(
        makeBase(
          name: 'Renamed',
          targetMemberId: 'm1',
          timeOfDay: '08:30',
          weeklyDays: [1, 3, 5],
          frequency: ReminderFrequency.weekly,
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      final row = await dao.getById('r1');
      expect(row, isNotNull);
      expect(row!.name, 'Renamed');
      expect(row.message, 'Original message');
      expect(row.targetMemberId, 'm1');
      expect(row.timeOfDay, '08:30');
      expect(row.frequency, 'weekly');
      expect(row.weeklyDays, isNotNull);
      expect(jsonDecode(row.weeklyDays!), [1, 3, 5]);
      expect(row.isActive, isTrue);
    });

    test('null-clearing weekly_days emits the null and writes it to the database',
        () async {
      await repo.create(
        makeBase(
          frequency: ReminderFrequency.weekly,
          weeklyDays: [1, 3, 5],
        ),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(
        makeBase(
          frequency: ReminderFrequency.weekly,
          weeklyDays: null,
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('weekly_days'), isTrue);
      expect(patch['weekly_days'], isNull);

      final row = await dao.getById('r1');
      expect(row!.weeklyDays, isNull);
    });

    test('silently no-ops on a tombstoned row (does not emit, '
        'does not resurrect)', () async {
      await repo.create(makeBase());
      await repo.delete('r1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeBase(name: 'Attempted edit'));

      expect(captured, isEmpty);
      // soft-deleted rows are filtered by RemindersDao.getById, so we read
      // back via watchAll() with `isDeleted` excluded.
      final all = await repo.watchAll().first;
      expect(all, isEmpty);
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(makeBase(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getById('missing');
      expect(row, isNull);
    });

    test('reordering weekly_days produces no diff', () async {
      await repo.create(
        makeBase(
          frequency: ReminderFrequency.weekly,
          weeklyDays: [1, 3, 5],
        ),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(
        makeBase(
          frequency: ReminderFrequency.weekly,
          weeklyDays: [5, 1, 3],
        ),
      );

      expect(captured, isEmpty);
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.create(makeBase());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.update(
        makeBase(
          name: 'Touched',
          modifiedAt: baseTime.add(const Duration(hours: 1)),
        ),
      );

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });
}
