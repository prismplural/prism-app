/// Result returned by
/// [MemberGroupsRepository.setGroupManualOrderSnapshot] indicating whether
/// the requested order was applied verbatim or recovered against the live
/// entry set.
///
/// Two outcomes:
/// - [SnapshotApplied] — the supplied id list was a valid permutation of the
///   group's current live entry ids; persisted exactly as supplied.
/// - [SnapshotRecovered] — the input drifted from the live set (a concurrent
///   add or remove landed between the UI's read and the snapshot write).
///   The repository's "truncate-intersection-then-append-missing" recovery
///   produced a coherent `manualOrder`. The UI is expected to surface a
///   recovery toast.
///
/// See plan §"Read path invariants" + §"Batch 4 — Repository + providers" in
/// `docs/plans/2026-05-14-group-member-ordering.md`.
sealed class SnapshotApplyResult {
  const SnapshotApplyResult();

  const factory SnapshotApplyResult.applied() = SnapshotApplied;

  const factory SnapshotApplyResult.recovered({
    required List<String> droppedIds,
    required List<String> appendedIds,
  }) = SnapshotRecovered;
}

final class SnapshotApplied extends SnapshotApplyResult {
  const SnapshotApplied();
}

final class SnapshotRecovered extends SnapshotApplyResult {
  const SnapshotRecovered({
    required this.droppedIds,
    required this.appendedIds,
  });

  /// Entry ids that were present in the supplied order but no longer live in
  /// the group (concurrently tombstoned). Dropped from the persisted order.
  final List<String> droppedIds;

  /// Entry ids that are live in the group but were absent from the supplied
  /// order (concurrently added by another device). Appended at the end of
  /// the persisted order, sorted by id ascending for determinism.
  final List<String> appendedIds;
}
