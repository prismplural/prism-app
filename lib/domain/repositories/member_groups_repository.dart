import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';

abstract class MemberGroupsRepository {
  Stream<List<domain.MemberGroup>> watchAllGroups();

  /// One-shot list of all active groups (mirrors [watchAllGroups]'s domain
  /// mapping). Prefer this over awaiting a stream provider's `.future` in
  /// non-watching contexts, which can stall.
  Future<List<domain.MemberGroup>> getAllGroups();
  Stream<domain.MemberGroup?> watchGroupById(String id);
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId);
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId);
  Stream<List<domain.MemberGroupEntry>> watchAllGroupEntries();
  Future<List<domain.MemberGroupEntry>> getAllGroupEntries();
  Stream<Map<String, int>> watchMemberCountsByGroup();
  Future<void> createGroup(domain.MemberGroup group);
  Future<void> updateGroup(domain.MemberGroup group);

  /// Reorders groups by writing `displayOrder` for changed rows.
  ///
  /// Implementations should preserve ordinary update sync semantics while
  /// avoiding per-row local database writes where possible.
  Future<void> reorderGroups(List<domain.MemberGroup> groups);

  Future<void> deleteGroup(String groupId);

  /// Promotes all direct children to root level, then deletes [groupId].
  Future<void> promoteChildrenToRoot(String groupId);

  /// Soft-deletes [groupId] and all descendant groups (and their entries).
  Future<void> deleteGroupWithDescendants(String groupId);

  Future<void> addMemberToGroup(
    String groupId,
    String memberId,
    String entryId,
  );
  Future<void> removeMemberFromGroup(String groupId, String memberId);

  /// Reconciles [groupId] and all of its active entries against this device's
  /// field_versions, even if the row is currently marked sync-suppressed or was
  /// recently dismissed from PK review. Used by repair/dismissal flows to push
  /// edits accumulated during the suppression window to peers: fields whose
  /// local value already matches the known winner emit nothing, diverged fields
  /// emit at a fresh HLC, and never-synced fields emit as floor-HLC backfill, so
  /// it can never clobber a peer's un-pulled newer edit.
  Future<void> emitGroupSyncState(String groupId);

  /// Atomically writes the group's `sortState` with `mode = manual` and
  /// `manualOrder = orderedEntryIds`, intersected with the currently live
  /// entries (concurrently-tombstoned ids in [orderedEntryIds] are dropped;
  /// concurrently-added live ids missing from [orderedEntryIds] are appended
  /// sorted by id ascending). Emits one parent `syncRecordUpdate` so the
  /// `(mode, manualOrder)` pair converges as a single LWW field on peers.
  Future<SnapshotApplyResult> setGroupManualOrderSnapshot(
    String groupId,
    List<String> orderedEntryIds,
  );

  /// Writes a new `sortState` for [groupId] with the given [mode] while
  /// preserving the current `manualOrder` from the stored row. Emits one
  /// parent `syncRecordUpdate`. No-op when the group is not found.
  Future<void> setGroupSortMode(String groupId, GroupSortMode mode);
}
