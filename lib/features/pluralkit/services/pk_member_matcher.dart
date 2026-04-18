import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

enum PkMatchConfidence { exact, caseInsensitive, none }

class PkMatchSuggestion {
  final PKMember pkMember;
  final Member? suggestedLocal;
  final PkMatchConfidence confidence;

  const PkMatchSuggestion({
    required this.pkMember,
    required this.suggestedLocal,
    required this.confidence,
  });
}

class PkMemberMatcher {
  const PkMemberMatcher();

  /// Suggest a local member match for each PK member.
  ///
  /// Confidence:
  /// - `exact`: names match exactly (after trim), unique on both sides
  /// - `caseInsensitive`: names match case-insensitively (after trim), unique on both sides
  /// - `none`: no match, or ambiguous (multiple candidates on either side)
  ///
  /// Members already linked (have non-null `pluralkitUuid`) are excluded from
  /// candidacy — they're considered already-mapped.
  List<PkMatchSuggestion> suggest(
    List<Member> locals,
    List<PKMember> pkMembers,
  ) {
    final unlinkedLocals = locals
        .where((m) => m.pluralkitUuid == null && !m.pluralkitSyncIgnored)
        .toList();

    final localsByExactName = <String, List<Member>>{};
    final localsByLowerName = <String, List<Member>>{};
    for (final local in unlinkedLocals) {
      final trimmed = local.name.trim();
      localsByExactName.putIfAbsent(trimmed, () => []).add(local);
      localsByLowerName
          .putIfAbsent(trimmed.toLowerCase(), () => [])
          .add(local);
    }

    final pkByExactName = <String, int>{};
    final pkByLowerName = <String, int>{};
    for (final pk in pkMembers) {
      final trimmed = pk.name.trim();
      pkByExactName.update(trimmed, (v) => v + 1, ifAbsent: () => 1);
      pkByLowerName.update(
        trimmed.toLowerCase(),
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }

    final suggestions = <PkMatchSuggestion>[];
    for (final pk in pkMembers) {
      final trimmed = pk.name.trim();
      final lower = trimmed.toLowerCase();

      // Ambiguous on PK side → force user choice.
      if ((pkByExactName[trimmed] ?? 0) > 1 ||
          (pkByLowerName[lower] ?? 0) > 1) {
        suggestions.add(PkMatchSuggestion(
          pkMember: pk,
          suggestedLocal: null,
          confidence: PkMatchConfidence.none,
        ));
        continue;
      }

      final exactMatches = localsByExactName[trimmed] ?? const [];
      if (exactMatches.length == 1) {
        suggestions.add(PkMatchSuggestion(
          pkMember: pk,
          suggestedLocal: exactMatches.first,
          confidence: PkMatchConfidence.exact,
        ));
        continue;
      }
      if (exactMatches.length > 1) {
        suggestions.add(PkMatchSuggestion(
          pkMember: pk,
          suggestedLocal: null,
          confidence: PkMatchConfidence.none,
        ));
        continue;
      }

      final ciMatches = localsByLowerName[lower] ?? const [];
      if (ciMatches.length == 1) {
        suggestions.add(PkMatchSuggestion(
          pkMember: pk,
          suggestedLocal: ciMatches.first,
          confidence: PkMatchConfidence.caseInsensitive,
        ));
        continue;
      }
      if (ciMatches.length > 1) {
        suggestions.add(PkMatchSuggestion(
          pkMember: pk,
          suggestedLocal: null,
          confidence: PkMatchConfidence.none,
        ));
        continue;
      }

      suggestions.add(PkMatchSuggestion(
        pkMember: pk,
        suggestedLocal: null,
        confidence: PkMatchConfidence.none,
      ));
    }

    return suggestions;
  }
}
