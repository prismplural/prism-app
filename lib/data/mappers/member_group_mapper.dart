import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

/// Strict decode of a stored or wire `sort_state` JSON blob. Returns `null`
/// on any structural failure. Wrong-type `mode` (string, null, bool, double)
/// is rejected; unknown `mode` ints fall back to [GroupSortMode.manual] via
/// [GroupSortMode.fromInt] (forward-compat). `order` is deduped, first
/// occurrence wins.
GroupSortState? tryDecodeSortState(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    if (!decoded.containsKey('mode') || !decoded.containsKey('order')) {
      return null;
    }

    // Strict: mode must be an int. Wrong-type (string "nameAsc", null,
    // bool, double 1.5) is garbage — reject. Unknown int (99) is
    // forward-compat — resolve to manual via GroupSortMode.fromInt.
    final rawMode = decoded['mode'];
    if (rawMode is! int) return null;
    final mode = GroupSortMode.fromInt(rawMode);

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

/// Sanitize a stored `sort_state` string for outbound emission. Valid input
/// passes through byte-for-byte (keeps peer merge metadata stable); invalid
/// input is replaced with the JSON encoding of [GroupSortState.manualEmpty]
/// and a warning logged. Defends against a locally-corrupt column (manual DB
/// edit, file corruption, or row written before apply-time validation
/// landed) re-broadcasting garbage to peers.
String sanitizeSortStateForEmission(String raw, {String? contextId}) {
  if (tryDecodeSortState(raw) != null) return raw;
  ErrorReportingService.instance.report(
    'Refusing to emit corrupt sort_state for member_group '
    '${contextId ?? '<unknown>'}: raw=${_truncateForLog(raw)}; '
    'substituting manualEmpty',
    severity: ErrorSeverity.warning,
  );
  return MemberGroupMapper.encodeSortStateForColumn(
    GroupSortState.manualEmpty,
  );
}

String _truncateForLog(String s) =>
    s.length > 120 ? '${s.substring(0, 120)}...' : s;

class MemberGroupMapper {
  MemberGroupMapper._();

  static domain.MemberGroup toDomain(MemberGroupRow row) {
    return domain.MemberGroup(
      id: row.id,
      name: row.name,
      description: row.description,
      colorHex: row.colorHex,
      emoji: row.emoji,
      avatarImageData: row.avatarImageData,
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
      avatarImageData: Value(model.avatarImageData),
      displayOrder: Value(model.displayOrder),
      parentGroupId: Value(model.parentGroupId),
      groupType: Value(model.groupType),
      filterRules: Value(model.filterRules),
      createdAt: Value(model.createdAt),
      sortState: Value(encodeSortStateForColumn(model.sortState)),
    );
  }

  /// JSON-encode for the `sort_state` column: `{"mode": <int>, "order": [...]}`.
  static String encodeSortStateForColumn(GroupSortState state) =>
      jsonEncode({
        'mode': state.mode.asInt,
        'order': state.manualOrder,
      });

  /// Read-path fallback: on decode failure, returns [GroupSortState.manualEmpty]
  /// for display + warn log; never writes back, so corrupt rows can't
  /// propagate. Apply-time validation in the sync adapter is the primary
  /// defense.
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
