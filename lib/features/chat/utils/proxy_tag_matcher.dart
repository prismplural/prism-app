import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';

/// Result of matching a draft against a member's PluralKit proxy tags.
class ProxyTagMatch {
  const ProxyTagMatch({
    required this.memberId,
    required this.strippedText,
    required this.matchedPrefix,
    required this.matchedSuffix,
  });

  final String memberId;

  /// Draft text with the matched prefix/suffix removed and trimmed.
  final String strippedText;

  /// Prefix that matched, or '' if the tag had no prefix.
  final String matchedPrefix;

  /// Suffix that matched, or '' if the tag had no suffix.
  final String matchedSuffix;
}

class _Candidate {
  _Candidate({
    required this.member,
    required this.tagIndex,
    required this.prefix,
    required this.suffix,
    required this.strippedText,
  });

  final Member member;
  final int tagIndex;
  final String prefix;
  final String suffix;
  final String strippedText;

  int get score => prefix.length + suffix.length;
}

/// Match the raw draft text against every active, non-deleted member's
/// PluralKit proxy tags.
///
/// Matching is **case-sensitive** (PluralKit's default). Suffix checks run
/// against `text.trimRight()` so accidental trailing whitespace does not
/// disqualify a match. Returns the highest-scoring match (by total tag
/// length), with deterministic tie-breaking on `displayOrder`, `id`, then
/// original tag index. The stripped content may be empty — e.g. when the
/// user has typed just the prefix — so the "Posting as …" banner can appear
/// as soon as the tag is typed; the send path is responsible for blocking
/// empty sends.
ProxyTagMatch? matchProxyTag(String rawText, List<Member> members) {
  if (rawText.isEmpty) return null;
  final trimmedRight = rawText.trimRight();
  if (trimmedRight.isEmpty) return null;

  final candidates = <_Candidate>[];

  for (final member in members) {
    if (member.isDeleted || !member.isActive) continue;
    if (member.proxyTagsJson == null) continue;

    final tags = parseProxyTags(member.proxyTagsJson);
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      final prefix = tag.prefix ?? '';
      final suffix = tag.suffix ?? '';

      // parseProxyTags already filters empty tags, but guard defensively.
      if (prefix.isEmpty && suffix.isEmpty) continue;

      String? stripped;
      if (prefix.isNotEmpty && suffix.isNotEmpty) {
        // Length guard: strips would overlap on short inputs.
        if (prefix.length + suffix.length > trimmedRight.length) continue;
        if (!rawText.startsWith(prefix)) continue;
        if (!trimmedRight.endsWith(suffix)) continue;
        stripped = trimmedRight.substring(
          prefix.length,
          trimmedRight.length - suffix.length,
        );
      } else if (prefix.isNotEmpty) {
        if (!rawText.startsWith(prefix)) continue;
        stripped = rawText.substring(prefix.length);
      } else {
        if (!trimmedRight.endsWith(suffix)) continue;
        stripped = trimmedRight.substring(
          0,
          trimmedRight.length - suffix.length,
        );
      }

      candidates.add(_Candidate(
        member: member,
        tagIndex: i,
        prefix: prefix,
        suffix: suffix,
        strippedText: stripped.trim(),
      ));
    }
  }

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byOrder = a.member.displayOrder.compareTo(b.member.displayOrder);
    if (byOrder != 0) return byOrder;
    final byId = a.member.id.compareTo(b.member.id);
    if (byId != 0) return byId;
    return a.tagIndex.compareTo(b.tagIndex);
  });

  final best = candidates.first;
  return ProxyTagMatch(
    memberId: best.member.id,
    strippedText: best.strippedText,
    matchedPrefix: best.prefix,
    matchedSuffix: best.suffix,
  );
}
