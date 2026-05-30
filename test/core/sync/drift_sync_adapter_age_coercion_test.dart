// Tests that the sync adapter correctly handles old-client wire values for the
// `age` field, which was previously an Int and is now a String.
//
// Scenarios:
//   1. New client (String "ageless") → written as-is.
//   2. Old client (bare integer 42) → coerced to "42" via _asString numeric
//      coercion, so old→new cross-version sync preserves numeric ages.
//   3. Null wire value → absent (no write).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  group('members applyFields: age wire coercion (int→String back-compat)', () {
    Future<database.AppDatabase> _makeDb() async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Seed the member row that applyFields will upsert into.
      await db.into(db.members).insert(
        database.MembersCompanion.insert(
          id: 'member-coerce',
          name: 'CoerceTest',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      return db;
    }

    Map<String, dynamic> _baseFields() => {
      'name': 'CoerceTest',
      'emoji': '❔',
      'is_active': true,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'display_order': 0,
      'is_admin': false,
      'custom_color_enabled': false,
      'is_deleted': false,
    };

    test('string age wire value is written unchanged', () async {
      final db = await _makeDb();
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final members = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'members',
      );

      syncAdapter.beginSyncBatch();
      await members.applyFields('member-coerce', {
        ..._baseFields(),
        'age': 'ageless',
      });
      await syncAdapter.completeSyncBatch();

      final row = await db.membersDao.getMemberById('member-coerce');
      expect(row, isNotNull);
      expect(row!.age, 'ageless');
    });

    test('integer wire value is coerced to string (old-client back-compat)',
        () async {
      final db = await _makeDb();
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final members = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'members',
      );

      syncAdapter.beginSyncBatch();
      await members.applyFields('member-coerce', {
        ..._baseFields(),
        'age': 42, // bare integer from old client
      });
      await syncAdapter.completeSyncBatch();

      final row = await db.membersDao.getMemberById('member-coerce');
      expect(row, isNotNull);
      // The numeric wire value must be preserved as its string form.
      expect(row!.age, '42');
    });

    test('null wire age leaves column null', () async {
      final db = await _makeDb();
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final members = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'members',
      );

      syncAdapter.beginSyncBatch();
      await members.applyFields('member-coerce', {
        ..._baseFields(),
        'age': null,
      });
      await syncAdapter.completeSyncBatch();

      final row = await db.membersDao.getMemberById('member-coerce');
      expect(row, isNotNull);
      expect(row!.age, isNull);
    });
  });
}
