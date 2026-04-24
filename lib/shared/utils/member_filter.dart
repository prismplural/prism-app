import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/domain/models/member.dart';

/// Normalises [text] to a stable search key: NFKC → lowercase.
///
/// NFKC maps compatibility variants (fullwidth Latin, mathematical alphabets,
/// etc.) to their base ASCII equivalents before lowercasing, so queries like
/// "alice" match members whose names use decorative Unicode characters.
/// Stored names are never modified — only the ephemeral search key is built
/// from this function.
String _normalizeForSearch(String text) => unorm.nfkc(text).toLowerCase();

class MemberSearchIndex {
  MemberSearchIndex(List<Member> members)
    : _members = members,
      _entries = [
        for (final member in members)
          (member: member, searchKey: _searchKey(member)),
      ];

  final List<Member> _members;
  final List<({Member member, String searchKey})> _entries;

  List<Member> filter(String query) {
    if (query.isEmpty) return _members;
    final normalizedQuery = _normalizeForSearch(query);
    return [
      for (final entry in _entries)
        if (entry.searchKey.contains(normalizedQuery)) entry.member,
    ];
  }
}

/// Returns the subset of [members] whose name or pronouns match [query].
///
/// Matching is performed against NFKC-normalised, lowercased search keys so
/// that:
/// - Queries are case-insensitive.
/// - Decorative Unicode variants in names still match plain ASCII queries.
/// - Pronouns are included in the search surface when present.
///
/// An empty [query] returns [members] unchanged (no allocation).
List<Member> filterMembers(List<Member> members, String query) {
  return MemberSearchIndex(members).filter(query);
}

String _searchKey(Member member) {
  final buffer = StringBuffer(_normalizeForSearch(member.name));
  final pronouns = member.pronouns;
  if (pronouns != null && pronouns.isNotEmpty) {
    buffer.write(' ');
    buffer.write(_normalizeForSearch(pronouns));
  }
  return buffer.toString();
}
