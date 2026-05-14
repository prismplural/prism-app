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

/// Sanitize a stored `sort_state` string for outbound emission.
///
/// Apply-time validation in `drift_sync_adapter.dart` prevents *new* garbage
/// from peers reaching the local column. But the column can hold pre-existing
/// corruption from before that validation landed, a manual DB edit, or
/// file-level corruption. Calling this helper before emitting protects peers
/// from re-broadcasting that corruption.
///
/// Behavior:
/// - Valid input: returns `raw` byte-for-byte unchanged (keeps merge metadata
///   stable for other-device-vs-other-device rounds).
/// - Invalid input: returns the JSON encoding of [GroupSortState.manualEmpty]
///   AND logs a warning via [ErrorReportingService].
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
  /// `member_groups.sort_state` column. Shape:
  /// `{"mode": <int>, "order": ["<entryId>", ...]}`. Always valid for local
  /// writes; remote payloads are validated separately by
  /// [tryDecodeSortState] in the adapter apply path.
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
