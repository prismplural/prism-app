import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_member_matcher.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';

/// Immutable state backing the mapping screen.
class PkMappingState {
  final List<PKMember> pkMembers;
  final List<domain.Member> localMembers;

  /// Decision keyed by PK member UUID (Link / Import / Skip for a PK member).
  final Map<String, PkMappingDecision> decisionsByPkUuid;

  /// Decision keyed by local member id for locals that are NOT the target of
  /// any link decision (push-new or skip).
  final Map<String, PkMappingDecision> decisionsByLocalId;

  final bool isApplying;
  final double applyProgress;
  final List<PkApplyResult>? lastResults;
  final String? error;

  const PkMappingState({
    this.pkMembers = const [],
    this.localMembers = const [],
    this.decisionsByPkUuid = const {},
    this.decisionsByLocalId = const {},
    this.isApplying = false,
    this.applyProgress = 0.0,
    this.lastResults,
    this.error,
  });

  PkMappingState copyWith({
    List<PKMember>? pkMembers,
    List<domain.Member>? localMembers,
    Map<String, PkMappingDecision>? decisionsByPkUuid,
    Map<String, PkMappingDecision>? decisionsByLocalId,
    bool? isApplying,
    double? applyProgress,
    List<PkApplyResult>? lastResults,
    String? error,
    bool clearError = false,
    bool clearResults = false,
  }) {
    return PkMappingState(
      pkMembers: pkMembers ?? this.pkMembers,
      localMembers: localMembers ?? this.localMembers,
      decisionsByPkUuid: decisionsByPkUuid ?? this.decisionsByPkUuid,
      decisionsByLocalId: decisionsByLocalId ?? this.decisionsByLocalId,
      isApplying: isApplying ?? this.isApplying,
      applyProgress: applyProgress ?? this.applyProgress,
      lastResults: clearResults ? null : (lastResults ?? this.lastResults),
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Local member IDs currently consumed by a Link decision.
  Set<String> get linkedLocalIds {
    final ids = <String>{};
    for (final d in decisionsByPkUuid.values) {
      if (d is PkLinkDecision) ids.add(d.localMemberId);
    }
    return ids;
  }

  /// Local members that are not already linked to PK and not consumed
  /// by any current link decision — candidates for the "Local members to push"
  /// section.
  List<domain.Member> get unlinkedLocals {
    final consumed = linkedLocalIds;
    return localMembers
        .where((m) => m.pluralkitUuid == null && !consumed.contains(m.id))
        .toList();
  }
}

/// Controller for the PluralKit mapping screen.
class PkMappingController extends AsyncNotifier<PkMappingState> {
  @override
  Future<PkMappingState> build() async {
    final syncService = ref.read(pluralKitSyncServiceProvider);
    // Read-only fetch — do NOT write PK members into the local table here.
    // Writes happen later, per-decision, via the mapping applier so the user's
    // Skip/Link choices actually matter. See bug B1.
    final (_, pkMembers) = await syncService.fetchPkMembersWithoutImport();

    final memberRepo = ref.read(memberRepositoryProvider);
    final locals = (await memberRepo.getAllMembers())
        .where((m) => !m.pluralkitSyncIgnored)
        .toList();

    // Exclude already-linked locals from mapping choices entirely — they're
    // considered done.
    final unlinkedLocals = locals
        .where((m) => m.pluralkitUuid == null)
        .toList();

    final suggestions = const PkMemberMatcher().suggest(
      unlinkedLocals,
      pkMembers,
    );

    final pkDecisions = <String, PkMappingDecision>{};
    final consumedLocalIds = <String>{};
    for (final s in suggestions) {
      if (s.suggestedLocal != null &&
          (s.confidence == PkMatchConfidence.exact ||
              s.confidence == PkMatchConfidence.caseInsensitive) &&
          !consumedLocalIds.contains(s.suggestedLocal!.id)) {
        pkDecisions[s.pkMember.uuid] = PkLinkDecision(
          localMemberId: s.suggestedLocal!.id,
          pkMember: s.pkMember,
        );
        consumedLocalIds.add(s.suggestedLocal!.id);
      } else {
        pkDecisions[s.pkMember.uuid] = PkImportDecision(pkMember: s.pkMember);
      }
    }

    // Default each un-consumed unlinked local to push-new.
    final localDecisions = <String, PkMappingDecision>{};
    for (final m in unlinkedLocals) {
      if (!consumedLocalIds.contains(m.id)) {
        localDecisions[m.id] = PkPushNewDecision(localMemberId: m.id);
      }
    }

    // Nothing to decide (empty PK system and all locals already linked) —
    // acknowledge immediately so the user isn't stranded at a blank screen
    // with `needsMapping=true`.
    if (pkDecisions.isEmpty && localDecisions.isEmpty) {
      await syncService.acknowledgeMapping();
      ref.invalidate(pluralKitSyncProvider);
    }

    return PkMappingState(
      pkMembers: pkMembers,
      localMembers: locals,
      decisionsByPkUuid: pkDecisions,
      decisionsByLocalId: localDecisions,
    );
  }

  /// Update the decision for a PK member. If the decision is a Link, drop
  /// the push decision that was defaulted for that local. If the decision
  /// moves away from Link, restore the local to the push/skip pool (default
  /// to Push).
  void setPkDecision(String pkUuid, PkMappingDecision decision) {
    final current = state.value;
    if (current == null) return;

    final prior = current.decisionsByPkUuid[pkUuid];
    final newPk = Map<String, PkMappingDecision>.from(current.decisionsByPkUuid)
      ..[pkUuid] = decision;
    final newLocal = Map<String, PkMappingDecision>.from(
      current.decisionsByLocalId,
    );

    // If prior was a Link, the local was removed from newLocal. Restore it
    // with a default push decision unless it's now linked elsewhere.
    if (prior is PkLinkDecision) {
      final stillLinked = newPk.values.any(
        (d) => d is PkLinkDecision && d.localMemberId == prior.localMemberId,
      );
      if (!stillLinked) {
        newLocal[prior.localMemberId] = PkPushNewDecision(
          localMemberId: prior.localMemberId,
        );
      }
    }

    // If new decision is a Link, remove that local from the push pool.
    if (decision is PkLinkDecision) {
      newLocal.remove(decision.localMemberId);
      // Also: if any OTHER PK member was linking to this same local, that
      // conflicts — the UI should prevent this, but defensively demote the
      // loser to Skip (never silently import a new member on the user).
      for (final entry in newPk.entries.toList()) {
        if (entry.key == pkUuid) continue;
        final d = entry.value;
        if (d is PkLinkDecision && d.localMemberId == decision.localMemberId) {
          newPk[entry.key] = PkSkipDecision(pkMemberUuid: d.pkMember.uuid);
        }
      }
    }

    state = AsyncData(
      current.copyWith(decisionsByPkUuid: newPk, decisionsByLocalId: newLocal),
    );
  }

  /// Update the decision for a local member (push-new / skip).
  void setLocalDecision(String localId, PkMappingDecision decision) {
    final current = state.value;
    if (current == null) return;
    final newLocal = Map<String, PkMappingDecision>.from(
      current.decisionsByLocalId,
    )..[localId] = decision;
    state = AsyncData(current.copyWith(decisionsByLocalId: newLocal));
  }

  /// Collect all decisions and run the applier.
  Future<void> apply() async {
    final current = state.value;
    if (current == null || current.isApplying) return;

    state = AsyncData(
      current.copyWith(
        isApplying: true,
        applyProgress: 0.0,
        clearError: true,
        clearResults: true,
      ),
    );

    final syncService = ref.read(pluralKitSyncServiceProvider);
    final client = await syncService.buildClientIgnoringMappingGate();
    if (!ref.mounted) {
      client?.dispose();
      return;
    }
    if (client == null) {
      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            isApplying: false,
            error: 'Not connected to PluralKit',
          ),
        );
      }
      return;
    }

