import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_front_member_alias_resolver.dart';

const pkFrontOrphanEngineRecoveryCheckedKey =
    'sync.pk_front_orphan_projection_repair_v1_checked';

Future<PkFrontOrphanProjectionRepairResult?> repairPkFrontOrphansAfterUpgrade({
  required AppDatabase db,
  required int? versionBefore,
  required int versionAfter,
}) {
  if (versionBefore == null || versionBefore >= versionAfter) {
    return Future.value();
  }
  return PkFrontOrphanProjectionRepair(db).run();
}

typedef PkWinningFieldReader =
    Future<String?> Function({
      required String table,
      required String entityId,
      required String field,
    });

Future<PkFrontOrphanProjectionRepairResult> runPkFrontOrphanEngineRecoveryOnce({
  required AppDatabase db,
  required Future<bool> Function() getChecked,
  required Future<void> Function() setChecked,
  required PkWinningFieldReader readWinningField,
}) async {
  if (await getChecked()) {
    return const PkFrontOrphanProjectionRepairResult();
  }
  final result = await PkFrontOrphanProjectionRepair(
    db,
  ).run(readWinningField: readWinningField);
  await setChecked();
  return result;
}

class PkFrontOrphanProjectionRepairResult {
  const PkFrontOrphanProjectionRepairResult({
    this.scanned = 0,
    this.repaired = 0,
    this.noEvidence = 0,
    this.shortIdOnly = 0,
    this.legacyRowExists = 0,
    this.staleTarget = 0,
    this.ambiguousIdentity = 0,
    this.aliasChain = 0,
    this.engineTombstoned = 0,
    this.malformedEngineEvidence = 0,
  });

  final int scanned;
  final int repaired;
  final int noEvidence;
  final int shortIdOnly;
  final int legacyRowExists;
  final int staleTarget;
  final int ambiguousIdentity;
  final int aliasChain;
  final int engineTombstoned;
  final int malformedEngineEvidence;

  int get unresolved => scanned - repaired;

  String get unresolvedSummary =>
      'noEvidence=$noEvidence shortIdOnly=$shortIdOnly '
      'legacyRowExists=$legacyRowExists staleTarget=$staleTarget '
      'ambiguousIdentity=$ambiguousIdentity aliasChain=$aliasChain '
      'engineTombstoned=$engineTombstoned '
      'malformedEngineEvidence=$malformedEngineEvidence';
}

/// Repairs only the local Drift projection. It never emits sync operations.
class PkFrontOrphanProjectionRepair {
  const PkFrontOrphanProjectionRepair(this._db);

  final AppDatabase _db;

  Future<PkFrontOrphanProjectionRepairResult> run({
    PkWinningFieldReader? readWinningField,
  }) async {
    final orphanRows = await _db.customSelect('''
      SELECT f.member_id AS legacy_member_id, COUNT(*) AS front_count
      FROM fronting_sessions f
      WHERE f.is_deleted = 0
        AND f.session_type = 0
        AND f.member_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM members m
          WHERE m.id = f.member_id AND m.is_deleted = 0
        )
      GROUP BY f.member_id
      ORDER BY f.member_id
    ''').get();

    var scanned = 0;
    var repaired = 0;
    var noEvidence = 0;
    var shortIdOnly = 0;
    var legacyRowExists = 0;
    var staleTarget = 0;
    var ambiguousIdentity = 0;
    var aliasChain = 0;
    var engineTombstoned = 0;
    var malformedEngineEvidence = 0;

    await _db.transaction(() async {
      for (final orphan in orphanRows) {
        final legacyId = orphan.read<String>('legacy_member_id');
        final frontCount = orphan.read<int>('front_count');
        scanned += frontCount;

        final aliasResolution = await resolvePkFrontMemberAlias(_db, legacyId);
        String? targetId;
        String? engineStableUuid;
        switch (aliasResolution.kind) {
          case PkFrontMemberAliasResolutionKind.resolved:
            targetId = aliasResolution.targetMemberId;
          case PkFrontMemberAliasResolutionKind.noAlias:
            if (readWinningField == null) {
              noEvidence += frontCount;
              continue;
            }
            final engineResolution = await _resolveFromEngine(
              legacyId,
              readWinningField,
            );
            switch (engineResolution.kind) {
              case _EngineResolutionKind.resolved:
                targetId = engineResolution.targetMemberId;
                engineStableUuid = engineResolution.stablePkUuid;
              case _EngineResolutionKind.noEvidence:
                noEvidence += frontCount;
                continue;
              case _EngineResolutionKind.tombstoned:
                engineTombstoned += frontCount;
                continue;
              case _EngineResolutionKind.ambiguous:
                ambiguousIdentity += frontCount;
                continue;
              case _EngineResolutionKind.malformed:
                malformedEngineEvidence += frontCount;
                continue;
            }
          case PkFrontMemberAliasResolutionKind.shortIdOnly:
            shortIdOnly += frontCount;
            continue;
          case PkFrontMemberAliasResolutionKind.legacyRowExists:
            legacyRowExists += frontCount;
            continue;
          case PkFrontMemberAliasResolutionKind.staleTarget:
            staleTarget += frontCount;
            continue;
          case PkFrontMemberAliasResolutionKind.ambiguousIdentity:
            ambiguousIdentity += frontCount;
            continue;
          case PkFrontMemberAliasResolutionKind.aliasChain:
            aliasChain += frontCount;
            continue;
        }

        final changed = await _db.customUpdate(
          'UPDATE fronting_sessions SET member_id = ? '
          'WHERE member_id = ? AND is_deleted = 0 AND session_type = 0',
          variables: [
            Variable.withString(targetId!),
            Variable.withString(legacyId),
          ],
          updates: {_db.frontingSessions},
        );
        if (changed > 0 && engineStableUuid != null) {
          // The retained live winner and the unique local holder establish the
          // same durable identity evidence as a normal redirect. Persist it in
          // this transaction so a later hydrated payload carrying [legacyId]
          // cannot undo the projection repair. The DAO records the validation
          // time as provenance and this remains local-only sync metadata.
          await _db.pkIdentitySyncAliasesDao.upsertAlias(
            entityTable: 'members',
            legacyEntityId: legacyId,
            pkUuid: engineStableUuid,
            targetRowId: targetId,
          );
        }
        repaired += changed;
      }
    });

    return PkFrontOrphanProjectionRepairResult(
      scanned: scanned,
      repaired: repaired,
      noEvidence: noEvidence,
      shortIdOnly: shortIdOnly,
      legacyRowExists: legacyRowExists,
      staleTarget: staleTarget,
      ambiguousIdentity: ambiguousIdentity,
      aliasChain: aliasChain,
      engineTombstoned: engineTombstoned,
      malformedEngineEvidence: malformedEngineEvidence,
    );
  }

