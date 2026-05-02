/// Unified PluralKit row id derivation (WS3 step 9).
///
/// The PK importer has historically derived per-member fronting session ids
/// at two sites: the live diff sweep (`_runDiffSweep`) and the corrective
/// canonicalization pass that runs at the start of `_runFullImportWithClient`.
/// Diff sweep used `derivePkSessionId(sw.id, memberPkUuid)` and fell back to
/// the local member id if the reverse PK-UUID lookup ever failed; the
/// canonicalization pass derived directly off `pkUuid` with no fallback. The
/// two paths could disagree on the id for the same `(switchId, localMemberId)`
/// pair under odd map-state conditions, which would cause the canonicalization
/// pass to tombstone a row the diff sweep had just written.
///
/// This helper is the single source of truth for both call sites. Behavior:
/// 1. If the local member id resolves to a PK UUID via [pkUuidByLocalId],
///    derive `Uuid.v5(pkFrontingNamespace, "$switchId:$pkUuid")`.
/// 2. Otherwise, fall back to deriving from the local member id directly.
///    This keeps the id deterministic even on map-cache miss, so re-running
///    the same import on the same DB always produces the same id.
///
/// Fallback (#2) should be vanishingly rare in practice — `_buildUuidToLocalIdMap`
/// only includes members with both `pluralkitId` AND `pluralkitUuid`, and the
/// callers only feed local ids that came from that very map. The path exists
/// so a partially-mapped DB doesn't tombstone live rows.
///
/// See:
/// - `docs/analysis/fronting-per-member-sessions-review-2026-04-30.md` finding #8
/// - `docs/analysis/fronting-per-member-sessions-remediation-plan-2026-04-30.md`
///   Workstream 3 step 9
library;

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';

/// Derive the canonical PK fronting session row id for a given
/// `(switchId, localMemberId)` pair.
///
/// [pkUuidByLocalId] is a forward map from local member id to the member's
/// PluralKit UUID. Pass an empty map (or one that does not contain
/// [localMemberId]) to force the fallback branch.
///
/// The derived id is stable for the same `(switchId, localMemberId)` so long
/// as [pkUuidByLocalId] either contains the same mapping or is missing the
/// local id entirely. Toggling between "present with pk uuid X" and
/// "present with pk uuid Y" *will* change the derived id — but no caller
/// should ever flip a member's PK UUID mid-sweep.
String deriveCanonicalPkSessionId({
  required String switchId,
  required String localMemberId,
  required Map<String, String> pkUuidByLocalId,
}) {
  final pkUuid = pkUuidByLocalId[localMemberId];
  if (pkUuid != null) {
    return derivePkSessionId(switchId, pkUuid);
  }
  // Fallback: PK UUID unknown for this local member. Derive deterministically
  // off the local id so the id is at least stable on re-runs against the
  // same DB. Matches the legacy diff-sweep behavior in `_localIdToPkUuid`.
  return derivePkSessionId(switchId, localMemberId);
}
