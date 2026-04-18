import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  group('reminders sync entity — frequency + weekly_days', () {
    late database.AppDatabase db;

    setUp(() {
      db = database.AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'applyFields writes frequency and weekly_days columns to the row',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final reminders = syncAdapter.adapter.entities.singleWhere(
          (entity) => entity.tableName == 'reminders',
        );

        final createdAt = DateTime.utc(2026, 4, 1).toIso8601String();
        final modifiedAt = DateTime.utc(2026, 4, 2).toIso8601String();

        await reminders.applyFields('reminder-1', {
          'name': 'Wind-down',
          'message': 'Time to wind down',
          'trigger': 0,
          'frequency': 'weekly',
          'weekly_days': '[1,3]',
          'interval_days': null,
          'time_of_day': '21:00',
          'delay_hours': null,
          'is_active': true,
          'created_at': createdAt,
          'modified_at': modifiedAt,
          'is_deleted': false,
        });

        final row = await (db.select(
          db.reminders,
        )..where((t) => t.id.equals('reminder-1'))).getSingleOrNull();

        expect(row, isNotNull);
        expect(row!.frequency, 'weekly');
        expect(row.weeklyDays, '[1,3]');
      },
    );

    test(
      'toSyncFields emits frequency and weekly_days keys with exact values',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final reminders = syncAdapter.adapter.entities.singleWhere(
          (entity) => entity.tableName == 'reminders',
        );

        final row = database.ReminderRow(
          id: 'reminder-2',
          name: 'Weekly check-in',
          message: 'Reflect on the week',
          trigger: 0,
          frequency: 'weekly',
          intervalDays: null,
          weeklyDays: '[1,3]',
          timeOfDay: '09:00',
          delayHours: null,
          isActive: true,
          createdAt: DateTime.utc(2026, 4, 1),
          modifiedAt: DateTime.utc(2026, 4, 2),
          isDeleted: false,
        );

        final fields = reminders.toSyncFields(row);

        expect(fields, contains('frequency'));
        expect(fields, contains('weekly_days'));
        expect(fields['frequency'], 'weekly');
        expect(fields['weekly_days'], '[1,3]');
      },
    );

    test(
      'applyFields writes an unknown frequency string as-is; mapper handles fallback on read',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final reminders = syncAdapter.adapter.entities.singleWhere(
          (entity) => entity.tableName == 'reminders',
        );

        final createdAt = DateTime.utc(2026, 4, 1).toIso8601String();
        final modifiedAt = DateTime.utc(2026, 4, 2).toIso8601String();

        await reminders.applyFields('reminder-garbage', {
          'name': 'Unknown frequency peer',
          'message': 'From a future client',
          'trigger': 0,
          'frequency': 'garbage',
          'weekly_days': null,
          'interval_days': null,
          'time_of_day': '08:00',
          'delay_hours': null,
          'is_active': true,
          'created_at': createdAt,
          'modified_at': modifiedAt,
          'is_deleted': false,
        });

        final row = await (db.select(
          db.reminders,
        )..where((t) => t.id.equals('reminder-garbage'))).getSingleOrNull();

        expect(row, isNotNull);
        expect(row!.frequency, 'garbage');
        expect(row.weeklyDays, isNull);
      },
    );

    test('toSyncFields emits daily frequency row fields', () async {
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final reminders = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'reminders',
      );

      final row = database.ReminderRow(
        id: 'reminder-daily',
        name: 'Daily ping',
        message: 'Every day',
        trigger: 0,
        frequency: 'daily',
        intervalDays: null,
        weeklyDays: null,
        timeOfDay: '07:30',
        delayHours: null,
        isActive: true,
        createdAt: DateTime.utc(2026, 4, 1),
        modifiedAt: DateTime.utc(2026, 4, 2),
        isDeleted: false,
      );

      final fields = reminders.toSyncFields(row);

      expect(fields['frequency'], 'daily');
      expect(fields['weekly_days'], isNull);
      expect(fields['interval_days'], isNull);
    });

    test(
      'applyFields writes target_member_id column (plan 06 per-member target)',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final reminders = syncAdapter.adapter.entities.singleWhere(
          (entity) => entity.tableName == 'reminders',
        );

        final createdAt = DateTime.utc(2026, 4, 1).toIso8601String();
        final modifiedAt = DateTime.utc(2026, 4, 2).toIso8601String();

        await reminders.applyFields('reminder-targeted', {
          'name': 'When Alex fronts',
          'message': 'Alex is out',
          'trigger': 1,
          'frequency': null,
          'weekly_days': null,
          'interval_days': null,
          'time_of_day': null,
          'delay_hours': 0,
          'target_member_id': 'alex-uuid',
          'is_active': true,
          'created_at': createdAt,
          'modified_at': modifiedAt,
          'is_deleted': false,
        });

        final row = await (db.select(
          db.reminders,
        )..where((t) => t.id.equals('reminder-targeted'))).getSingleOrNull();

        expect(row, isNotNull);
        expect(row!.targetMemberId, 'alex-uuid');
      },
    );

    test(
      'toSyncFields emits target_member_id (null + non-null round-trip)',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final reminders = syncAdapter.adapter.entities.singleWhere(
          (entity) => entity.tableName == 'reminders',
        );

        final anyRow = database.ReminderRow(
          id: 'r-any',
          name: 'Any',
          message: 'm',
          trigger: 1,
          frequency: null,
          intervalDays: null,
          weeklyDays: null,
          timeOfDay: null,
          delayHours: 0,
          targetMemberId: null,
          isActive: true,
          createdAt: DateTime.utc(2026, 4, 1),
          modifiedAt: DateTime.utc(2026, 4, 2),
          isDeleted: false,
        );
        final anyFields = reminders.toSyncFields(anyRow);
        expect(anyFields, contains('target_member_id'));
        expect(anyFields['target_member_id'], isNull);

        final targetedRow = database.ReminderRow(
          id: 'r-tgt',
          name: 'Target',
          message: 'm',
          trigger: 1,
          frequency: null,
          intervalDays: null,
          weeklyDays: null,
          timeOfDay: null,
          delayHours: 0,
          targetMemberId: 'member-x',
          isActive: true,
          createdAt: DateTime.utc(2026, 4, 1),
          modifiedAt: DateTime.utc(2026, 4, 2),
          isDeleted: false,
        );
        final targetedFields = reminders.toSyncFields(targetedRow);
        expect(targetedFields['target_member_id'], 'member-x');
      },
    );

    test('toSyncFields emits interval frequency row fields', () async {
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final reminders = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'reminders',
      );

      final row = database.ReminderRow(
        id: 'reminder-interval',
        name: 'Every 3 days',
        message: 'Recurring check-in',
        trigger: 0,
        frequency: 'interval',
        intervalDays: 3,
        weeklyDays: null,
        timeOfDay: '12:00',
        delayHours: null,
        isActive: true,
        createdAt: DateTime.utc(2026, 4, 1),
        modifiedAt: DateTime.utc(2026, 4, 2),
        isDeleted: false,
      );

      final fields = reminders.toSyncFields(row);

      expect(fields['frequency'], 'interval');
      expect(fields['weekly_days'], isNull);
      expect(fields['interval_days'], 3);
    });
  });
}
