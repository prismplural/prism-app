/// Sort modes available for members within a group.
///
/// Persisted as part of [GroupSortState], serialized to JSON in the
/// `member_groups.sort_state` column as the int index of this enum.
///
/// Unknown values from older or newer peers fall back to [manual] via
/// [fromInt] — see plan §"Validation: reject at apply, never store garbage"
/// (`docs/plans/2026-05-14-group-member-ordering.md`).
enum GroupSortMode {
  /// Drag-reorder; order persisted in `sortState.manualOrder`.
  manual,

  /// Sorted by member name, A → Z, case-insensitive, with id tiebreaker.
  nameAsc,

  /// Sorted by member name, Z → A, case-insensitive, with id tiebreaker.
  nameDesc,

  /// Sorted by member `createdAt` descending (most recent first).
  /// UI copy is "Recently added"; the internal name keeps the `Desc` suffix
  /// to disambiguate from future "recently fronted"/"recently updated" sorts.
  recentDesc;

  /// Parse a persisted int back into a [GroupSortMode]. Any null,
  /// out-of-range, or otherwise unrecognized value falls back to [manual] —
  /// this is the apply-path safety net for forward-compatibility with peers
  /// that introduce new modes.
  static GroupSortMode fromInt(int? i) {
    if (i == null) return GroupSortMode.manual;
    try {
      if (i < 0 || i >= GroupSortMode.values.length) return GroupSortMode.manual;
      return GroupSortMode.values[i];
    } catch (_) {
      return GroupSortMode.manual;
    }
  }

  /// Serialized integer representation persisted in `sort_state` JSON.
  int get asInt => index;
}
