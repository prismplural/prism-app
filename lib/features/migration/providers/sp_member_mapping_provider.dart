import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/migration/services/sp_member_mapping.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

class SpMemberMappingState {
  const SpMemberMappingState({
    this.localMembers = const [],
    this.suggestions = const [],
    this.decisions = const {},
    this.exportIdentity,
  });

  final List<Member> localMembers;
  final List<SpMemberMatchSuggestion> suggestions;
  final Map<String, SpMemberMappingDecision> decisions;
  final String? exportIdentity;

  SpMemberMappingState copyWith({
    List<Member>? localMembers,
    List<SpMemberMatchSuggestion>? suggestions,
    Map<String, SpMemberMappingDecision>? decisions,
    String? exportIdentity,
  }) {
    return SpMemberMappingState(
      localMembers: localMembers ?? this.localMembers,
      suggestions: suggestions ?? this.suggestions,
      decisions: decisions ?? this.decisions,
      exportIdentity: exportIdentity ?? this.exportIdentity,
    );
  }
}

class SpMemberMappingNotifier extends Notifier<SpMemberMappingState> {
  @override
  SpMemberMappingState build() => const SpMemberMappingState();

  Future<void> seedFromExport(SpExportData data) async {
    final identity = _identityFor(data);
    if (identity == state.exportIdentity && state.decisions.isNotEmpty) {
      return;
    }

    final localMembers =
        (await ref.read(memberRepositoryProvider).getAllMembers())
            .where(
              (member) =>
                  member.id != unknownSentinelMemberId && !member.isDeleted,
            )
            .toList(growable: false);
    final persisted = await _loadPersistedMemberMappings(data);
    final suggestions = const SpMemberMatcher().suggest(
      spMembers: data.members,
      localMembers: localMembers,
      persistedMemberMappings: persisted,
    );

    final decisions = <String, SpMemberMappingDecision>{};
    for (final suggestion in suggestions) {
      final local = suggestion.suggestedLocal;
      if (local != null) {
        decisions[suggestion.spMember.id] = SpLinkMemberDecision(
          spMemberId: suggestion.spMember.id,
          localMemberId: local.id,
        );
      } else {
        decisions[suggestion.spMember.id] = SpImportMemberDecision(
          spMemberId: suggestion.spMember.id,
        );
      }
    }

    state = SpMemberMappingState(
      localMembers: localMembers,
      suggestions: suggestions,
      decisions: decisions,
      exportIdentity: identity,
    );
  }

  void setDecision(String spMemberId, SpMemberMappingDecision decision) {
    final next = Map<String, SpMemberMappingDecision>.from(state.decisions)
      ..[spMemberId] = decision;

    if (decision is SpLinkMemberDecision) {
      for (final entry in next.entries.toList()) {
        if (entry.key == spMemberId) continue;
        final other = entry.value;
        if (other is SpLinkMemberDecision &&
            other.localMemberId == decision.localMemberId) {
          next[entry.key] = SpImportMemberDecision(spMemberId: entry.key);
        }
      }
    }

    state = state.copyWith(decisions: next);
  }

  Future<void> resetToDefaults(SpExportData data) async {
    state = state.copyWith(exportIdentity: null, decisions: const {});
    await seedFromExport(data);
  }

  void clear() {
    state = const SpMemberMappingState();
  }

  String _identityFor(SpExportData data) {
    final sortedMembers = [...data.members]
      ..sort((a, b) => a.id.compareTo(b.id));
    final payload = <String, Object?>{
      'sys': data.systemId ?? data.systemName,
      'members': [
        for (final member in sortedMembers)
          {'id': member.id, 'name': member.name, 'pkId': member.pkId},
      ],
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  Future<Map<String, String>> _loadPersistedMemberMappings(
    SpExportData data,
  ) async {
    final exportedIds = {for (final member in data.members) member.id};
    final rows = await ref.read(databaseProvider).spImportDao.getAllMappings();
    return {
      for (final row in rows)
        if (row.entityType == 'member' && exportedIds.contains(row.spId))
          row.spId: row.prismId,
    };
  }
}

final _spMemberMappingStateProvider =
    NotifierProvider<SpMemberMappingNotifier, SpMemberMappingState>(
      SpMemberMappingNotifier.new,
    );

final spMemberMappingProvider = Provider<SpMemberMappingState>((ref) {
  return ref.watch(_spMemberMappingStateProvider);
});

final spMemberMappingDecisionsProvider =
    Provider<Map<String, SpMemberMappingDecision>>((ref) {
      return ref.watch(_spMemberMappingStateProvider).decisions;
    });

final spMemberMappingControllerProvider = Provider<SpMemberMappingNotifier>((
  ref,
) {
  return ref.read(_spMemberMappingStateProvider.notifier);
});
