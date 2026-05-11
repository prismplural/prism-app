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

enum SpMemberMatchConfidence { persistedMapping, pluralKitId, exactName, none }

class SpMemberMatchSuggestion {
  const SpMemberMatchSuggestion({
    required this.spMember,
    required this.confidence,
    this.suggestedLocal,
  });

  final SpMember spMember;
  final Member? suggestedLocal;
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
    for (final local in localsById.values) {
      final pkId = _trimmedOrNull(local.pluralkitId);
      if (pkId != null) {
        localPkCounts[pkId] = (localPkCounts[pkId] ?? 0) + 1;
        localsByPkId.putIfAbsent(pkId, () => local);
      }

      final name = normalizedSpMemberName(local.name);
      if (name != null) {
        localNameCounts[name] = (localNameCounts[name] ?? 0) + 1;
        localsByName.putIfAbsent(name, () => local);
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

      suggestions.add(
        SpMemberMatchSuggestion(
          spMember: member,
          confidence: SpMemberMatchConfidence.none,
        ),
      );
    }

    return suggestions;
  }
}

String? normalizedSpMemberName(String name) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
