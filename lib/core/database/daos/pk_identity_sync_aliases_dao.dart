import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pk_identity_sync_aliases_table.dart';

part 'pk_identity_sync_aliases_dao.g.dart';

@DriftAccessor(tables: [PkIdentitySyncAliases])
class PkIdentitySyncAliasesDao extends DatabaseAccessor<AppDatabase>
    with _$PkIdentitySyncAliasesDaoMixin {
  PkIdentitySyncAliasesDao(super.db);

  Future<PkIdentitySyncAliasRow?> getByLegacyEntityId(
    String entityTable,
    String legacyEntityId,
  ) =>
      (select(pkIdentitySyncAliases)
            ..where(
              (t) =>
                  t.entityTable.equals(entityTable) &
                  t.legacyEntityId.equals(legacyEntityId),
            ))
          .getSingleOrNull();

  /// All aliases recorded for one entity table whose redirected PK identity
  /// matches the given uuid/id/member values. Used by the delete emitters to
  /// fan tombstones out to every legacy id of a merged logical entity.
  Future<List<PkIdentitySyncAliasRow>> getByIdentity(
    String entityTable, {
    String? pkUuid,
    String? pkId,
    String? memberId,
  }) {
    final query = select(pkIdentitySyncAliases)
      ..where((t) {
        final matchUuid = (pkUuid == null || pkUuid.isEmpty)
            ? const Constant<bool>(false)
            : t.pkUuid.equals(pkUuid);
        final matchPkId = (pkId == null || pkId.isEmpty)
            ? const Constant<bool>(false)
            : t.pkId.equals(pkId);
        final matchMember = (memberId == null || memberId.isEmpty)
            ? const Constant<bool>(false)
            : t.memberId.equals(memberId);
        return t.entityTable.equals(entityTable) &
            (matchUuid | matchPkId | matchMember);
      });
    return query.get();
  }

  Future<void> upsertAlias({
    required String entityTable,
    required String legacyEntityId,
    String? pkUuid,
    String? pkId,
    String? memberId,
    required String targetRowId,
  }) async {
    // Preserve the ORIGINAL createdAt on conflict so a redelivered redirect
    // (re-pair snapshot, quarantine replay) cannot push the timestamp forward.
    // The temporal re-resolution bound compares holder timestamps against this
    // createdAt; a refresh to now() could wrongly admit a later same-identity
    // row the original recording excluded. Only identity/target move on
    // conflict.
    final existing = await getByLegacyEntityId(entityTable, legacyEntityId);
    await into(pkIdentitySyncAliases).insertOnConflictUpdate(
      PkIdentitySyncAliasesCompanion.insert(
        entityTable: entityTable,
        legacyEntityId: legacyEntityId,
        pkUuid: Value(pkUuid),
        pkId: Value(pkId),
        memberId: Value(memberId),
        targetRowId: targetRowId,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> deleteByLegacyEntityId(
    String entityTable,
    String legacyEntityId,
  ) =>
      (delete(pkIdentitySyncAliases)..where(
            (t) =>
                t.entityTable.equals(entityTable) &
                t.legacyEntityId.equals(legacyEntityId),
          ))
          .go();

  /// Purge every alias in [entityTable] whose recorded redirect target is
  /// [targetRowId]. Called when a recorded holder row is terminally resolved by
  /// its OWN id (exact-id hard-delete, or a fields-tombstone that resolves to an
  /// existing row): once that row is dead, every legacy id whose recorded target
  /// is it dies with it, so a delayed legacy-id delete no-ops instead of
  /// re-resolving the now-stale identity onto a fresh re-import of the same PK
  /// identity (holder/re-import share a historical pk.created timestamp the
  /// temporal bound cannot tell apart).
  ///
  /// NOTE: this purges by recorded `target_row_id` only. When a holder is found
  /// via IDENTITY re-resolution (the resolved-holder delete path) a SIBLING
  /// alias may still point at a DIFFERENT dead row of the same identity, so that
  /// path uses [deleteByIdentity] instead.
  Future<void> deleteByTargetRowId(
    String entityTable,
    String targetRowId,
  ) =>
      (delete(pkIdentitySyncAliases)..where(
            (t) =>
                t.entityTable.equals(entityTable) &
                t.targetRowId.equals(targetRowId),
          ))
          .go();

  /// Purge every alias in [entityTable] redirecting the given PK identity,
  /// regardless of which (possibly long-dead) row each alias recorded as its
  /// target. Matches on the same uuid/id/member OR-predicate as [getByIdentity].
  ///
  /// Called on the resolved-holder terminal delete paths (members/fronting
  /// hardDelete that resolve a redirect alias to the current active holder and
  /// delete THAT row). Purging by `target_row_id == holderId` alone leaves a
  /// deeper variant open: a sibling alias whose recorded `target_row_id` is a
  /// different already-dead row of the same identity — the holder was found by
  /// re-resolving the identity, not by that recorded target. Such a sibling
  /// would survive the holder's death and let a delayed legacy-id delete
  /// re-resolve the stale identity onto a fresh re-import. Tying the purge to the
  /// IDENTITY (not the recorded target) closes that vector, mirroring
  /// `_fanOutPkIdentityAliasDeletes`' "the logical entity is gone, so the alias
  /// is dead weight" GC semantics.
  Future<void> deleteByIdentity(
    String entityTable, {
    String? pkUuid,
    String? pkId,
    String? memberId,
  }) {
    final hasUuid = pkUuid != null && pkUuid.isNotEmpty;
    final hasPkId = pkId != null && pkId.isNotEmpty;
    final hasMember = memberId != null && memberId.isNotEmpty;
    if (!hasUuid && !hasPkId && !hasMember) {
      return Future<void>.value();
    }
    return (delete(pkIdentitySyncAliases)..where((t) {
          final matchUuid = hasUuid
              ? t.pkUuid.equals(pkUuid)
              : const Constant<bool>(false);
          final matchPkId = hasPkId
              ? t.pkId.equals(pkId)
              : const Constant<bool>(false);
          final matchMember = hasMember
              ? t.memberId.equals(memberId)
              : const Constant<bool>(false);
          return t.entityTable.equals(entityTable) &
              (matchUuid | matchPkId | matchMember);
        }))
        .go();
  }
}
