import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/domain/models/note.dart';

/// Sentinel used to represent "notes with no member assigned" in the filter.
const String filterNoMemberId = '__filter_no_member__';

/// Filters [notes] by [query] (searches title + body) and/or [filterMemberId]
/// (matches note.memberId exactly).
///
/// [query] is trimmed, NFKC-normalized, case-insensitive, and must be at least
/// 2 non-whitespace characters to apply. Shorter or whitespace-only queries
/// pass through unchanged.
///
/// [filterMemberId] semantics:
///   - `null` = no member filter (show all)
///   - [filterNoMemberId] = show only notes with `memberId == null`
///   - Any other string = show only notes with `memberId == filterMemberId`
///
/// Both filters use AND logic: a note must satisfy BOTH to pass.
List<Note> filterNotes(
  List<Note> notes, {
  String? query,
  String? filterMemberId,
}) {
  var result = notes;

  if (filterMemberId != null) {
    if (filterMemberId == filterNoMemberId) {
      result = result.where((n) => n.memberId == null).toList(growable: false);
    } else {
      result =
          result.where((n) => n.memberId == filterMemberId).toList(growable: false);
    }
  }

  if (query != null) {
    final trimmed = query.trim();
    if (trimmed.length >= 2) {
      final normalizedQuery = unorm.nfkc(trimmed).toLowerCase();
      result = result.where((n) {
        final title = unorm.nfkc(n.title).toLowerCase();
        final body = unorm.nfkc(n.body).toLowerCase();
        return title.contains(normalizedQuery) || body.contains(normalizedQuery);
      }).toList(growable: false);
    }
  }

  return result;
}
