import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

/// Strict decode of a stored or wire `sort_state` JSON blob.
///
/// Shape: `{"mode": <int>, "order": ["<entryId>", ...]}`. Returns `null` on
/// any structural failure (parse error, non-object, missing required keys,
/// non-list `order`, non-string elements, mixed types).
///
/// Unknown `mode` ints are NOT a decode failure — they are forward-compatible
/// and fall back to [GroupSortMode.manual] via [GroupSortMode.fromInt].
///
/// Defensive normalization on success: duplicate entry ids in `order` are
/// deduped, preserving first occurrence.
///
/// Shared between the apply-time validator in `drift_sync_adapter.dart`
/// (`_memberGroupsEntity.applyFields`) and the on-read mapper below. See plan
/// §"Validation: reject at apply, never store garbage" in
/// `docs/plans/2026-05-14-group-member-ordering.md`.
GroupSortState? tryDecodeSortState(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    if (!decoded.containsKey('mode') || !decoded.containsKey('order')) {
      return null;
    }

    final rawMode = decoded['mode'];
    final mode = rawMode is int
        ? GroupSortMode.fromInt(rawMode)
        : GroupSortMode.manual;

    final rawOrder = decoded['order'];
    if (rawOrder is! List) return null;
    final order = <String>[];
    final seen = <String>{};
    for (final item in rawOrder) {
      if (item is! String) return null;
      if (seen.add(item)) order.add(item);
    }

    return GroupSortState(mode: mode, manualOrder: order);
  } catch (_) {
    return null;
  }
}

class MemberGroupMapper {
  MemberGroupMapper._();

  static domain.MemberGroup toDomain(MemberGroupRow row) {
    return domain.MemberGroup(
      id: row.id,
      name: row.name,
      description: row.description,
      colorHex: row.colorHex,
      emoji: row.emoji,
      displayOrder: row.displayOrder,
      parentGroupId: row.parentGroupId,
      groupType: row.groupType,
      filterRules: row.filterRules,
      createdAt: row.createdAt,
      sortState: _decodeSortStateForRead(row.sortState, contextId: row.id),
    );
  }

  static MemberGroupsCompanion toCompanion(domain.MemberGroup model) {
    return MemberGroupsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      description: Value(model.description),
      colorHex: Value(model.colorHex),
      emoji: Value(model.emoji),
      displayOrder: Value(model.displayOrder),
      parentGroupId: Value(model.parentGroupId),
      groupType: Value(model.groupType),
      filterRules: Value(model.filterRules),
      createdAt: Value(model.createdAt),
      sortState: Value(encodeSortStateForColumn(model.sortState)),
    );
  }

  /// JSON-encode a [GroupSortState] for persistence in the
  /// `member_groups.sort_state` column.
  ///
  /// Shape: `{"mode": <int>, "order": ["<entryId>", ...]}`. By construction
  /// this is always valid for the on-wire schema — local writes can never
  /// propagate corrupt state to peers. See plan §"Validation: reject at
  /// apply, never store garbage" (`docs/plans/2026-05-14-group-member-ordering.md`).
  static String encodeSortStateForColumn(GroupSortState state) =>
      jsonEncode({
        'mode': state.mode.asInt,
        'order': state.manualOrder,
      });

  /// Read-path decode of the stored `sort_state` column.
  ///
  /// The mapper is the secondary belt-and-suspenders defense (the primary
  /// defense is apply-time validation in `drift_sync_adapter.dart` —
  /// see [tryDecodeSortState]). On any structural failure we fall back to
  /// [GroupSortState.manualEmpty] for display only, log a warning, and do
  /// NOT write back. A corrupt-decode therefore never propagates to peers.
  static GroupSortState _decodeSortStateForRead(
    String raw, {
    required String contextId,
  }) {
    final decoded = tryDecodeSortState(raw);
    if (decoded != null) return decoded;
    ErrorReportingService.instance.report(
      'Failed to decode sort_state JSON for member_group $contextId: '
      'raw=${_truncate(raw)}',
      severity: ErrorSeverity.warning,
    );
    return GroupSortState.manualEmpty;
  }

  static String _truncate(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}...' : s;
}
