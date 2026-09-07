import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/pk_front_orphan_projection_repair.dart';

Future<void> _insertMember(
  AppDatabase db, {
  required String id,
  required String uuid,
  String? shortId,
  bool deleted = false,
}) {
  return db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(uuid),
          pluralkitId: Value(shortId),
          isDeleted: Value(deleted),
        ),
      );
}

Future<void> _insertFront(
  AppDatabase db, {
  required String id,
  required String memberId,
}) {
  return db
      .into(db.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: id,
          startTime: DateTime.utc(2026, 2, 1),
          memberId: Value(memberId),
        ),
      );
}

Map<String, dynamic> _frontFields(String memberId) => {
  'start_time': DateTime.utc(2026, 3, 1).toIso8601String(),
  'end_time': null,
  'member_id': memberId,
  'notes': null,
  'confidence': null,
  'session_type': 0,
  'quality': null,
  'is_health_kit_import': false,
  'pluralkit_uuid': null,
  'pk_import_source': null,
  'pk_file_switch_id': null,
  'pk_member_ids_json': null,
  'delete_push_started_at': null,
  'is_deleted': false,
};

void main() {
  test(
    'v39 orphan survives a v40 open when no fresh op records an alias',
    () async {
      final dir = await Directory.systemTemp.createTemp('prism-pk-orphan-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/prism.sqlite');

      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await _insertMember(db, id: 'local-winner', uuid: 'stable-uuid');
      await _insertFront(db, id: 'historical-front', memberId: 'remote-loser');
      await db.customStatement('PRAGMA user_version = 39');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final front = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals('historical-front'))).getSingle();
      final aliases = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'members',
        'remote-loser',
      );
      expect(front.memberId, 'remote-loser');
      expect(aliases, null);
    },
  );

  test(
    'v39 alias-backed orphan repairs after v40 open without a remote op',
    () async {
      final dir = await Directory.systemTemp.createTemp('prism-pk-repair-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/prism.sqlite');

      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
      await db.pkIdentitySyncAliasesDao.upsertAlias(
        entityTable: 'members',
        legacyEntityId: 'remote-loser',
        pkUuid: 'stable-uuid',
        targetRowId: 'winner',
      );
      await _insertFront(db, id: 'historical-front', memberId: 'remote-loser');
      await db.customStatement('PRAGMA user_version = 39');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final first = await repairPkFrontOrphansAfterUpgrade(
        db: db,
        versionBefore: 39,
        versionAfter: 40,
      );
      final repeat = await repairPkFrontOrphansAfterUpgrade(
        db: db,
        versionBefore: 40,
        versionAfter: 40,
      );

      expect(first?.repaired, 1);
      expect(repeat, null);
      expect(
        (await db.select(db.frontingSessions).get()).single.memberId,
        'winner',
      );
    },
  );

  test(
    'stale UUID alias does not remap a front onto a later re-import',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      await _insertMember(db, id: 'old-holder', uuid: 'stable-uuid');
      await db.pkIdentitySyncAliasesDao.upsertAlias(
        entityTable: 'members',
        legacyEntityId: 'remote-loser',
        pkUuid: 'stable-uuid',
        pkId: 'abcde',
        targetRowId: 'old-holder',
      );
      await (db.update(
        db.members,
      )..where((t) => t.id.equals('old-holder'))).write(
        const MembersCompanion(
          pluralkitUuid: Value(null),
          pluralkitId: Value(null),
          isDeleted: Value(true),
        ),
      );
      await _insertMember(
        db,
        id: 'later-reimport',
        uuid: 'stable-uuid',
        shortId: 'abcde',
      );

      final fronting = buildSyncAdapterWithCompletion(db).adapter.entities
          .singleWhere((entity) => entity.tableName == 'fronting_sessions');
      await fronting.applyFields('late-front', _frontFields('remote-loser'));

      final front = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals('late-front'))).getSingle();
      expect(front.memberId, 'remote-loser');
    },
  );

  test(
    'short-id-only stale alias does not remap onto a recycled short id',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      await _insertMember(
        db,
        id: 'recycled-holder',
        uuid: 'different-stable-uuid',
        shortId: 'abcde',
      );
      await db.pkIdentitySyncAliasesDao.upsertAlias(
        entityTable: 'members',
        legacyEntityId: 'remote-loser',
        pkUuid: null,
        pkId: 'abcde',
        targetRowId: 'gone-original-holder',
      );

      final fronting = buildSyncAdapterWithCompletion(db).adapter.entities
          .singleWhere((entity) => entity.tableName == 'fronting_sessions');
      await fronting.applyFields('late-front', _frontFields('remote-loser'));

      final front = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals('late-front'))).getSingle();
      expect(front.memberId, 'remote-loser');
    },
  );

  test('valid stable-UUID alias still converges a later front apply', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'remote-loser',
      pkUuid: 'stable-uuid',
      pkId: 'abcde',
      targetRowId: 'winner',
    );

    final fronting = buildSyncAdapterWithCompletion(db).adapter.entities
        .singleWhere((entity) => entity.tableName == 'fronting_sessions');
    await fronting.applyFields('late-front', _frontFields('remote-loser'));

    final front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'winner');
  });

  test('alias-backed projection repair handles multiple fronts once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'remote-loser',
      pkUuid: 'stable-uuid',
      pkId: 'abcde',
      targetRowId: 'winner',
    );
    await _insertFront(db, id: 'front-1', memberId: 'remote-loser');
    await _insertFront(db, id: 'front-2', memberId: 'remote-loser');

    final repair = PkFrontOrphanProjectionRepair(db);
    final first = await repair.run();
    final second = await repair.run();

    expect(first.scanned, 2);
    expect(first.repaired, 2);
    expect(first.unresolved, 0);
    expect(second.scanned, 0);
    expect(second.repaired, 0);
    expect(
      (await db.select(db.frontingSessions).get()).map((row) => row.memberId),
      everyElement('winner'),
    );
  });

  test('projection repair preserves deleted legacy, stale target, short id, '
      'and alias chain cases', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
    await _insertMember(
      db,
      id: 'deleted-legacy',
      uuid: 'deleted-uuid',
      deleted: true,
    );
    await _insertFront(db, id: 'f-deleted', memberId: 'deleted-legacy');
    await _insertFront(db, id: 'f-stale', memberId: 'stale-legacy');
    await _insertFront(db, id: 'f-short', memberId: 'short-legacy');
    await _insertFront(db, id: 'f-chain', memberId: 'chain-legacy');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'stale-legacy',
      pkUuid: 'stable-uuid',
      targetRowId: 'gone-target',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'short-legacy',
      pkUuid: null,
      pkId: 'abcde',
      targetRowId: 'winner',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'chain-legacy',
      pkUuid: 'stable-uuid',
      targetRowId: 'middle-legacy',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'middle-legacy',
      pkUuid: 'stable-uuid',
      targetRowId: 'winner',
    );

    final result = await PkFrontOrphanProjectionRepair(db).run();

    expect(result.scanned, 4);
    expect(result.repaired, 0);
    expect(result.legacyRowExists, 1);
    expect(result.staleTarget, 1);
    expect(result.shortIdOnly, 1);
    expect(result.aliasChain, 1);
    expect(
      (await db.select(db.frontingSessions).get()).map((row) => row.memberId),
      containsAll(<String>{
        'deleted-legacy',
        'stale-legacy',
        'short-legacy',
        'chain-legacy',
      }),
    );
  });

  test('projection repair refuses duplicate live UUID holders', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP INDEX idx_members_pluralkit_uuid');
    await _insertMember(db, id: 'winner-a', uuid: 'stable-uuid');
    await _insertMember(db, id: 'winner-b', uuid: 'stable-uuid');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'remote-loser',
      pkUuid: 'stable-uuid',
      targetRowId: 'winner-a',
    );
    await _insertFront(db, id: 'front', memberId: 'remote-loser');

    final result = await PkFrontOrphanProjectionRepair(db).run();

    expect(result.ambiguousIdentity, 1);
    expect(result.repaired, 0);
    expect(
      (await db.select(db.frontingSessions).get()).single.memberId,
      'remote-loser',
    );
  });

  test(
    'retained stable UUID and live tombstone winner recover no-alias orphan',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
      await _insertFront(db, id: 'front', memberId: 'remote-loser');
      final reads = <String>[];

      final result = await PkFrontOrphanProjectionRepair(db).run(
        readWinningField:
            ({required table, required entityId, required field}) async {
              reads.add('$table.$entityId.$field');
              return switch (field) {
                'is_deleted' => 'false',
                'pluralkit_uuid' => '"stable-uuid"',
                _ => null,
              };
            },
      );

      expect(reads, <String>[
        'members.remote-loser.is_deleted',
        'members.remote-loser.pluralkit_uuid',
      ]);
      expect(result.repaired, 1);
      expect(
        (await db.select(db.frontingSessions).get()).single.memberId,
        'winner',
      );
    },
  );

  test(
    'tombstoned or missing engine evidence preserves original member id',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
      await _insertFront(db, id: 'tombstoned', memberId: 'gone');
      await _insertFront(db, id: 'no-evidence', memberId: 'unknown');

      final result = await PkFrontOrphanProjectionRepair(db).run(
        readWinningField:
            ({required table, required entityId, required field}) async {
              if (entityId == 'gone' && field == 'is_deleted') return 'true';
              return null;
            },
      );

      expect(result.engineTombstoned, 1);
      expect(result.noEvidence, 1);
      expect(result.repaired, 0);
      expect(
        (await db.select(db.frontingSessions).get()).map((row) => row.memberId),
        containsAll(<String>{'gone', 'unknown'}),
      );
    },
  );

  test('healthy-engine recovery gate runs one completed local pass', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertMember(db, id: 'winner', uuid: 'stable-uuid');
    await _insertFront(db, id: 'front', memberId: 'remote-loser');
    var checked = false;
    var readCount = 0;
    Future<String?> reader({
      required String table,
      required String entityId,
      required String field,
    }) async {
      readCount++;
      return field == 'is_deleted' ? 'false' : '"stable-uuid"';
    }

    final first = await runPkFrontOrphanEngineRecoveryOnce(
      db: db,
      getChecked: () async => checked,
      setChecked: () async => checked = true,
      readWinningField: reader,
    );
    final second = await runPkFrontOrphanEngineRecoveryOnce(
      db: db,
      getChecked: () async => checked,
      setChecked: () async => checked = true,
      readWinningField: reader,
    );

    expect(first.repaired, 1);
    expect(second.scanned, 0);
    expect(readCount, 2);
    expect(checked, isTrue);
  });
}
