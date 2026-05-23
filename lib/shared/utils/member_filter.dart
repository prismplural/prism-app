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
  MemberSearchIndex(
    List<Member> members, {
    Map<String, Iterable<String>> additionalSearchTermsByMemberId = const {},
  }) : _members = members,
       _entries = [
         for (final member in members)
           (
             member: member,
             searchKey: _searchKey(
               member,
               additionalSearchTermsByMemberId[member.id] ?? const [],
             ),
           ),
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

/// Returns the subset of [members] whose names or pronouns match [query].
///
/// Matching is performed against NFKC-normalised, lowercased search keys so
/// that:
/// - Queries are case-insensitive.
/// - Decorative Unicode variants in names still match plain ASCII queries.
/// - Full names are included in the search surface when present.
/// - Pronouns are included in the search surface when present.
///
/// An empty [query] returns [members] unchanged (no allocation).
List<Member> filterMembers(
  List<Member> members,
  String query, {
  Map<String, Iterable<String>> additionalSearchTermsByMemberId = const {},
}) {
  return MemberSearchIndex(
    members,
    additionalSearchTermsByMemberId: additionalSearchTermsByMemberId,
  ).filter(query);
}

String _searchKey(Member member, Iterable<String> additionalSearchTerms) {
  final buffer = StringBuffer();
  final seen = <String>{};

  void writeTerm(String? term) {
    final trimmed = term?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final normalized = _normalizeForSearch(trimmed);
    if (!seen.add(normalized)) return;
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(normalized);
  }

  writeTerm(member.name);
  writeTerm(member.displayName);
  writeTerm(member.pronouns);
  for (final term in additionalSearchTerms) {
    writeTerm(term);
  }

  return buffer.toString();
}
