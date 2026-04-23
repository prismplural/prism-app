import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pk_group_sync_aliases_table.dart';

part 'pk_group_sync_aliases_dao.g.dart';

@DriftAccessor(tables: [PkGroupSyncAliases])
class PkGroupSyncAliasesDao extends DatabaseAccessor<AppDatabase>
    with _$PkGroupSyncAliasesDaoMixin {
  PkGroupSyncAliasesDao(super.db);

  Future<PkGroupSyncAliasRow?> getByLegacyEntityId(String legacyEntityId) =>
      (select(pkGroupSyncAliases)
            ..where((t) => t.legacyEntityId.equals(legacyEntityId)))
          .getSingleOrNull();

  Future<List<PkGroupSyncAliasRow>> getByPkGroupUuid(String pkGroupUuid) =>
      (select(
        pkGroupSyncAliases,
      )..where((t) => t.pkGroupUuid.equals(pkGroupUuid))).get();

  Future<void> upsertAlias({
    required String legacyEntityId,
    required String pkGroupUuid,
    required String canonicalEntityId,
  }) async {
    await into(pkGroupSyncAliases).insertOnConflictUpdate(
      PkGroupSyncAliasesCompanion.insert(
        legacyEntityId: legacyEntityId,
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> deleteByLegacyEntityId(String legacyEntityId) => (delete(
    pkGroupSyncAliases,
  )..where((t) => t.legacyEntityId.equals(legacyEntityId))).go();
}
