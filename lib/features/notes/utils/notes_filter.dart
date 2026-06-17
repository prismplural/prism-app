import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';

/// Sentinel for filtering notes that have no member assigned.
const String filterNoMemberId = '__filter_no_member__';

/// Client-side note filter. AND logic when both [query] and [filterMemberIds]
/// are active. [query] trims, NFKC-normalises, and skips when < 2 chars.
List<Note> filterNotes(
  List<Note> notes, {
  String? query,
  Set<String> filterMemberIds = const {},
  Map<String, String> memberNameMap = const {},
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
            final searchableText = _searchableNoteText(n, memberNameMap);
            final normalizedText = unorm.nfkc(searchableText).toLowerCase();
            return normalizedText.contains(normalizedQuery);
          })
          .toList(growable: false);
    }
  }

  return result;
}

String _searchableNoteText(Note note, Map<String, String> memberNameMap) {
  final rawText = '${note.title}\n${note.body}';
  if (!containsMemberMention(rawText)) return rawText;
  return '$rawText\n${replaceMemberMentionsWithNames(rawText, memberNameMap)}';
}
