import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// Cross-device regression test for C1: applying a remote canonical
/// member_groups op must not record an alias that later produces a
/// data-loss tombstone for the receiving device's own active row.
void main() {
  test(
    'two devices sharing a `pk-group-<uuid>` local id never cross-record '
    'an alias that would emit a hard-delete for the peer',
    () async {
      const pkUuid = 'pk-g-uuid-shared';
      const canonicalEntityId = 'pk-group:$pkUuid';
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
      final entityA = buildSyncAdapterWithCompletion(
        deviceA,
      ).adapter.entities.singleWhere(
            (entity) => entity.tableName == 'member_groups',
          );
      final entityB = buildSyncAdapterWithCompletion(
        deviceB,
      ).adapter.entities.singleWhere(
            (entity) => entity.tableName == 'member_groups',
          );

      // Device A encodes its local row as an outgoing canonical sync
      // payload, then Device B applies it. This mirrors the real
      // post-cutover flow where canonical PK-group updates propagate.
      final deviceARow = await (deviceA.select(
        deviceA.memberGroups,
      )..where((t) => t.id.equals(localRowId))).getSingle();
      final aPayload = entityA.toSyncFields(deviceARow);

      await entityB.applyFields(canonicalEntityId, aPayload);

      // Device B's active PK group row is still present.
      final bActive = await (deviceB.select(
        deviceB.memberGroups,
      )..where((t) => t.id.equals(localRowId))).getSingle();
      expect(bActive.isDeleted, isFalse);

      // Post-apply, Device B must NOT have recorded an alias for its own
      // active local row id. Recording such an alias would later produce
      // an alias-delete that hard-deletes Device A's active row.
      final bAliases = await deviceB
          .customSelect(
            'SELECT legacy_entity_id FROM pk_group_sync_aliases',
          )
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
    },
  );
}
