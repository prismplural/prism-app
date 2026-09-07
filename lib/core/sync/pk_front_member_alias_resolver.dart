import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';

enum PkFrontMemberAliasResolutionKind {
  resolved,
  noAlias,
  shortIdOnly,
  legacyRowExists,
  staleTarget,
  ambiguousIdentity,
  aliasChain,
}

class PkFrontMemberAliasResolution {
  const PkFrontMemberAliasResolution(this.kind, {this.targetMemberId});

  final PkFrontMemberAliasResolutionKind kind;
  final String? targetMemberId;
}

/// Resolves a missing, device-local member id through durable alias evidence.
///
/// This deliberately requires the exact recorded holder and a stable PK UUID.
/// Identity-wide or short-id re-resolution can attach history to a later
/// re-import or to a different member after PK short-id reuse.
Future<PkFrontMemberAliasResolution> resolvePkFrontMemberAlias(
  AppDatabase db,
  String legacyMemberId,
) async {
  final rowAtLegacyId =
      await (db.select(db.members)
            ..where((t) => t.id.equals(legacyMemberId))
            ..limit(1))
          .getSingleOrNull();
  if (rowAtLegacyId != null) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.legacyRowExists,
    );
  }

  final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
    'members',
    legacyMemberId,
  );
  if (alias == null) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.noAlias,
    );
  }

  final pkUuid = alias.pkUuid?.trim();
  if (pkUuid == null || pkUuid.isEmpty) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.shortIdOnly,
    );
  }

  final targetAlias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
    'members',
    alias.targetRowId,
  );
  if (targetAlias != null) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.aliasChain,
    );
  }

  final target =
      await (db.select(db.members)
            ..where(
              (t) =>
                  t.id.equals(alias.targetRowId) &
                  t.isDeleted.equals(false) &
                  t.pluralkitUuid.equals(pkUuid),
            )
            ..limit(1))
          .getSingleOrNull();
  if (target == null) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.staleTarget,
    );
  }

  final liveHolders =
      await (db.select(db.members)
            ..where(
              (t) => t.isDeleted.equals(false) & t.pluralkitUuid.equals(pkUuid),
            )
            ..limit(2))
          .get();
  if (liveHolders.length != 1 || liveHolders.single.id != target.id) {
    return const PkFrontMemberAliasResolution(
      PkFrontMemberAliasResolutionKind.ambiguousIdentity,
    );
  }

  return PkFrontMemberAliasResolution(
    PkFrontMemberAliasResolutionKind.resolved,
    targetMemberId: target.id,
  );
}
