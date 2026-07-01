import 'package:prism_plurality/domain/models/member.dart' as domain;

abstract class MemberRepository {
  Future<List<domain.Member>> getAllMembers();
  Future<List<domain.Member>> getAllMembersIncludingDeleted();
  Stream<List<domain.Member>> watchAllMembers();
  Stream<List<domain.Member>> watchActiveMembers();
  Future<domain.Member?> getMemberById(String id);
  Stream<domain.Member?> watchMemberById(String id);
  Future<void> createMember(domain.Member member);
  Future<void> updateMember(domain.Member member);

  /// Keyed patch-style update. Apply only the supplied fields to an
  /// active member row and emit a corresponding per-field sync update.
  ///
  /// Returns:
  ///  * `0` — row missing or tombstoned (no-op, no emission).
  ///  * `1` — active row patched; emits `syncRecordUpdate` for the
  ///    fields that actually differ from the stored row. Empty diff
  ///    returns 1 as a no-op success.
  ///
  /// Unknown keys are silently filtered. Modeled on
  /// `updateHabitFields(id, Map)`; used by the board-posts repo's
  /// `markInboxOpenedFor` to route `board_last_read_at` writes through
  /// the members repo without inlining a row read and diff.
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  );
  Future<void> deleteMember(String id);
  Future<List<domain.Member>> getMembersByIds(List<String> ids);
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids);
  Future<int> getCount();

  // -- PR 2 of pluralkit-link-management plan ------------------------------

  /// User-driven (or applier-driven on user-confirmed decisions) link to a
  /// PluralKit member. Atomically writes the PK link fields supplied in
  /// [patch] AND sets `pluralkit_sync_ignored` to false. The path used
  /// whenever the intent is "link this member and (re-)enable sync."
  ///
  /// Contract:
  ///   - [patch] MUST contain at least one of `pluralkit_uuid` /
  ///     `pluralkit_id` (validated; AssertionError otherwise).
  ///   - The method ALWAYS injects `pluralkit_sync_ignored=false` into
  ///     the patch before writing. Callers MAY include
  ///     `pluralkit_sync_ignored: false` in [patch] (idempotent with the
  ///     force-injection); callers MUST NOT pass
  ///     `pluralkit_sync_ignored: true`.
  ///   - Returns 0 for tombstoned rows.
  ///   - Patch keys are validated against the same member-field allowlist
  ///     as `updateMemberFields` (`_memberPatchKeys` in
  ///     `drift_member_repository.dart`).
  Future<int> applyPluralKitLink(
    String memberId,
    Map<String, dynamic> patch,
  );

  /// System-driven write of PK identifiers AFTER a push to the PK server
  /// returned them. Does NOT touch `pluralkit_sync_ignored`; preserves
  /// whatever the user has set.
  ///
  /// Used by post-push writebacks (e.g. `_linkBackLocally` in the one-shot
  /// push service). If the user excluded the member between push start and
  /// writeback, the PK identifiers still record locally (so future "Resume
  /// sync" picks up the established PK identity without re-creating) and
  /// exclude remains durable.
  ///
  /// Contract:
  ///   - [patch] MUST contain at least one of `pluralkit_uuid` /
  ///     `pluralkit_id` (validated).
  ///   - [patch] MUST NOT contain `pluralkit_sync_ignored` (validated).
  ///   - Returns 0 for tombstoned rows.
  ///   - Patch keys validated against `_memberPatchKeys`.
  Future<int> recordPluralKitIdentity(
    String memberId,
    Map<String, dynamic> patch,
  );

  /// User picked "Exclude from PluralKit sync." Sets
  /// `pluralkit_sync_ignored=true`. Does NOT clear PK link fields — they
  /// remain as historical metadata and to keep cross-device PK lookups
  /// from missing the local row.
  Future<int> excludePluralKitSync(String memberId);

  /// User picked "Resume PluralKit sync." Sets
  /// `pluralkit_sync_ignored=false`. The only path besides
  /// [applyPluralKitLink] allowed to transition the flag from true to
  /// false.
  Future<int> resumePluralKitSync(String memberId);

  // -- Plan 02 (PK deletion push) ------------------------------------------

  /// Soft-deleted members that still have a PK link + a stamped intent
  /// epoch. Not filtered by `is_deleted = false` (unlike [getAllMembers]).
  Future<List<domain.Member>> getDeletedLinkedMembers();

  /// Clear `pluralkitId` / `pluralkitUuid` on a tombstone row and emit a
  /// CRDT op so peers converge. Row stays `is_deleted = true`. R3.
  Future<void> clearPluralKitLink(String id);

  /// Stamp the synced cross-device `delete_push_started_at` (ms since
  /// epoch) via `syncRecordUpdate` so peer devices can see who's pushing.
  /// R6.
  Future<void> stampDeletePushStartedAt(String id, int timestampMs);

  /// F4: stamp the synced cross-device `create_push_started_at` (ms since
  /// epoch) via `syncRecordUpdate` so peers don't double-POST a new member.
  Future<void> stampCreatePushStartedAt(String id, int timestampMs);

  /// F4: clear the create-push lease once the create completes or is adopted.
  Future<void> clearCreatePushStartedAt(String id);

  // -- Unknown sentinel ----------------------------------------------------

  /// Ensures the deterministic Unknown sentinel member exists, creating
  /// it via `syncRecordCreate` if missing.  Returns the (member, wasCreated)
  /// pair so callers that report counters (e.g. migration) can observe
  /// whether a write happened.
  ///
  /// Idempotent: two concurrent calls produce the same row id; the
  /// loser's PK constraint violation is caught and the winning row is
  /// refetched (see `DriftMemberRepository.ensureUnknownSentinelMember`).
  /// Used by every code path that needs the sentinel — the add-front
  /// sheet's "Front as Unknown" flow, the per-member fronting migration
  /// (orphan reassignment), the SP importer (entries with `member: "unknown"`),
  /// and the data import service (orphan native rows).
  Future<({domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember();
}
