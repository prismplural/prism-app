import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
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

  Reminder _makeReminder({
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
      final reminder = _makeReminder(id: 'r1', name: 'Daily Check');

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
      await repo.create(_makeReminder(id: 'r1', name: 'First'));
      await repo.create(_makeReminder(id: 'r2', name: 'Second'));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });
  });

  group('update', () {
    test('update changes fields', () async {
      final original = _makeReminder(
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
      final original = _makeReminder(
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
      await repo.create(_makeReminder(id: 'r1'));
      await repo.create(_makeReminder(id: 'r2'));

      await repo.delete('r1');

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.first.id, 'r2');
    });

    test('soft-deleted reminder not returned by getById', () async {
      await repo.create(_makeReminder(id: 'r1'));
      await repo.delete('r1');

      final result = await repo.getById('r1');
      expect(result, isNull);
    });
  });

  group('watchActive', () {
    test('only returns active reminders', () async {
      await repo.create(_makeReminder(id: 'r1', isActive: true));
      await repo.create(_makeReminder(id: 'r2', isActive: false));
      await repo.create(_makeReminder(id: 'r3', isActive: true));

      final active = await repo.watchActive().first;
      expect(active, hasLength(2));
      final ids = active.map((r) => r.id).toSet();
      expect(ids, containsAll(['r1', 'r3']));
    });

    test('soft-deleted active reminder excluded from watchActive', () async {
      await repo.create(_makeReminder(id: 'r1', isActive: true));
      await repo.delete('r1');

      final active = await repo.watchActive().first;
      expect(active, isEmpty);
    });
  });

  group('getById', () {
    test('returns reminder when it exists', () async {
      await repo.create(_makeReminder(
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
}
