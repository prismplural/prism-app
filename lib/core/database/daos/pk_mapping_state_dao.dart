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

  /// Mark a decision `pending` ahead of (re)applying it WITHOUT clobbering any
  /// PK identifiers a prior (possibly crashed) attempt already persisted.
  ///
  /// 2026-06 PK audit M7: the applier's old `_recordPending` upserted with
  /// explicit `pkMemberId: Value(null)` / `pkMemberUuid: Value(null)` at the
  /// START of every (re)apply, wiping the ids that `_applyPushNew` writes
  /// post-POST. A crash between this row write and the local link-back then
  /// left a `pending` row with NULL ids → the next retry could not recognise
  /// the in-flight POST and re-POSTed → duplicate PK member. This method
  /// preserves the identifier columns (and `createdAt`) when the row already
  /// exists, only touching `decisionType` / `localMemberId` / `status` /
  /// `errorMessage` / `updatedAt`. The caller still passes the ids it knows
  /// about (e.g. for `link` / `import` decisions, which derive them straight
  /// from the decision) — those land on a FRESH insert; on conflict they are
  /// intentionally ignored in favour of whatever is already stored.
  Future<void> recordPending(PkMappingStateCompanion state) async {
    final id = state.id.value;
    final existing = await getById(id);
    if (existing == null) {
      await into(pkMappingState).insert(state);
      return;
    }
    // Row exists — update status/bookkeeping only. Do NOT pass pkMemberId /
    // pkMemberUuid / createdAt so the persisted identifiers survive a retry.
    await (update(pkMappingState)..where((t) => t.id.equals(id))).write(
      PkMappingStateCompanion(
        decisionType: state.decisionType,
        localMemberId: state.localMemberId,
        status: state.status,
        errorMessage: state.errorMessage,
        updatedAt: state.updatedAt,
      ),
    );
  }

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
