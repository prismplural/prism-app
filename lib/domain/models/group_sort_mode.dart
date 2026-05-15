/// Sort modes for members within a group. Persisted as the int index in
/// `member_groups.sort_state`; unknown ints from older/newer peers fall
/// back to [manual] via [fromInt] (forward-compat).
enum GroupSortMode {
  /// Drag-reorder; order persisted in `sortState.manualOrder`.
  manual,
  nameAsc,
  nameDesc,

  /// Sorts by `createdAt` desc; UI copy is "Recently added". The `Desc`
  /// suffix disambiguates from future "recently fronted/updated" sorts.
  recentDesc;

  /// Null, out-of-range, or otherwise unrecognized values fall back to
  /// [manual]. Apply-path safety net for forward-compat with newer peers.
  static GroupSortMode fromInt(int? i) {
    if (i == null) return GroupSortMode.manual;
    try {
      if (i < 0 || i >= GroupSortMode.values.length) return GroupSortMode.manual;
      return GroupSortMode.values[i];
    } catch (_) {
      return GroupSortMode.manual;
    }
  }

  int get asInt => index;
}
