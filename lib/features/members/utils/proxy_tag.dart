import 'dart:convert';

/// PluralKit-style proxy tag (prefix and/or suffix wrapping a message).
///
/// Pulled from PK on sync and stored verbatim on [Member.proxyTagsJson]; Prism
/// does not push edits back. Either side may be null, but at least one must be
/// non-empty — see [isEmpty].
class ProxyTag {
  const ProxyTag({this.prefix, this.suffix});

  final String? prefix;
  final String? suffix;

  /// True when both sides are null or the empty string. Empty tags are
  /// filtered out by [parseProxyTags]; otherwise they would match every draft.
  bool get isEmpty =>
      (prefix == null || prefix!.isEmpty) &&
      (suffix == null || suffix!.isEmpty);
}

/// Parse `Member.proxyTagsJson` into a list of [ProxyTag]s.
///
/// Returns an empty list for null/empty input, malformed JSON, or non-list
/// top-level JSON. Silently skips individual entries that aren't JSON objects
/// or whose prefix+suffix are both empty.
List<ProxyTag> parseProxyTags(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final result = <ProxyTag>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      try {
        final tag = ProxyTag(
          prefix: e['prefix'] as String?,
          suffix: e['suffix'] as String?,
        );
        if (!tag.isEmpty) result.add(tag);
      } catch (_) {
        // Skip malformed entry but continue parsing the rest.
      }
    }
    return result;
  } catch (_) {
    return const [];
  }
}
