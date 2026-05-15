/// Outcome of [MemberGroupsRepository.setGroupManualOrderSnapshot]:
/// [SnapshotApplied] when the supplied ids were an exact permutation of
/// the live set; [SnapshotRecovered] when the input drifted (concurrent
/// add/remove) and was reconciled — caller surfaces a recovery toast.
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

  /// Ids in the input that aren't live (tombstoned or duplicate); dropped.
  final List<String> droppedIds;

  /// Ids live in the group but missing from the input (concurrently added);
  /// appended at the end, sorted by id.
  final List<String> appendedIds;
}
