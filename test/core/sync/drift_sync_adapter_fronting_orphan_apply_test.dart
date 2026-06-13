// A remote fronting_sessions op with session_type=0 and member_id=NULL
// would trip the v14 CHECK (session_type != 0 OR member_id IS NOT NULL) and the
// non-strict apply would quarantine-and-swallow the row. The apply normalizes
// such a row onto the Unknown sentinel and enqueues a sync-repair so the
// coercion re-emits and wins LWW fleet-wide.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  group('fronting_sessions applyFields: orphan normalization (S2)', () {
    Future<database.AppDatabase> makeDb() async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Force schema migration to run so the v14 CHECK is installed.
      await db.customSelect('SELECT 1').get();
      return db;
    }

    Map<String, dynamic> baseFields() => {
      'start_time': DateTime.utc(2026, 1, 1).toIso8601String(),
      'end_time': null,
      'session_type': 0,
      'is_health_kit_import': false,
      'is_deleted': false,
    };

    Future<List<Map<String, String>>> repairRows(
      database.AppDatabase db,
    ) async {
      final rows = await db
          .customSelect(
            'SELECT table_name, entity_id, field_names_json, reason '
            'FROM sync_migration_repairs ORDER BY table_name, entity_id',
          )
          .get();
      return [
        for (final r in rows)
          {
            'table': r.read<String>('table_name'),
            'entity': r.read<String>('entity_id'),
            'fields': r.read<String>('field_names_json'),
            'reason': r.read<String>('reason'),
          },
      ];
    }

    test('a session_type=0/member_id=NULL apply persists with the sentinel '
        'member_id, no SqliteException, repair enqueued', () async {
      final db = await makeDb();
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'fronting_sessions',
      );

      syncAdapter.beginSyncBatch();
      // No throw — the CHECK is not tripped because member_id is coerced.
      await fronting.applyFields('orphan-remote', {
        ...baseFields(),
        'member_id': null,
      });
      await syncAdapter.completeSyncBatch();

      final row = await db
          .customSelect(
            'SELECT member_id, session_type '
            "FROM fronting_sessions WHERE id = 'orphan-remote'",
          )
          .getSingle();
      expect(row.read<String?>('member_id'), unknownSentinelMemberId);
      expect(row.read<int>('session_type'), 0);

      expect(
        await repairRows(db),
        unorderedEquals([
          {
            'table': 'fronting_sessions',
            'entity': 'orphan-remote',
            'fields': '["member_id","pluralkit_uuid"]',
            'reason': 'fronting_orphan_rescue',
          },
          {
            'table': 'members',
            'entity': unknownSentinelMemberId,
            'fields': '["__create__"]',
            'reason': 'fronting_orphan_rescue',
          },
        ]),
      );
    });

    test('a normal apply with a concrete member_id is untouched and enqueues '
        'no repair', () async {
      final db = await makeDb();
      // Seed the referenced member so the row is a healthy fronting session.
      await db.into(db.members).insert(
        database.MembersCompanion.insert(
          id: 'm1',
          name: 'Alpha',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'fronting_sessions',
      );

      syncAdapter.beginSyncBatch();
      await fronting.applyFields('healthy-remote', {
        ...baseFields(),
        'member_id': 'm1',
      });
      await syncAdapter.completeSyncBatch();

      final row = await db
          .customSelect(
            "SELECT member_id FROM fronting_sessions WHERE id = 'healthy-remote'",
          )
          .getSingle();
      expect(row.read<String?>('member_id'), 'm1');
      expect(await repairRows(db), isEmpty);
    });

    test('a sleep row (session_type=1) with NULL member_id is left as-is', () async {
      final db = await makeDb();
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'fronting_sessions',
      );

      syncAdapter.beginSyncBatch();
      await fronting.applyFields('sleep-remote', {
        ...baseFields(),
        'session_type': 1,
        'member_id': null,
      });
      await syncAdapter.completeSyncBatch();

      final row = await db
          .customSelect(
            "SELECT member_id FROM fronting_sessions WHERE id = 'sleep-remote'",
          )
          .getSingle();
      expect(row.read<String?>('member_id'), isNull);
      expect(await repairRows(db), isEmpty);
    });
  });
}
