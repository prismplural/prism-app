import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

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
      sortState: _decodeSortState(row.sortState, contextId: row.id),
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

  /// Best-effort decode of a stored `sort_state` JSON blob.
  ///
  /// The mapper is the secondary belt-and-suspenders defense (the primary
  /// defense is apply-time validation in `drift_sync_adapter.dart`). On any
  /// structural failure — non-JSON, non-object, missing keys, wrong types —
  /// we fall back to [GroupSortState.manualEmpty] for display only, log a
  /// warning, and do NOT write back. A corrupt-decode therefore never
  /// propagates to peers.
  ///
  /// Defensive normalizations on success: duplicate entry ids in the
  /// `order` array are deduped, preserving first occurrence.
  static GroupSortState _decodeSortState(
    String raw, {
    required String contextId,
  }) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _warnDecodeFailure(
          contextId,
          'expected JSON object, got ${decoded.runtimeType}',
        );
        return GroupSortState.manualEmpty;
      }
      if (!decoded.containsKey('mode') || !decoded.containsKey('order')) {
        _warnDecodeFailure(
          contextId,
          'missing required key(s); has=${decoded.keys.toList()}',
        );
        return GroupSortState.manualEmpty;
      }

      final rawMode = decoded['mode'];
      final mode = rawMode is int
          ? GroupSortMode.fromInt(rawMode)
          : GroupSortMode.manual;

      final rawOrder = decoded['order'];
      if (rawOrder is! List) {
        _warnDecodeFailure(
          contextId,
          'order field is not a list; got ${rawOrder.runtimeType}',
        );
        return GroupSortState.manualEmpty;
      }
      final order = <String>[];
      final seen = <String>{};
      for (final item in rawOrder) {
        if (item is! String) {
          _warnDecodeFailure(
            contextId,
            'order contains non-string element; got ${item.runtimeType}',
          );
          return GroupSortState.manualEmpty;
        }
        if (seen.add(item)) {
          order.add(item);
        }
      }

      return GroupSortState(mode: mode, manualOrder: order);
    } catch (e) {
      _warnDecodeFailure(contextId, 'jsonDecode threw: $e');
      return GroupSortState.manualEmpty;
    }
  }

  static void _warnDecodeFailure(String contextId, String detail) {
    ErrorReportingService.instance.report(
      'Failed to decode sort_state JSON for member_group $contextId: $detail',
      severity: ErrorSeverity.warning,
    );
  }
}
