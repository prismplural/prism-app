import 'package:freezed_annotation/freezed_annotation.dart';

import 'group_sort_mode.dart';

part 'group_sort_state.freezed.dart';
part 'group_sort_state.g.dart';

/// Per-group sort state — the (mode, manualOrder) pair that drives the
/// member list ordering within a group.
///
/// Persisted as a single JSON-encoded column `member_groups.sort_state` so
/// the pair is one sync field — one `pending_op`, one `field_versions` row,
/// one merge winner per round. See plan §"Design decision" in
/// `docs/plans/2026-05-14-group-member-ordering.md`.
@freezed
abstract class GroupSortState with _$GroupSortState {
  const GroupSortState._();

  const factory GroupSortState({
    @Default(GroupSortMode.manual) GroupSortMode mode,
    @Default(<String>[]) List<String> manualOrder,
  }) = _GroupSortState;

  /// Const sentinel for the empty manual state. Suitable for use as a
  /// `@Default(...)` argument on freezed fields that need a non-null
  /// `GroupSortState`.
  static const GroupSortState manualEmpty = _GroupSortState();

  /// Factory for a locked sort mode with no `manualOrder`. The caller is
  /// expected to either flip to `manual` via `setGroupManualOrderSnapshot`
  /// or leave the order empty (sort is computed from member properties at
  /// read time).
  factory GroupSortState.locked(GroupSortMode mode) =>
      GroupSortState(mode: mode);

  factory GroupSortState.fromJson(Map<String, dynamic> json) =>
      _$GroupSortStateFromJson(json);

  /// True iff [mode] is [GroupSortMode.manual].
  bool get isManual => mode == GroupSortMode.manual;
}
