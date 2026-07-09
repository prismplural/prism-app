import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

sealed class SpMemberMappingDecision {
  const SpMemberMappingDecision({required this.spMemberId});

  final String spMemberId;
}

class SpLinkMemberDecision extends SpMemberMappingDecision {
  const SpLinkMemberDecision({
    required super.spMemberId,
    required this.localMemberId,
  });

  final String localMemberId;
}

class SpImportMemberDecision extends SpMemberMappingDecision {
  const SpImportMemberDecision({required super.spMemberId});
}

enum SpMemberMatchConfidence {
  persistedMapping,
  pluralKitId,
  exactName,
  ambiguous,
  none,
}

class SpMemberMatchSuggestion {
  const SpMemberMatchSuggestion({
    required this.spMember,
    required this.confidence,
    this.suggestedLocal,
    this.candidates = const [],
  });

  final SpMember spMember;
  final Member? suggestedLocal;

  /// Populated for [SpMemberMatchConfidence.ambiguous]: local members the SP
  /// member could be, but which the 1:1 gates couldn't pick between.
  final List<Member> candidates;
  final SpMemberMatchConfidence confidence;
}

class SpMemberMatcher {
  const SpMemberMatcher();

  List<SpMemberMatchSuggestion> suggest({
    required List<SpMember> spMembers,
    required List<Member> localMembers,
    Map<String, String> persistedMemberMappings = const {},
  }) {
    final localsById = {
      for (final local in localMembers)
        if (local.id != unknownSentinelMemberId && !local.isDeleted)
          local.id: local,
    };

    final exportedIds = {for (final member in spMembers) member.id};
    final persistedTargetCounts = <String, int>{};
    for (final entry in persistedMemberMappings.entries) {
      if (!exportedIds.contains(entry.key) ||
          !localsById.containsKey(entry.value)) {
        continue;
      }
      persistedTargetCounts[entry.value] =
          (persistedTargetCounts[entry.value] ?? 0) + 1;
    }

    final spPkCounts = <String, int>{};
    for (final member in spMembers) {
      final pkId = _trimmedOrNull(member.pkId);
      if (pkId != null) spPkCounts[pkId] = (spPkCounts[pkId] ?? 0) + 1;
    }

    final localsByPkId = <String, Member>{};
    final localPkCounts = <String, int>{};
    final localsByName = <String, Member>{};
    final localNameCounts = <String, int>{};
    // Every local per key, not just the first, so a failed 1:1 gate can still
    // list the members the SP row might be.
    final localsByPkIdAll = <String, List<Member>>{};
    final localsByNameAll = <String, List<Member>>{};
    for (final local in localsById.values) {
      final pkId = _trimmedOrNull(local.pluralkitId);
      if (pkId != null) {
        localPkCounts[pkId] = (localPkCounts[pkId] ?? 0) + 1;
        localsByPkId.putIfAbsent(pkId, () => local);
        (localsByPkIdAll[pkId] ??= <Member>[]).add(local);
      }

      final name = normalizedSpMemberName(local.name);
      if (name != null) {
        localNameCounts[name] = (localNameCounts[name] ?? 0) + 1;
        localsByName.putIfAbsent(name, () => local);
        (localsByNameAll[name] ??= <Member>[]).add(local);
      }
    }

    final spNameCounts = <String, int>{};
    for (final member in spMembers) {
      final name = normalizedSpMemberName(member.name);
      if (name != null) spNameCounts[name] = (spNameCounts[name] ?? 0) + 1;
    }

    final consumedLocalIds = <String>{};
    final suggestions = <SpMemberMatchSuggestion>[];

    for (final member in spMembers) {
      final persistedLocalId = persistedMemberMappings[member.id];
      if (persistedLocalId != null &&
          persistedTargetCounts[persistedLocalId] == 1 &&
          !consumedLocalIds.contains(persistedLocalId)) {
        final local = localsById[persistedLocalId];
        if (local != null) {
          consumedLocalIds.add(local.id);
          suggestions.add(
            SpMemberMatchSuggestion(
              spMember: member,
              suggestedLocal: local,
              confidence: SpMemberMatchConfidence.persistedMapping,
            ),
          );
          continue;
        }
      }

      final pkId = _trimmedOrNull(member.pkId);
      if (pkId != null && spPkCounts[pkId] == 1 && localPkCounts[pkId] == 1) {
        final local = localsByPkId[pkId];
        if (local != null && !consumedLocalIds.contains(local.id)) {
          consumedLocalIds.add(local.id);
          suggestions.add(
            SpMemberMatchSuggestion(
              spMember: member,
              suggestedLocal: local,
              confidence: SpMemberMatchConfidence.pluralKitId,
            ),
          );
          continue;
        }
      }

      final normalizedName = normalizedSpMemberName(member.name);
      if (normalizedName != null &&
          spNameCounts[normalizedName] == 1 &&
          localNameCounts[normalizedName] == 1) {
        final local = localsByName[normalizedName];
        if (local != null && !consumedLocalIds.contains(local.id)) {
          consumedLocalIds.add(local.id);
          suggestions.add(
            SpMemberMatchSuggestion(
              spMember: member,
              suggestedLocal: local,
              confidence: SpMemberMatchConfidence.exactName,
            ),
          );
          continue;
        }
      }

      // Failed every 1:1 gate but still has local matches → ambiguous, not
      // new. Surfacing the candidates lets the user link it instead of
      // minting a shadow duplicate that steals the SP row's custom fields.
      final candidates = _ambiguousCandidates(
        pkId: pkId,
        normalizedName: normalizedName,
        localsByPkIdAll: localsByPkIdAll,
        localsByNameAll: localsByNameAll,
        consumedLocalIds: consumedLocalIds,
      );
      suggestions.add(
        SpMemberMatchSuggestion(
          spMember: member,
          confidence: candidates.isEmpty
              ? SpMemberMatchConfidence.none
              : SpMemberMatchConfidence.ambiguous,
          candidates: candidates,
        ),
      );
    }

    return suggestions;
  }
}

List<Member> _ambiguousCandidates({
  required String? pkId,
  required String? normalizedName,
  required Map<String, List<Member>> localsByPkIdAll,
  required Map<String, List<Member>> localsByNameAll,
  required Set<String> consumedLocalIds,
}) {
  final seen = <String>{};
  final candidates = <Member>[];
  void addAll(Iterable<Member>? locals) {
    if (locals == null) return;
    for (final local in locals) {
      if (consumedLocalIds.contains(local.id)) continue;
      if (seen.add(local.id)) candidates.add(local);
    }
  }

  if (pkId != null) addAll(localsByPkIdAll[pkId]);
  if (normalizedName != null) addAll(localsByNameAll[normalizedName]);
  return candidates;
}

String? normalizedSpMemberName(String name) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
