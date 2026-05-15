import 'package:freezed_annotation/freezed_annotation.dart';

import 'group_sort_mode.dart';

part 'group_sort_state.freezed.dart';
part 'group_sort_state.g.dart';

/// Per-group sort state. Persisted as one JSON-encoded column
/// (`member_groups.sort_state`) so `(mode, manualOrder)` merges as a single
/// sync field — one winner per round under per-field LWW.
@freezed
abstract class GroupSortState with _$GroupSortState {
  const GroupSortState._();

  const factory GroupSortState({
    @Default(GroupSortMode.manual) GroupSortMode mode,
    @Default(<String>[]) List<String> manualOrder,
  }) = _GroupSortState;

  /// Const empty state, usable in `@Default(...)` on freezed fields.
  static const GroupSortState manualEmpty = _GroupSortState();

  factory GroupSortState.locked(GroupSortMode mode) =>
      GroupSortState(mode: mode);

  factory GroupSortState.fromJson(Map<String, dynamic> json) =>
      _$GroupSortStateFromJson(json);

  bool get isManual => mode == GroupSortMode.manual;
}
