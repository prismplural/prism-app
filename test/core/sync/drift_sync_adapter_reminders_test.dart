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
  });
}