    try {
      final memberRepo = ref.read(memberRepositoryProvider);
      final db = ref.read(databaseProvider);
      final applier = PkMappingApplier(
        members: memberRepo,
        state: PkMappingStateDao(db),
        pushService: const PkPushService(),
        client: client,
      );

      // Build the full decision list — PK decisions first, then local-only.
      final decisions = <PkMappingDecision>[
        ...current.decisionsByPkUuid.values,
        ...current.decisionsByLocalId.values,
      ];

      // Apply one-by-one to emit progress.
      final results = <PkApplyResult>[];
      for (var i = 0; i < decisions.length; i++) {
        final r = await applier.apply([decisions[i]]);
        if (!ref.mounted) return;
        results.addAll(r);
        final next = state.value;
        if (next != null) {
          state = AsyncData(
            next.copyWith(applyProgress: (i + 1) / decisions.length),
          );
        }
      }

      final hasFailures = results.any(
        (r) => r.outcome == PkApplyOutcome.failed,
      );

      if (!hasFailures) {
        await syncService.acknowledgeMapping();
        if (!ref.mounted) return;

        // Phase 4 bootstrap after Apply: import PK switch history, re-
        // attribute any headless sessions against the fresh mapping, and
        // push post-linkedAt local sessions to PK. Errors here must not
        // undo the Apply itself — log and continue so the UI still flips
        // out of `needsMapping`.
        try {
          await syncService.importSwitchesAfterLink();
          if (!ref.mounted) return;
          await syncService.pushPendingSwitches();
        } catch (_) {
          // Non-fatal — surfaces on next syncRecentData via state.syncError.
        }
        if (!ref.mounted) return;

        // Refresh the PK sync provider so UI picks up the new canAutoSync.
        ref.invalidate(pluralKitSyncProvider);
      }

      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            isApplying: false,
            applyProgress: 1.0,
            lastResults: results,
          ),
        );
      }
    } catch (e, st) {
      if (!ref.mounted) return;
      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(isApplying: false, error: e.toString()),
        );
      } else {
        state = AsyncError(e, st);
      }
    } finally {
      client.dispose();
    }
  }

  /// Retry the initial build — used from the screen when `build()` errored
  /// (e.g. network failure on `importMembersOnly`).
  void retry() {
    ref.invalidateSelf();
  }

  /// Close the screen without flipping `needsMapping`. User can revisit later.
  void dismiss() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearError: true, clearResults: true));
  }
}

final pkMappingControllerProvider =
    AsyncNotifierProvider<PkMappingController, PkMappingState>(
      PkMappingController.new,
    );
