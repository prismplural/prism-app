import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';

/// The single shared guard for the PK-identity alias machinery.
///
/// Returns `true` when [legacyEntityId] must NEVER be aliased onto a winner row
/// or emitted as an alias-delete tombstone for [table], because doing so would
/// hard-delete an active row on this or a peer device. The predicate is the one
/// source of truth consumed by every alias recorder (adapter), every
/// alias-delete emitter (repository + importer + member/fronting fan-out), and
/// the migration purge.
///
/// It is forbidden when [legacyEntityId] either:
///   1. equals the deterministic self-id form for the identity — the importer's
///      `pk-group-<uuid>` ([PkGroupsImporter.deriveGroupId]), which is by
///      construction every importing device's own local row id; or
///   2. matches ANY active (`is_deleted = 0`) local row id in [table] — an
///      id that is currently someone's live row; aliasing a stale self-id makes
///      every group update tombstone peers' active rows.
///
/// [pkUuid] is the canonical PluralKit uuid of the identity the alias points
/// at; it is only used for the self-id-form check and may be null/empty for
/// non-group tables (members/fronting_sessions have no deterministic self-id
/// form, so check #1 is a no-op there and check #2 carries the guard).
Future<bool> isForbiddenAliasTarget(
  AppDatabase db,
  String table,
  String legacyEntityId,
  String? pkUuid,
) async {
  // (1) Deterministic self-id form. The importer mints group rows under the
  // hyphen-form `pk-group-<uuid>` id; on every device that PK-imported, that id
  // IS the device's own active row, so it must never be aliased or tombstoned.
  if (pkUuid != null &&
      pkUuid.isNotEmpty &&
      legacyEntityId == PkGroupsImporter.deriveGroupId(pkUuid)) {
    return true;
  }

  // (2) Active local row match. Resolved generically against the named table so
  // the same predicate serves member_groups, members, and fronting_sessions.
  final rows = await db
      .customSelect(
        'SELECT 1 FROM $table WHERE id = ? AND is_deleted = 0 LIMIT 1',
        variables: [Variable<String>(legacyEntityId)],
      )
      .get();
  return rows.isNotEmpty;
}
