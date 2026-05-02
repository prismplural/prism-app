import 'dart:convert';

/// PluralKit-style proxy tag (prefix and/or suffix wrapping a message).
///
/// Stored on [Member.proxyTagsJson] and used by chat's proxy-tag authoring.
/// Tags can come from PluralKit sync or be edited locally in Prism. Prism does
/// not push local tag edits back to PluralKit. Either side may be null, but at
/// least one must be non-empty — see [isEmpty].
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

/// Encode proxy tags back to PK-compatible JSON.
///
/// Empty tags are filtered. Empty prefix/suffix fields are encoded as null so
/// the stored shape matches PluralKit's `[{ "prefix": "...", "suffix": null }]`
/// convention.
String? encodeProxyTags(
  Iterable<ProxyTag> tags, {
  bool emptyAsJsonList = false,
}) {
  final normalized = <Map<String, String?>>[];
  for (final tag in tags) {
    final prefix = tag.prefix?.isEmpty ?? true ? null : tag.prefix;
    final suffix = tag.suffix?.isEmpty ?? true ? null : tag.suffix;
    final normalizedTag = ProxyTag(prefix: prefix, suffix: suffix);
    if (normalizedTag.isEmpty) continue;
    normalized.add({'prefix': prefix, 'suffix': suffix});
  }
  if (normalized.isEmpty) return emptyAsJsonList ? '[]' : null;
  return jsonEncode(normalized);
}
