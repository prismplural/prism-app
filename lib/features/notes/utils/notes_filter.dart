import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/domain/models/note.dart';

/// Sentinel for filtering notes that have no member assigned.
const String filterNoMemberId = '__filter_no_member__';

/// Client-side note filter. AND logic when both [query] and [filterMemberIds]
/// are active. [query] trims, NFKC-normalises, and skips when < 2 chars.
List<Note> filterNotes(
  List<Note> notes, {
  String? query,
  Set<String> filterMemberIds = const {},
}) {
  var result = notes;

  if (filterMemberIds.isNotEmpty) {
    result = result
        .where((note) {
          final memberId = note.memberId;
          if (memberId == null) {
            return filterMemberIds.contains(filterNoMemberId);
          }
          return filterMemberIds.contains(memberId);
        })
        .toList(growable: false);
  }

  if (query != null) {
    final trimmed = query.trim();
    if (trimmed.length >= 2) {
      final normalizedQuery = unorm.nfkc(trimmed).toLowerCase();
      result = result
          .where((n) {
            final title = unorm.nfkc(n.title).toLowerCase();
            final body = unorm.nfkc(n.body).toLowerCase();
            return title.contains(normalizedQuery) ||
                body.contains(normalizedQuery);
          })
          .toList(growable: false);
    }
  }

  return result;
}
