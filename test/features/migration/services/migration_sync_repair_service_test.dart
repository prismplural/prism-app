import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/migration/services/migration_sync_repair_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _enqueue(
  AppDatabase db,
  String table,
  String entityId,
  List<String> fields,
  String reason,
) {
  return db.customStatement(
    'INSERT OR REPLACE INTO sync_migration_repairs '
    '(table_name, entity_id, field_names_json, reason, enqueued_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [table, entityId, jsonEncode(fields), reason, 0],
  );
}

Future<int> _queueCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM sync_migration_repairs')
      .getSingle();
  return row.read<int>('c');
}

Future<void> _insertMember(
  AppDatabase db,
  String id, {
  required bool markdownEnabled,
  bool isDeleted = false,
}) async {
  await db.customStatement(
    'INSERT INTO members '
    '(id, name, created_at, is_admin, display_order, is_active, is_deleted, '
    ' markdown_enabled) VALUES (?, ?, 0, 0, 0, 1, ?, ?)',
    [id, 'Member $id', isDeleted ? 1 : 0, markdownEnabled ? 1 : 0],
  );
}

Future<void> _insertGroup(
  AppDatabase db,
  String id, {
  String sortState = '{"mode":0,"order":["e1","e2"]}',
  bool isDeleted = false,
  bool syncSuppressed = false,
  String? pluralkitUuid,
}) async {
  await db.customStatement(
    'INSERT INTO member_groups '
    '(id, name, display_order, group_type, created_at, is_deleted, '
    ' sync_suppressed, sort_state, pluralkit_uuid) '
    'VALUES (?, ?, 0, 0, 0, ?, ?, ?, ?)',
    [
      id,
      'group $id',
      isDeleted ? 1 : 0,
      syncSuppressed ? 1 : 0,
      sortState,
      pluralkitUuid,
    ],
  );
}

Future<void> _insertConversation(
  AppDatabase db,
  String id, {
  required bool includesAllMembers,
  String participantIds = '["a","b"]',
  String? creatorId,
  bool isDeleted = false,
}) async {
  await db.customStatement(
    'INSERT INTO conversations '
    '(id, created_at, last_activity_at, creator_id, participant_ids, '
    ' is_direct_message, is_deleted, includes_all_members) '
    'VALUES (?, 0, 0, ?, ?, 0, ?, ?)',
    [
      id,
      creatorId,
      participantIds,
      isDeleted ? 1 : 0,
      includesAllMembers ? 1 : 0,
    ],
  );
}