  Future<_EngineResolution> _resolveFromEngine(
    String legacyId,
    PkWinningFieldReader readWinningField,
  ) async {
    final deletedRaw = await readWinningField(
      table: 'members',
      entityId: legacyId,
      field: 'is_deleted',
    );
    final deleted = _decodeBool(deletedRaw);
    if (deleted == null) {
      return deletedRaw == null
          ? const _EngineResolution.noEvidence()
          : const _EngineResolution.malformed();
    }
    if (deleted) return const _EngineResolution.tombstoned();

    final uuidRaw = await readWinningField(
      table: 'members',
      entityId: legacyId,
      field: 'pluralkit_uuid',
    );
    final uuid = _decodeNonEmptyString(uuidRaw);
    if (uuid == null) {
      return uuidRaw == null
          ? const _EngineResolution.noEvidence()
          : const _EngineResolution.malformed();
    }

    final holders =
        await (_db.select(_db.members)
              ..where(
                (t) => t.isDeleted.equals(false) & t.pluralkitUuid.equals(uuid),
              )
              ..limit(2))
            .get();
    if (holders.length != 1) return const _EngineResolution.ambiguous();
    return _EngineResolution.resolved(holders.single.id, uuid);
  }
}

bool? _decodeBool(String? encoded) {
  if (encoded == null) return null;
  try {
    final value = jsonDecode(encoded);
    return value is bool ? value : null;
  } catch (_) {
    return null;
  }
}

String? _decodeNonEmptyString(String? encoded) {
  if (encoded == null) return null;
  try {
    final value = jsonDecode(encoded);
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  } catch (_) {
    return null;
  }
}

enum _EngineResolutionKind {
  resolved,
  noEvidence,
  tombstoned,
  ambiguous,
  malformed,
}

class _EngineResolution {
  const _EngineResolution.resolved(this.targetMemberId, this.stablePkUuid)
    : kind = _EngineResolutionKind.resolved;
  const _EngineResolution.noEvidence()
    : kind = _EngineResolutionKind.noEvidence,
      targetMemberId = null,
      stablePkUuid = null;
  const _EngineResolution.tombstoned()
    : kind = _EngineResolutionKind.tombstoned,
      targetMemberId = null,
      stablePkUuid = null;
  const _EngineResolution.ambiguous()
    : kind = _EngineResolutionKind.ambiguous,
      targetMemberId = null,
      stablePkUuid = null;
  const _EngineResolution.malformed()
    : kind = _EngineResolutionKind.malformed,
      targetMemberId = null,
      stablePkUuid = null;

  final _EngineResolutionKind kind;
  final String? targetMemberId;
  final String? stablePkUuid;
}
