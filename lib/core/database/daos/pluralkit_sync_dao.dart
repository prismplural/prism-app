import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pluralkit_sync_state_table.dart';

part 'pluralkit_sync_dao.g.dart';

@DriftAccessor(tables: [PluralKitSyncState])
class PluralKitSyncDao extends DatabaseAccessor<AppDatabase>
    with _$PluralKitSyncDaoMixin {
  PluralKitSyncDao(super.db);

  static const _configId = 'pk_config';

  Future<PluralKitSyncStateData> getSyncState() async {
    final result = await (select(pluralKitSyncState)
          ..where((s) => s.id.equals(_configId)))
        .getSingleOrNull();
    if (result != null) return result;

    // Create default row on first access
    await into(pluralKitSyncState).insert(
      const PluralKitSyncStateCompanion(
        id: Value(_configId),
      ),
    );
    return (select(pluralKitSyncState)
          ..where((s) => s.id.equals(_configId)))
        .getSingle();
  }

  Stream<PluralKitSyncStateData> watchSyncState() {
    // Ensure the row exists before watching
    getSyncState();
    return (select(pluralKitSyncState)
          ..where((s) => s.id.equals(_configId)))
        .watchSingle();
  }

  Future<void> upsertSyncState(PluralKitSyncStateCompanion state) =>
      into(pluralKitSyncState).insertOnConflictUpdate(state);
}