void main() {
  late AppDatabase db;
  late List<_Emit> emits;

  setUp(() {
    db = _makeDb();
    emits = [];
  });

  tearDown(() async {
    await db.close();
  });

  MigrationSyncRepairService serviceWith(
    Future<void> Function({
      required String table,
      required String entityId,
      required Map<String, dynamic> fields,
    })
    recordReconcile,
  ) {
    return MigrationSyncRepairService(db: db, recordReconcile: recordReconcile);
  }

  MigrationSyncRepairService service() {
    return serviceWith(({
      required table,
      required entityId,
      required fields,
    }) async {
      emits.add(_Emit(table, entityId, fields));
    });
  }

  test('re-reads CURRENT values with correct encodings and deletes on success',
      () async {
    // Migration enqueued at flip time; the row's CURRENT markdown_enabled is 1,
    // which the drain must read (not a captured value) and emit as a bool.
    await _insertMember(db, 'm1', markdownEnabled: true);
    await _enqueue(db, 'members', 'm1', const ['markdown_enabled'], 'r1');

    await _insertGroup(db, 'g1', sortState: '{"mode":0,"order":["e1","e2"]}');
    await _enqueue(db, 'member_groups', 'g1', const ['sort_state'], 'r2');

    await _insertConversation(
      db,
      'c1',
      includesAllMembers: true,
      participantIds: '["owner"]',
      creatorId: 'owner',
    );
    await _enqueue(
      db,
      'conversations',
      'c1',
      const ['includes_all_members', 'participant_ids', 'creator_id'],
      'r3',
    );

    final result = await service().drain();

    expect(result.error, isNull);
    expect(result.repaired, 3);
    expect(emits, unorderedEquals([
      const _Emit('members', 'm1', {'markdown_enabled': true}),
      const _Emit('member_groups', 'g1', {
        'sort_state': '{"mode":0,"order":["e1","e2"]}',
      }),
      const _Emit('conversations', 'c1', {
        'includes_all_members': true,
        'participant_ids': '["owner"]',
        'creator_id': 'owner',
      }),
    ]));
    // All rows deleted on success.
    expect(await _queueCount(db), 0);
  });

  test(
    'drains the POST-mutation value, not a migration-time capture',
    () async {
      // Enqueue at "migration time" against markdown_enabled = 1 / a given
      // sort_state, then mutate both rows to a DIFFERENT value before draining.
      // The queue stores only field NAMES, so a drain that re-reads current
      // state must carry the post-mutation values; a drain that replayed a
      // captured value would carry the stale migration-time ones.
      await _insertMember(db, 'm1', markdownEnabled: true);
      await _enqueue(db, 'members', 'm1', const ['markdown_enabled'], 'r1');
      await _insertGroup(db, 'g1', sortState: '{"mode":0,"order":["e1","e2"]}');
      await _enqueue(db, 'member_groups', 'g1', const ['sort_state'], 'r2');

      // A later user edit between enqueue and drain.
      await db.customStatement(
        'UPDATE members SET markdown_enabled = 0 WHERE id = ?',
        ['m1'],
      );
      await db.customStatement(
        'UPDATE member_groups SET sort_state = ? WHERE id = ?',
        ['{"mode":1,"order":["e2","e1"]}', 'g1'],
      );

      final result = await service().drain();

      expect(result.error, isNull);
      expect(result.repaired, 2);
      expect(emits, unorderedEquals([
        const _Emit('members', 'm1', {'markdown_enabled': false}),
        const _Emit('member_groups', 'g1', {
          'sort_state': '{"mode":1,"order":["e2","e1"]}',
        }),
      ]));
    },
  );

  test('retries on injected FFI failure (row not deleted)', () async {
    await _insertMember(db, 'm1', markdownEnabled: true);
    await _enqueue(db, 'members', 'm1', const ['markdown_enabled'], 'r1');

    final failing = serviceWith(({
      required table,
      required entityId,
      required fields,
    }) async {
      throw StateError('engine unavailable');
    });

    final result = await failing.drain();

    expect(result.hasError, isTrue);
    // Row survives for the next healthy catch-up.
    expect(await _queueCount(db), 1);

    // A subsequent healthy drain succeeds and clears it.
    final result2 = await service().drain();
    expect(result2.error, isNull);
    expect(result2.repaired, 1);
    expect(await _queueCount(db), 0);
  });

  test('drops repairs for deleted or missing entities without emitting',
      () async {
    await _insertMember(db, 'gone', markdownEnabled: true, isDeleted: true);
    await _enqueue(db, 'members', 'gone', const ['markdown_enabled'], 'r1');
    // Never-existed entity.
    await _enqueue(db, 'members', 'never', const ['markdown_enabled'], 'r2');

    final result = await service().drain();

    expect(result.error, isNull);
    expect(result.repaired, 0);
    expect(result.dropped, 2);
    expect(emits, isEmpty);
    expect(await _queueCount(db), 0);
  });

  test('skips and deletes suppressed groups', () async {
    await _insertGroup(db, 'gsup', syncSuppressed: true);
    await _enqueue(db, 'member_groups', 'gsup', const ['sort_state'], 'r1');

    final result = await service().drain();

    expect(result.skipped, 1);
    expect(result.repaired, 0);
    expect(emits, isEmpty);
    expect(await _queueCount(db), 0);
  });

  test('skips and deletes PK-backed groups when pk group-sync v2 is off',
      () async {
    await _insertGroup(db, 'gpk', pluralkitUuid: 'uuid-1');
    await _enqueue(db, 'member_groups', 'gpk', const ['sort_state'], 'r1');

    // pkGroupSyncV2Enabled defaults to false.
    final result = await service().drain();

    expect(result.skipped, 1);
    expect(emits, isEmpty);
    expect(await _queueCount(db), 0);
  });

  test('emits PK-backed groups when pk group-sync v2 is enabled', () async {
    await _insertGroup(db, 'gpk', pluralkitUuid: 'uuid-1');
    await _enqueue(db, 'member_groups', 'gpk', const ['sort_state'], 'r1');
    await db.systemSettingsDao.applyPartialSettings(
      const SystemSettingsTableCompanion(pkGroupSyncV2Enabled: Value(true)),
    );

    final result = await service().drain();

    expect(result.repaired, 1);
    expect(result.skipped, 0);
    expect(emits, hasLength(1));
    expect(emits.single.table, 'member_groups');
    expect(emits.single.entityId, 'gpk');
    expect(await _queueCount(db), 0);
  });

  group('one-time blanket backfill', () {
    test('enqueues expected rows once, then no-ops', () async {
      await _insertGroup(db, 'g1');
      await _insertGroup(db, 'g_deleted', isDeleted: true);
      await _insertMember(db, 'm_on', markdownEnabled: true);
      await _insertMember(db, 'm_off', markdownEnabled: false);

      var flag = false;
      Future<bool> getFlag() async => flag;
      Future<void> setFlag() async {
        flag = true;
      }

      final enqueued = await service().enqueueBlanketBackfillOnce(
        getFlag: getFlag,
        setFlag: setFlag,
      );
      // g1 (sort_state) + m_on (markdown_enabled); deleted group and
      // markdown-off member are excluded.
      expect(enqueued, 2);
      expect(await _queueCount(db), 2);
      expect(flag, isTrue);

      final second = await service().enqueueBlanketBackfillOnce(
        getFlag: getFlag,
        setFlag: setFlag,
      );
      expect(second, 0);
      expect(await _queueCount(db), 2);
    });
  });
}

class _Emit {
  const _Emit(this.table, this.entityId, this.fields);

  final String table;
  final String entityId;
  final Map<String, dynamic> fields;

  @override
  bool operator ==(Object other) =>
      other is _Emit &&
      other.table == table &&
      other.entityId == entityId &&
      const DeepCollectionEquality().equals(other.fields, fields);

  @override
  int get hashCode =>
      Object.hash(table, entityId, const DeepCollectionEquality().hash(fields));

  @override
  String toString() => '_Emit($table, $entityId, $fields)';
}
