import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  for (final unrelated in [100, 1000]) {
    test(
      'parent and alias lookups use indexes with $unrelated unrelated rows',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.batch((batch) {
          batch.insertAll(db.memberGroups, [
            for (var i = 0; i < unrelated; i++)
              MemberGroupsCompanion.insert(
                id: 'unrelated-$i',
                name: 'Unrelated',
                createdAt: DateTime.utc(2026),
                parentGroupId: Value('other-parent-$i'),
                pluralkitUuid: Value('other-uuid-$i'),
              ),
            MemberGroupsCompanion.insert(
              id: 'wanted-parent',
              name: 'Parent',
              createdAt: DateTime.utc(2026),
              pluralkitUuid: const Value('uuid'),
            ),
            MemberGroupsCompanion.insert(
              id: 'child',
              name: 'Child',
              createdAt: DateTime.utc(2026),
              parentGroupId: const Value('pk-group:uuid'),
            ),
          ]);
          batch.insertAll(db.pkGroupSyncAliases, [
            for (var i = 0; i < unrelated; i++)
              PkGroupSyncAliasesCompanion.insert(
                legacyEntityId: 'unrelated-alias-$i',
                pkGroupUuid: 'other-uuid-$i',
                canonicalEntityId: 'pk-group:other-uuid-$i',
                createdAt: DateTime.utc(2026),
              ),
            PkGroupSyncAliasesCompanion.insert(
              legacyEntityId: 'wanted-alias',
              pkGroupUuid: 'uuid',
              canonicalEntityId: 'pk-group:uuid',
              createdAt: DateTime.utc(2026),
            ),
          ]);
        });
        // Mirror the production builder predicates, then explain Drift's actual
        // generated SQL and bindings rather than a handwritten SQL approximation.
        final children = db.select(db.memberGroups)
          ..where(
            (g) =>
                g.isDeleted.equals(false) &
                g.parentGroupId.isNotNull() &
                g.parentGroupId.isIn({
                  'pk-group:uuid',
                  'pk-group-uuid',
                  'pk-group-g2:uuid',
                }),
          );
        final activeParent = db.select(db.memberGroups)
          ..where(
            (g) =>
                g.pluralkitUuid.equals('uuid') &
                g.isDeleted.equalsExp(const Constant(false)),
          );
        final aliases = db.select(db.pkGroupSyncAliases)
          ..where((a) => a.pkGroupUuid.equals('uuid'));
        for (final (query, index) in [
          (children, 'idx_member_groups_parent_id'),
          (activeParent, 'idx_member_groups_pluralkit_uuid'),
          (aliases, 'idx_pk_group_sync_aliases_pk_group_uuid'),
        ]) {
          final sql = query.constructQuery();
          final plan = await db
              .customSelect(
                'EXPLAIN QUERY PLAN ${sql.sql}',
                variables: sql.introducedVariables,
              )
              .get();
          final detail = plan.map((row) => row.data['detail']).join(' ');
          expect(detail, contains('USING INDEX $index'));
          expect(detail, contains('SEARCH'));
          final elapsed = <int>[];
          for (var repetition = 0; repetition < 5; repetition++) {
            final watch = Stopwatch()..start();
            final rows = await query.get();
            watch.stop();
            expect(rows, hasLength(1));
            elapsed.add(watch.elapsedMicroseconds);
          }
          // Observations only: no machine-dependent latency pass threshold.
          debugPrintSynchronously(
            'lookup rows=$unrelated index=$index sql=${sql.sql} '
            'plan=$detail elapsed_us=$elapsed',
          );
        }
      },
    );
  }

  for (final tombstone in [false, true]) {
    for (final canonicalUuid in [null, 'different-uuid']) {
      test(
        'parent canonical fallback tombstone=$tombstone uuid=$canonicalUuid',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          if (tombstone) {
            await db
                .into(db.memberGroups)
                .insert(
                  MemberGroupsCompanion.insert(
                    id: 'deleted-family',
                    name: 'Deleted',
                    createdAt: DateTime.utc(2026),
                    pluralkitUuid: const Value('fallback-uuid'),
                    isDeleted: const Value(true),
                  ),
                );
          }
          await db
              .into(db.memberGroups)
              .insert(
                MemberGroupsCompanion.insert(
                  id: 'pk-group:fallback-uuid',
                  name: 'Canonical',
                  createdAt: DateTime.utc(2026),
                  pluralkitUuid: Value(canonicalUuid),
                ),
              );
          final entity = buildSyncAdapterWithCompletion(
            db,
          ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
          await entity.applyFields('child', {
            'name': 'Child',
            'created_at': DateTime.utc(2026).toIso8601String(),
            'parent_group_id': 'pk-group-fallback-uuid',
          });
          // Preserve the existing resolver's distinction: a deleted UUID match
          // blocks canonical fallback; no UUID row permits the legacy fallback.
          expect(
            (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
            tombstone ? 'pk-group-fallback-uuid' : 'pk-group:fallback-uuid',
          );
        },
      );
    }
  }

  test('indexed parent fast path preserves duplicate-family ranking', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');
    for (final suppressed in [true, false]) {
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: suppressed ? 'suppressed-parent' : 'active-parent',
              name: 'Parent',
              createdAt: DateTime.utc(2026),
              pluralkitUuid: const Value('dupe-uuid'),
              syncSuppressed: Value(suppressed),
            ),
          );
    }
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-dupe-uuid',
    });
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'active-parent',
    );
  });

  test('live UUID parent outranks deleted family rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final deleted in [false, true]) {
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: deleted ? 'deleted-parent' : 'live-parent',
              name: 'Parent',
              createdAt: DateTime.utc(2026),
              pluralkitUuid: const Value('mixed-uuid'),
              isDeleted: Value(deleted),
            ),
          );
    }
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-mixed-uuid',
    });
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'live-parent',
    );
  });

  test(
    'missing PK parent stays unresolved rather than creating a parent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
      await entity.applyFields('child', {
        'name': 'Child',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'parent_group_id': 'pk-group-missing-uuid',
      });
      expect(
        (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
        'pk-group-missing-uuid',
      );
      expect(await db.select(db.memberGroups).get(), hasLength(1));
    },
  );

  test('PK parent reference resolves to receiver legacy local id', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'receiver-parent',
            name: 'Parent',
            createdAt: DateTime.utc(2026),
            pluralkitUuid: const Value('parent-uuid'),
            syncGeneration: const Value(2),
          ),
        );
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-g2:parent-uuid',
    });
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'receiver-parent',
    );
    await entity.applyFields('child', {'name': 'Renamed'});
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'receiver-parent',
    );
    await entity.applyFields('child', {'parent_group_id': null});
    await entity.applyFields('pk-group-g2:parent-uuid', {'name': 'Updated'});
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      isNull,
    );
  });

  test('future parent incarnation waits for sparse parent arrival', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'receiver-parent',
            name: 'Parent',
            createdAt: DateTime.utc(2026),
            pluralkitUuid: const Value('future-uuid'),
          ),
        );
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-g2:future-uuid',
    });
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'pk-group-g2:future-uuid',
    );
    await entity.applyFields('pk-group-g2:future-uuid', {'name': 'Revived'});
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'receiver-parent',
    );
  });

  test(
    'older parent incarnation does not attach to a revived local parent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'receiver-parent',
              name: 'Parent',
              createdAt: DateTime.utc(2026),
              pluralkitUuid: const Value('revived-uuid'),
              syncGeneration: const Value(2),
            ),
          );
      final entity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
      await entity.applyFields('child', {
        'name': 'Child',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'parent_group_id': 'pk-group-g1:revived-uuid',
      });
      await entity.applyFields('pk-group-g2:revived-uuid', {
        'pluralkit_uuid': 'revived-uuid',
      });
      expect(
        (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
        'pk-group-g1:revived-uuid',
      );
    },
  );

  test(
    'known legacy alias repairs child when PK parent arrives later',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'sender-old-parent',
        pkGroupUuid: 'alias-uuid',
        canonicalEntityId: 'pk-group:alias-uuid',
      );
      final entity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
      await entity.applyFields('child', {
        'name': 'Child',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'parent_group_id': 'sender-old-parent',
      });
      await entity.applyFields('pk-group:alias-uuid', {
        'name': 'Parent',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'pluralkit_uuid': 'alias-uuid',
      });
      expect(
        (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
        'pk-group:alias-uuid',
      );
    },
  );

  test('exact ordinary parent id wins over PK-looking reference', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'pk-group-collision',
            name: 'Ordinary',
            createdAt: DateTime.utc(2026),
          ),
        );
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-collision',
    });
    await entity.applyFields('pk-group:collision', {
      'name': 'PK',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'pluralkit_uuid': 'collision',
    });
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'pk-group-collision',
    );
  });

  test(
    'unknown sender-local parent stays unresolved without flattening',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entity = buildSyncAdapterWithCompletion(
        db,
      ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
      await entity.applyFields('child', {
        'name': 'Child',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'parent_group_id': 'unknown-sender-local-id',
      });
      await entity.applyFields('pk-group:unrelated-uuid', {
        'name': 'Unrelated',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'pluralkit_uuid': 'unrelated-uuid',
      });
      expect(
        (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
        'unknown-sender-local-id',
      );
    },
  );

  test('parent resolution never revives a deleted PK parent', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'deleted-parent',
            name: 'Deleted',
            createdAt: DateTime.utc(2026),
            pluralkitUuid: const Value('deleted-uuid'),
            isDeleted: const Value(true),
          ),
        );
    final entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
    await entity.applyFields('child', {
      'name': 'Child',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'parent_group_id': 'pk-group-deleted-uuid',
    });
    final parent = await (db.select(
      db.memberGroups,
    )..where((g) => g.id.equals('deleted-parent'))).getSingle();
    expect(parent.isDeleted, isTrue);
    expect(
      (await db.memberGroupsDao.getGroupById('child'))!.parentGroupId,
      'pk-group-deleted-uuid',
    );
    expect(await db.select(db.memberGroups).get(), hasLength(2));
  });

  for (final pkBacked in [false, true]) {
    for (final reverseDelivery in [false, true]) {
      test('three-level ${pkBacked ? 'PK' : 'ordinary'} hierarchy survives '
          '${reverseDelivery ? 'child-first' : 'parent-first'} sync', () async {
        final source = AppDatabase(NativeDatabase.memory());
        final target = AppDatabase(NativeDatabase.memory());
        addTearDown(source.close);
        addTearDown(target.close);
        final outgoing = buildSyncAdapterWithCompletion(
          source,
        ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
        final incoming = buildSyncAdapterWithCompletion(
          target,
        ).adapter.entities.singleWhere((e) => e.tableName == 'member_groups');
        String localId(int i) => pkBacked ? 'pk-group-uuid-$i' : 'group-$i';
        for (var i = 0; i < 3; i++) {
          await source
              .into(source.memberGroups)
              .insert(
                MemberGroupsCompanion.insert(
                  id: localId(i),
                  name: 'Level $i',
                  createdAt: DateTime.utc(2026),
                  parentGroupId: Value(i == 0 ? null : localId(i - 1)),
                  displayOrder: Value(i + 4),
                  pluralkitUuid: Value(pkBacked ? 'uuid-$i' : null),
                ),
              );
        }
        final rows = await source.select(source.memberGroups).get();
        for (final row in reverseDelivery ? rows.reversed : rows) {
          await incoming.applyFields(
            outgoing.entityIdFor(row),
            outgoing.toSyncFields(row),
          );
        }
        final received = await target.select(target.memberGroups).get();
        final byName = {for (final row in received) row.name: row};
        expect(received, hasLength(3));
        expect(byName['Level 0']!.parentGroupId, isNull);
        for (var i = 1; i < 3; i++) {
          expect(
            byName['Level $i']!.parentGroupId,
            byName['Level ${i - 1}']!.id,
          );
          expect(byName['Level $i']!.displayOrder, i + 4);
        }
        // Sparse reparent and explicit root move must not flatten descendants.
        final middle = byName['Level 1']!;
        await incoming.applyFields(outgoing.entityIdFor(rows[1]), {
          'parent_group_id': null,
        });
        final moved = await target.memberGroupsDao.getGroupById(middle.id);
        final leaf = await target.memberGroupsDao.getGroupById(
          byName['Level 2']!.id,
        );
        expect(moved!.parentGroupId, isNull);
        expect(leaf!.parentGroupId, moved.id);
      });
    }
  }
}
