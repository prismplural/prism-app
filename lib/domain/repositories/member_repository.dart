import 'package:prism_plurality/domain/models/member.dart' as domain;

abstract class MemberRepository {
  Future<List<domain.Member>> getAllMembers();
  Stream<List<domain.Member>> watchAllMembers();
  Stream<List<domain.Member>> watchActiveMembers();
  Future<domain.Member?> getMemberById(String id);
  Stream<domain.Member?> watchMemberById(String id);
  Future<void> createMember(domain.Member member);
  Future<void> updateMember(domain.Member member);
  Future<void> deleteMember(String id);
  Future<List<domain.Member>> getMembersByIds(List<String> ids);
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids);
  Future<int> getCount();

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
