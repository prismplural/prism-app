import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pk_mapping_state_table.dart';

part 'pk_mapping_state_dao.g.dart';

/// DAO for the resumable PK mapping applier (plan 08).
@DriftAccessor(tables: [PkMappingState])
class PkMappingStateDao extends DatabaseAccessor<AppDatabase>
    with _$PkMappingStateDaoMixin {
  PkMappingStateDao(super.db);

  Future<PkMappingStateData?> getById(String id) =>
      (select(pkMappingState)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<PkMappingStateData>> getAll() => select(pkMappingState).get();

  Future<List<PkMappingStateData>> getPending() =>
      (select(pkMappingState)..where((t) => t.status.equals('pending'))).get();

  Future<void> upsert(PkMappingStateCompanion state) =>
      into(pkMappingState).insertOnConflictUpdate(state);

  Future<void> markApplied(String id) async {
    await (update(pkMappingState)..where((t) => t.id.equals(id))).write(
      PkMappingStateCompanion(
        status: const Value('applied'),
        errorMessage: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markFailed(String id, String error) async {
    await (update(pkMappingState)..where((t) => t.id.equals(id))).write(
      PkMappingStateCompanion(
        status: const Value('failed'),
        errorMessage: Value(error),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Clears all decisions — e.g. when the user dismisses the mapping flow
  /// and wants a fresh slate next time.
  Future<void> clearAll() => delete(pkMappingState).go();
}
