import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// Cross-device regression test for C1: applying a remote canonical
/// member_groups op must not record an alias that later produces a
/// data-loss tombstone for the receiving device's own active row.
void main() {
  test('applyFields does not record an alias when incoming id matches an '
      'active local row for the same PK UUID', () async {
    const pkUuid = 'pk-g-uuid-shared';
    const localRowId = 'pk-group-$pkUuid';
    final createdAt = DateTime.utc(2026, 4, 18, 12);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: localRowId,
            name: 'Core',
            createdAt: createdAt,
            pluralkitUuid: const Value(pkUuid),
          ),
        );

    final groupsEntity = buildSyncAdapterWithCompletion(db).adapter.entities
        .singleWhere((entity) => entity.tableName == 'member_groups');

    await groupsEntity.applyFields(localRowId, {
      'name': 'Remote Legacy',
      'display_order': 1,
      'group_type': 0,
      'created_at': createdAt.toIso8601String(),
      'pluralkit_uuid': pkUuid,
      'is_deleted': false,
    });

    final aliases = await db
        .customSelect('SELECT legacy_entity_id FROM pk_group_sync_aliases')
        .get();
    expect(aliases, isEmpty);
  });

  test('two devices sharing a `pk-group-<uuid>` local id never cross-record '
      'an alias that would emit a hard-delete for the peer', () async {
    const pkUuid = 'pk-g-uuid-shared';
    const localRowId = 'pk-group-$pkUuid';
    final createdAt = DateTime.utc(2026, 4, 18, 12);

    final deviceA = AppDatabase(NativeDatabase.memory());
    addTearDown(deviceA.close);
    final deviceB = AppDatabase(NativeDatabase.memory());
    addTearDown(deviceB.close);

    // Both devices imported PK groups locally and share the importer's
    // hyphen-form local id, `pk-group-<uuid>`, for the same PK group.
    Future<void> seedLocalRow(AppDatabase db) async {
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: localRowId,
              name: 'Core',
              createdAt: createdAt,
              pluralkitUuid: const Value(pkUuid),
            ),
          );
    }

    await seedLocalRow(deviceA);
    await seedLocalRow(deviceB);

    // Build both devices' sync entity wrappers (with completion hooks),
    // so we can drive the cross-device handoff via the real apply path.
    final entityA = buildSyncAdapterWithCompletion(deviceA).adapter.entities
        .singleWhere((entity) => entity.tableName == 'member_groups');
    final entityB = buildSyncAdapterWithCompletion(deviceB).adapter.entities
        .singleWhere((entity) => entity.tableName == 'member_groups');

    // Device A encodes its local row as an outgoing payload, then Device B
    // applies it under the pre-H2/non-canonical entity id. This is the
    // remaining C1 hole: the incoming id collides with Device B's active
    // local row id for the same PK UUID.
    final deviceARow = await (deviceA.select(
      deviceA.memberGroups,
    )..where((t) => t.id.equals(localRowId))).getSingle();
    final aPayload = entityA.toSyncFields(deviceARow);

    await entityB.applyFields(localRowId, aPayload);

    // Device B's active PK group row is still present.
    final bActive = await (deviceB.select(
      deviceB.memberGroups,
    )..where((t) => t.id.equals(localRowId))).getSingle();
    expect(bActive.isDeleted, isFalse);

    // Post-apply, Device B must NOT have recorded an alias for its own
    // active local row id. Recording such an alias would later produce
    // an alias-delete that hard-deletes Device A's active row.
    final bAliases = await deviceB
        .customSelect('SELECT legacy_entity_id FROM pk_group_sync_aliases')
        .get();
    expect(
      bAliases.map((row) => row.data['legacy_entity_id']),
      isNot(contains(localRowId)),
      reason:
          'Device B must not auto-alias its own active row id; that '
          'would cause a cross-device alias-delete cascade.',
    );

    // The dao-level helper that the repository uses to enumerate
    // alias-deletes returns nothing targeting the shared local row id.
    final aliasesByPkUuid = await deviceB.pkGroupSyncAliasesDao
        .getByPkGroupUuid(pkUuid);
    expect(
      aliasesByPkUuid.map((alias) => alias.legacyEntityId),
      isNot(contains(localRowId)),
    );

    // Simulate Device B's later edit emit: the repository would enumerate
    // aliases for this PK UUID and send deletes for them. Applying that set
    // to Device A must not delete Device A's active row.
    for (final alias in aliasesByPkUuid) {
      await entityA.hardDelete(alias.legacyEntityId);
    }

    final aActive = await (deviceA.select(
      deviceA.memberGroups,
    )..where((t) => t.id.equals(localRowId))).getSingle();
    expect(aActive.isDeleted, isFalse);
  });

  test(
    'legacy alias delete does not resolve through PK UUID to the active winner',
    () async {
      const pkUuid = 'pk-g-uuid-repaired';
      final createdAt = DateTime.utc(2026, 4, 18, 12);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'winner-local-id',
              name: 'Winner',
              createdAt: createdAt,
              pluralkitUuid: const Value(pkUuid),
            ),
          );
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'legacy-loser-id',
        pkGroupUuid: pkUuid,
        canonicalEntityId: 'pk-group:$pkUuid',
      );

      final groupsEntity = buildSyncAdapterWithCompletion(db).adapter.entities
          .singleWhere((entity) => entity.tableName == 'member_groups');

      await groupsEntity.hardDelete('legacy-loser-id');

      final winner = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('winner-local-id'))).getSingle();
      expect(winner.isDeleted, isFalse);
    },
  );
}
