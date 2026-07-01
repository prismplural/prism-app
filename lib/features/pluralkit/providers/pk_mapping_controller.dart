import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/fronting_reminder_reanchor.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unmapped_fronters_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_member_matcher.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_prefs_keys.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';

/// English fallback shown when [PkMappingController.apply] is called without a
/// localized [PkMappingController.apply.offlineErrorMessage]. Existing tests
/// call `apply()` with no args; this keeps them compiling and asserts a stable
/// string they can match against.
const _defaultOfflineErrorMessage =
    "Couldn't reach PluralKit. Check your internet connection and try again.";
const _overrideSwitchPushFailedMessage =
    "Couldn't push the chosen fronter set to PluralKit. Check your internet "
    'connection and try again.';

class _PendingFronterResolutionPush {
  _PendingFronterResolutionPush({
    required this.chosenLocalMemberIds,
    required this.switchEntry,
  });

  final Set<String> chosenLocalMemberIds;
  final PKSwitch switchEntry;
  bool cursorAdvanced = false;

  bool matches(Set<String> chosen) =>
      chosenLocalMemberIds.length == chosen.length &&
      chosenLocalMemberIds.containsAll(chosen);
}

// ---------------------------------------------------------------------------
// Outcome type
// ---------------------------------------------------------------------------

/// Sealed outcome returned by [PkMappingController.apply].
///
/// The mapping screen inspects this value to decide whether to navigate back
/// immediately ([PkMappingApplyOutcomeApplied]), show the "Who's fronting?"
/// resolution sheet ([PkMappingApplyOutcomeNeedsFronterResolution]), or surface
/// an error ([PkMappingApplyOutcomeFailed]).
///
/// Named `PkMappingApplyOutcome` rather than `PkApplyOutcome` to avoid
/// collision with the existing `enum PkApplyOutcome` in `pk_mapping_applier.dart`.
sealed class PkMappingApplyOutcome {
  const PkMappingApplyOutcome();
}

/// Returned when all decisions succeeded and active fronter sets agreed (or
/// disagreement was not actionable in the current direction). The post-apply
/// bootstrap has already run.
class PkMappingApplyOutcomeApplied extends PkMappingApplyOutcome {
  const PkMappingApplyOutcomeApplied();
}

/// Returned when decisions succeeded but the local and PK active fronter sets
/// disagree AND the chosen direction can act on the difference. The post-apply
/// bootstrap has NOT yet run — it is deferred until the user resolves the
/// conflict via [PkMappingController.applyFronterResolution] or defers it via
/// [PkMappingController.deferBootstrap].
class PkMappingApplyOutcomeNeedsFronterResolution
    extends PkMappingApplyOutcome {
  /// Local Prism member IDs of active (non-sleep) sessions.
  final Set<String> localFronterMemberIds;

  /// PK members projected to local member IDs via the just-applied mapping
  /// decisions. PK members with no mapping decision are excluded (unmapped
  /// fronter notice handles them separately).
  final Set<String> pkFronterMemberIds;

  final PkSyncDirection direction;
  final PkSyncMode mode;

  /// Raw PK switch, passed through so T9 can use it without a second network
  /// call (cache pass-through — see spec "liveFrontsOnly mode" section).
  final PKSwitch pkCurrentSwitch;

  const PkMappingApplyOutcomeNeedsFronterResolution({
    required this.localFronterMemberIds,
    required this.pkFronterMemberIds,
    required this.direction,
    required this.mode,
    required this.pkCurrentSwitch,
  });
}

/// Returned when one or more per-decision applier calls produced a failure.
/// [PkMappingController.acknowledgeMapping] was NOT called; `needsMapping`
/// remains true.
class PkMappingApplyOutcomeFailed extends PkMappingApplyOutcome {
  final List<PkApplyResult> failures;
  const PkMappingApplyOutcomeFailed(this.failures);
}

// ---------------------------------------------------------------------------
// Phase enum + state
// ---------------------------------------------------------------------------

/// Phase tracker for the mapping screen's Apply pipeline.
///
/// The Apply button stays disabled across all phases. The accompanying
/// status text widget (rendered above the button) communicates which phase the
/// pipeline is in. The button label itself stays stable while the adjacent
/// status text communicates progress through the pipeline.
enum PkMappingPhase {
  /// The per-decision loop is running — applier handles link/import/push/skip
  /// for each row.
  applyingDecisions,

  /// Post-decisions: the user-selected fronter resolution is being applied
  /// locally and, when direction permits, pushed to PK.
  resolvingFronters,

  /// Post-decisions: PK switch history is being walked and imported via the
  /// diff sweep.
  importingSwitches,

  /// Post-decisions: pending local switch updates are being pushed to PK.
  pushingSwitches,
}

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

  /// Which phase of the Apply pipeline is currently running. Defaults to
  /// [PkMappingPhase.applyingDecisions] so the screen behaves identically to
  /// the pre-Phase-3 build before [apply] is called.
  final PkMappingPhase phase;

  /// Optional human-readable status shown above the Apply button while
  /// [isApplying] is true. `null` outside Apply or during the per-decision
  /// loop (the existing percent-based label already covers that phase).
  final String? statusText;

  /// PK member UUIDs returned by the most recent fetch. Used together with
  /// [fetchedPkIds] by [hasResolvablePluralKitLink] to decide whether a
  /// local's stored `pluralkitUuid` / `pluralkitId` resolves against the
  /// currently-paired PK system.
  final Set<String> fetchedPkUuids;

  /// PK member short IDs returned by the most recent fetch. Companion to
  /// [fetchedPkUuids].
  final Set<String> fetchedPkIds;

  const PkMappingState({
    this.pkMembers = const [],
    this.localMembers = const [],
    this.decisionsByPkUuid = const {},
    this.decisionsByLocalId = const {},
    this.isApplying = false,
    this.applyProgress = 0.0,
    this.lastResults,
    this.error,
    this.phase = PkMappingPhase.applyingDecisions,
    this.statusText,
    this.fetchedPkUuids = const {},
    this.fetchedPkIds = const {},
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
    PkMappingPhase? phase,
    String? statusText,
    Set<String>? fetchedPkUuids,
    Set<String>? fetchedPkIds,
    bool clearError = false,
    bool clearResults = false,
    bool clearStatusText = false,
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
      phase: phase ?? this.phase,
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
      fetchedPkUuids: fetchedPkUuids ?? this.fetchedPkUuids,
      fetchedPkIds: fetchedPkIds ?? this.fetchedPkIds,
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

  /// Local members that don't currently resolve against the PK fetch and
  /// aren't already consumed by a Link decision — candidates for the
  /// "Local members to push" section. Includes both truly-unlinked locals
  /// (no PK fields) and unresolved-link locals (PK fields set but pointing
  /// at a member not in the current PK system).
  List<domain.Member> get unlinkedLocals {
    final consumed = linkedLocalIds;
    return localMembers
        .where(
          (m) =>
              !hasResolvablePluralKitLink(
                m,
                fetchedPkUuids: fetchedPkUuids,
                fetchedPkIds: fetchedPkIds,
              ) &&
              !consumed.contains(m.id),
        )
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Controller for the PluralKit mapping screen.
class PkMappingController extends AsyncNotifier<PkMappingState> {
  _PendingFronterResolutionPush? _pendingFronterResolutionPush;

  @override
  Future<PkMappingState> build() async {
    final syncService = ref.read(pluralKitSyncServiceProvider);
    // Read-only fetch — do NOT write PK members into the local table here.
    // Writes happen later, per-decision, via the mapping applier so the user's
    // Skip/Link choices actually matter. See bug B1.
    final (_, pkMembers) = await syncService.fetchPkMembersWithoutImport();

    final memberRepo = ref.read(memberRepositoryProvider);
    final allLocals = await memberRepo.getAllMembers();
    final allLocalsIncludingDeleted = await memberRepo
        .getAllMembersIncludingDeleted();
    final locals = allLocals.where((m) => !m.pluralkitSyncIgnored).toList();

    // Snapshot the PK identifiers returned by the current fetch — used by
    // hasResolvablePluralKitLink below and by the applier later to decide
    // whether a local's stored PK fields point at a member that actually
    // exists in the connected system.
    final fetchedPkUuids = {for (final pk in pkMembers) pk.uuid};
    final fetchedPkIds = {for (final pk in pkMembers) pk.id};

    // A local "already maps" a PK member only when its PK fields RESOLVE
    // against the current fetch. Stale PK fields inherited from a prior
    // different-system import (e.g. via Simply Plural) must NOT cause the
    // matching PK member to be hidden from the screen.
    final resolvedPkUuids = {
      for (final m in allLocalsIncludingDeleted)
        if (hasResolvablePluralKitLink(
              m,
              fetchedPkUuids: fetchedPkUuids,
              fetchedPkIds: fetchedPkIds,
            ) &&
            m.pluralkitUuid != null &&
            m.pluralkitUuid!.trim().isNotEmpty)
          m.pluralkitUuid!.trim(),
    };
    final resolvedPkIds = {
      for (final m in allLocalsIncludingDeleted)
        if (hasResolvablePluralKitLink(
              m,
              fetchedPkUuids: fetchedPkUuids,
              fetchedPkIds: fetchedPkIds,
            ) &&
            m.pluralkitId != null &&
            m.pluralkitId!.trim().isNotEmpty)
          m.pluralkitId!.trim(),
    };
    final unmappedPkMembers = pkMembers
        .where(
          (pk) =>
              !resolvedPkUuids.contains(pk.uuid) &&
              !resolvedPkIds.contains(pk.id),
        )
        .toList();

    // Locals without a current-system PK link — candidates for the
    // "Local members to push" section. Includes both truly-unlinked locals
    // (no PK fields) and unresolved-link locals (stale PK fields from a
    // prior different-system pairing). Excluded members are already filtered
    // out above.
    final unlinkedLocals = locals
        .where(
          (m) => !hasResolvablePluralKitLink(
            m,
            fetchedPkUuids: fetchedPkUuids,
            fetchedPkIds: fetchedPkIds,
          ),
        )
        .toList();

    final suggestions = const PkMemberMatcher().suggest(
      unlinkedLocals,
      unmappedPkMembers,
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
      } else if (s.confidence == PkMatchConfidence.ambiguous) {
        // F13: a name matching more than one candidate has no safe automatic
        // choice, so default to Skip rather than Import (which would duplicate an
        // existing same-name person). The user picks Link/Import from the row.
        pkDecisions[s.pkMember.uuid] = PkSkipDecision(
          pkMemberUuid: s.pkMember.uuid,
        );
      } else {
        pkDecisions[s.pkMember.uuid] = PkImportDecision(pkMember: s.pkMember);
      }
    }

    // Default decision for un-consumed unlinked locals: split by whether the
    // local already had PK fields set.
    //   - Truly-unlinked local (no PK fields): default to PushNew (existing
    //     behavior).
    //   - Unresolved-link local (PK fields set but pointing at a member not
    //     in the current PK system): default to Skip. The user already
    //     touched these PK fields once via a prior import; don't auto-push
    //     without explicit consent. Section-2 caption surfaces the override
    //     affordance.
    final localDecisions = <String, PkMappingDecision>{};
    for (final m in unlinkedLocals) {
      if (consumedLocalIds.contains(m.id)) continue;
      if (hasPluralKitLink(m)) {
        localDecisions[m.id] = PkSkipDecision(localMemberId: m.id);
      } else {
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
      pkMembers: unmappedPkMembers,
      localMembers: locals,
      decisionsByPkUuid: pkDecisions,
      decisionsByLocalId: localDecisions,
      fetchedPkUuids: fetchedPkUuids,
      fetchedPkIds: fetchedPkIds,
    );
  }

  /// Update the decision for a PK member. If the decision is a Link, drop
  /// the push decision that was defaulted for that local. If the decision
  /// moves away from Link, restore the local to the push/skip pool with the
  /// same asymmetric default as [build]: truly-unlinked locals default to
  /// Push; locals with unresolved PK fields default to Skip.
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
    // with a default decision unless it's now linked elsewhere.
    if (prior is PkLinkDecision) {
      final stillLinked = newPk.values.any(
        (d) => d is PkLinkDecision && d.localMemberId == prior.localMemberId,
      );
      if (!stillLinked) {
        final localMember = current.localMembers.firstWhere(
          (m) => m.id == prior.localMemberId,
          orElse: () => current.localMembers.first,
        );
        // Asymmetric default mirrors build(): if the local already carries
        // PK fields they didn't resolve (otherwise the local wouldn't be a
        // push candidate), default to Skip to avoid an unintended new-PK-
        // member POST.
        if (current.localMembers.any((m) => m.id == prior.localMemberId) &&
            hasPluralKitLink(localMember)) {
          newLocal[prior.localMemberId] = PkSkipDecision(
            localMemberId: prior.localMemberId,
          );
        } else {
          newLocal[prior.localMemberId] = PkPushNewDecision(
            localMemberId: prior.localMemberId,
          );
        }
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
  ///
  /// The pipeline runs in scoped phases ([PkMappingPhase]):
  /// 1. `applyingDecisions` — per-decision loop emits an applier op for each
  ///    Link/Import/Push/Skip choice. Progress 0.0 → 1.0.
  /// 2. Post-decisions, honors the persisted sync mode/direction:
  ///    full-sync pull walks PK switch history via
  ///    [PluralKitSyncService.importSwitchesAfterLink], full-sync push runs
  ///    [PluralKitSyncService.pushPendingSwitches], and live-fronts-only runs
  ///    [PluralKitSyncService.syncLiveFrontersOnly] instead of importing
  ///    history.
  ///
  /// `applyProgress` is reset to 0 at each phase boundary so the screen's
  /// progress bar reflects real per-phase progress instead of staying pinned
  /// at 100%. The Apply button stays `isLoading + disabled` across all
  /// phases; phase information is surfaced via [PkMappingState.statusText]
  /// rendered above the button — never on the button itself.
  ///
  /// [importingHistoryStatus] and [pushingHistoryStatus] are the pre-
  /// localized strings shown above the button during phases 2 and 3. The
  /// caller (the mapping screen) resolves them from [BuildContext]; the
  /// controller has no BuildContext of its own.
  ///
  /// Returns a [PkMappingApplyOutcome]:
  /// - [PkMappingApplyOutcomeApplied]: success, bootstrap ran.
  /// - [PkMappingApplyOutcomeNeedsFronterResolution]: success, but active
  ///   fronter sets disagree and direction can act on the difference. Bootstrap
  ///   NOT yet run — deferred to [applyFronterResolution] (T9).
  /// - [PkMappingApplyOutcomeFailed]: one or more decisions failed.
  ///
  /// The return value is `null` on early exits (not connected, already
  /// applying, ref unmounted before completion, unhandled exception). The
  /// caller should treat `null` as "stay on screen and show state.error".
  Future<PkMappingApplyOutcome?> apply({
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
    String? offlineErrorMessage,
  }) async {
    final current = state.value;
    if (current == null || current.isApplying) return null;

    state = AsyncData(
      current.copyWith(
        isApplying: true,
        applyProgress: 0.0,
        phase: PkMappingPhase.applyingDecisions,
        clearError: true,
        clearResults: true,
        clearStatusText: true,
      ),
    );

    final syncService = ref.read(pluralKitSyncServiceProvider);
    final client = await syncService.buildClientIgnoringMappingGate();
    if (!ref.mounted) {
      client?.dispose();
      return null;
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
      return null;
    }

    try {
      // Pre-flight: verify we can reach PluralKit before we start mutating
      // state. If the user lost connectivity between opening this screen and
      // tapping Apply, fail fast with a clean message instead of N raw socket
      // exceptions. Cap the probe at 5s so offline users don't wait the
      // client's 15s default. Non-network exceptions fall through to the
      // outer catch, which already routes them into `state.error`.
      // Capture the connected system id from the
      // pre-flight probe so the applier can reject prior-row reuse of a member
      // that PK reports as owned by a different system (stale short/uuid ref).
      String? connectedSystemId;
      try {
        final probedSystem = await client.getSystem().timeout(
          const Duration(seconds: 5),
        );
        connectedSystemId = probedSystem.id;
      } on Object catch (e) {
        if (isPluralKitNetworkException(e)) {
          if (!ref.mounted) return null;
          final after = state.value;
          if (after != null) {
            state = AsyncData(
              after.copyWith(
                isApplying: false,
                clearStatusText: true,
                error: offlineErrorMessage ?? _defaultOfflineErrorMessage,
              ),
            );
          }
          return null;
        }
        rethrow;
      }

      final memberRepo = ref.read(memberRepositoryProvider);
      final db = ref.read(databaseProvider);
      final bus = ref.read(pkSyncEventBusProvider);
      final applier = PkMappingApplier(
        members: memberRepo,
        state: PkMappingStateDao(db),
        pushService: const PkPushService(),
        client: client,
        bus: bus,
        connectedSystemId: connectedSystemId,
      );

      // Build the full decision list — PK decisions first, then local-only.
      final decisions = <PkMappingDecision>[
        ...current.decisionsByPkUuid.values,
        ...current.decisionsByLocalId.values,
      ];

      // Snapshot the current PK fetch for the applier so the push-new path
      // can distinguish "already linked" from "stale PK fields from a prior
      // different-system import" — see PkMappingApplier.apply doc.
      final resolution = PkResolutionSnapshot(
        fetchedPkUuids: current.fetchedPkUuids,
        fetchedPkIds: current.fetchedPkIds,
      );

      // Phase 1: per-decision loop.
      final results = <PkApplyResult>[];
      for (var i = 0; i < decisions.length; i++) {
        final r = await applier.apply([decisions[i]], resolution: resolution);
        if (!ref.mounted) return null;
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

      // On failure: do NOT acknowledge mapping and do NOT run bootstrap.
      // Return the failure outcome so the screen can surface it.
      if (hasFailures) {
        final failures = results
            .where((r) => r.outcome == PkApplyOutcome.failed)
            .toList();
        final after = state.value;
        if (after != null) {
          state = AsyncData(
            after.copyWith(
              isApplying: false,
              applyProgress: 1.0,
              lastResults: results,
              clearStatusText: true,
            ),
          );
        }
        return PkMappingApplyOutcomeFailed(failures);
      }

      // All decisions succeeded. NOTE: `acknowledgeMapping()` is intentionally
      // NOT called here. Calling it before the disagreement check would flip
      // `canAutoSync` true while the "Who's fronting?" sheet is being shown,
      // allowing the auto-poll provider to fire a sync the user hadn't yet
      // decided on. See bug pairing push.
      //
      // It is instead called from:
      //   - The Applied outcome path below (sets match, no resolution needed).
      //   - The end of `applyFronterResolution()` (user resolved the sheet).
      //   - The start of `deferBootstrap()` (user explicitly chose defer).
      if (!ref.mounted) return null;

      // Load the persisted sync mode and direction.
      await ref.read(pkSyncModeProvider.notifier).load();
      await ref.read(pkSyncDirectionProvider.notifier).load();
      if (!ref.mounted) return null;
      final mode = ref.read(pkSyncModeProvider);
      final direction = ref.read(pkSyncDirectionProvider);

      // Check for fronter disagreement.
      //
      // Fetch PK's current fronters with a 5s cap. On timeout or any network
      // error, treat as "no disagreement detectable" and proceed directly to
      // the bootstrap.
      PKSwitch? pkCurrentSwitch;
      var skipDisagreementCheck = false;
      try {
        pkCurrentSwitch = await client.getCurrentFronters().timeout(
          const Duration(seconds: 5),
        );
      } on Object catch (e) {
        // Network or timeout — log and skip the disagreement check.
        debugPrint(
          '[PK_MAPPING] getCurrentFronters failed; skipping fronter '
          'disagreement check: $e',
        );
        skipDisagreementCheck = true;
      }

      // If direction can't act on a disagreement, skip the check too.
      if (!skipDisagreementCheck &&
          direction != PkSyncDirection.disabled &&
          (direction.pullEnabled || direction.pushEnabled)) {
        // Compute the local active fronter set.
        final frontingRepo = ref.read(frontingSessionRepositoryProvider);
        final activeSessions = await frontingRepo
            .getAllActiveSessionsUnfiltered();
        final localFronterIds = activeSessions
            .where((s) => s.memberId != null && !s.isSleep && !s.isDeleted)
            .map((s) => s.memberId!)
            .toSet();

        // Project PK current fronters (short IDs) → local member IDs via:
        //   1. The just-applied PkLinkDecision entries (covers fresh links).
        //   2. PkImportDecision entries (the applier wrote the PK short ID
        //      onto the new local member; we resolve via DB lookup below).
        //   3. Already-mapped members from prior sessions whose
        //      `pluralkitId` is set on the local member row but have no
        //      decision in this batch.
        //
        // PKSwitch.members contains 5-char PK short IDs. Without (2)+(3) PK
        // could have an active mapped fronter that's invisible to the
        // disagreement check, causing the "Who's fronting?" sheet to be
        // skipped or shown with the wrong options. See bug ephemeral lane.
        final pkShortIdToLocalId = <String, String>{};
        for (final d in current.decisionsByPkUuid.values) {
          if (d is PkLinkDecision) {
            pkShortIdToLocalId[d.pkMember.id] = d.localMemberId;
          }
        }
        // Augment with DB-side lookup for any PK short ID still unresolved
        // (PkImportDecision results + already-mapped members from prior
        // sessions). One-shot scan is acceptable here — setup-time path.
        if (pkCurrentSwitch != null && pkCurrentSwitch.members.isNotEmpty) {
          final unresolved = pkCurrentSwitch.members
              .where((id) => !pkShortIdToLocalId.containsKey(id))
              .toSet();
          if (unresolved.isNotEmpty) {
            final memberRepo = ref.read(memberRepositoryProvider);
            final allMembers = await memberRepo.getAllMembers();
            for (final m in allMembers) {
              final pkId = m.pluralkitId?.trim();
              if (pkId != null &&
                  pkId.isNotEmpty &&
                  unresolved.contains(pkId)) {
                pkShortIdToLocalId[pkId] = m.id;
              }
            }
          }
        }
        final pkFronterLocalIds = <String>{};
        if (pkCurrentSwitch != null) {
          for (final pkShortId in pkCurrentSwitch.members) {
            final localId = pkShortIdToLocalId[pkShortId];
            if (localId != null) pkFronterLocalIds.add(localId);
          }
        }

        // If the sets differ, defer the bootstrap and return the resolution
        // outcome so the screen can show the "Who's fronting?" sheet.
        if (!setEquals(localFronterIds, pkFronterLocalIds)) {
          final after = state.value;
          if (after != null) {
            state = AsyncData(
              after.copyWith(
                isApplying: false,
                applyProgress: 1.0,
                lastResults: results,
                clearStatusText: true,
              ),
            );
          }
          ref.invalidate(pluralKitSyncProvider);
          return PkMappingApplyOutcomeNeedsFronterResolution(
            localFronterMemberIds: localFronterIds,
            pkFronterMemberIds: pkFronterLocalIds,
            direction: direction,
            mode: mode,
            pkCurrentSwitch:
                pkCurrentSwitch ??
                PKSwitch(id: '', timestamp: DateTime.now(), members: const []),
          );
        }
      }

      // Sets match (or check was skipped) — acknowledge mapping then run the
      // bootstrap inline. acknowledgeMapping() is called here (not before the
      // disagreement check) so `canAutoSync` only flips true when no
      // resolution sheet is needed. See bug pairing push.
      await syncService.acknowledgeMapping();
      if (!ref.mounted) return null;

      // Pass the fetched pkCurrentSwitch as a cache so the liveFrontsOnly
      // bootstrap branch can skip a redundant getCurrentFronters network call.
      // When skipDisagreementCheck was true, pkCurrentSwitch is null and the
      // bootstrap will fetch fresh (safe fallback).
      await _runPostApplyBootstrap(
        mode: mode,
        direction: direction,
        syncService: syncService,
        importingHistoryStatus: importingHistoryStatus,
        pushingHistoryStatus: pushingHistoryStatus,
        knownCurrentFronters: pkCurrentSwitch,
      );
      if (!ref.mounted) return null;

      // Refresh the PK sync provider so UI picks up the new canAutoSync.
      ref.invalidate(pluralKitSyncProvider);

      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            isApplying: false,
            applyProgress: 1.0,
            lastResults: results,
            clearStatusText: true,
          ),
        );
      }
      return const PkMappingApplyOutcomeApplied();
    } catch (e, st) {
      if (!ref.mounted) return null;
      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            isApplying: false,
            error: e.toString(),
            clearStatusText: true,
          ),
        );
      } else {
        state = AsyncError(e, st);
      }
      return null;
    } finally {
      client.dispose();
    }
  }

  /// Runs the post-apply bootstrap: syncs the surfaces allowed by the persisted
  /// mode and direction. Errors here are non-fatal — they surface on the next
  /// `syncRecentData` call via `state.syncError`.
  ///
  /// This method is extracted so it can be reused by [applyFronterResolution]
  /// (T9) after the user resolves the fronter disagreement.
  ///
  /// [syncService] must be the already-read service (avoids a second
  /// `ref.read` after a potential `await` boundary in the caller).
  ///
  /// [knownCurrentFronters] is an optional cache pass-through: when the caller
  /// already fetched the current PK switch (e.g. during the disagreement check
  /// in [apply] or from [applyFronterResolution]'s `pkCurrentSwitch` param),
  /// pass it here so `syncLiveFrontersOnly` can skip a redundant network call
  /// in the liveFrontsOnly bootstrap branch.
  Future<void> _runPostApplyBootstrap({
    required PkSyncMode mode,
    required PkSyncDirection direction,
    required PluralKitSyncService syncService,
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
    PKSwitch? knownCurrentFronters,
  }) async {
    try {
      if (mode == PkSyncMode.liveFrontsOnly) {
        if (direction.pullEnabled || direction.pushEnabled) {
          if (!ref.read(frontingMigrationWritesBlockedProvider)) {
            final summary = await syncService.syncLiveFrontersOnly(
              direction: direction,
              knownCurrentFronters: knownCurrentFronters,
            );
            if (!ref.mounted) return;
            if (summary != null && direction.pullEnabled) {
              await ref
                  .read(pkUnmappedFrontersNoticeProvider.notifier)
                  .applyLiveFrontersSummary(summary);
            }
          }
        }
      } else {
        if (direction.pullEnabled) {
          final beforeImport = state.value;
          if (beforeImport != null) {
            state = AsyncData(
              beforeImport.copyWith(
                phase: PkMappingPhase.importingSwitches,
                applyProgress: 0.0,
                statusText: importingHistoryStatus,
              ),
            );
          }
          await syncService.importSwitchesAfterLink(
            onProgress: (fraction, message) {
              if (!ref.mounted) return;
              final cur = state.value;
              if (cur == null) return;
              state = AsyncData(
                cur.copyWith(
                  applyProgress: fraction.clamp(0.0, 1.0),
                  statusText: message,
                ),
              );
            },
          );
          if (!ref.mounted) return;
        }

        if (direction.pushEnabled) {
          final beforePush = state.value;
          if (beforePush != null) {
            state = AsyncData(
              beforePush.copyWith(
                phase: PkMappingPhase.pushingSwitches,
                applyProgress: 0.0,
                statusText: pushingHistoryStatus,
              ),
            );
          }
          await syncService.pushPendingSwitches();
        }
      }
    } catch (_) {
      // Non-fatal — surfaces on next syncRecentData via state.syncError.
    }
  }

  /// Called by the "Who's fronting?" sheet after the user picks an option.
  ///
  /// Applies the user's fronter-resolution choice, then runs the deferred
  /// post-apply bootstrap.
  ///
  /// Push-enabled directions write PK first, advance the import cursor, and
  /// then apply local diff writes so interrupted flows can recover from PK.
  /// Empty choices are pushed too, allowing PK to clear current fronters.
  ///
  /// Returns [PkMappingApplyOutcomeApplied] when the deferred resolution and
  /// bootstrap complete. Returns `null` for early exits or unhandled failures;
  /// when still mounted, failures are also stored in [PkMappingState.error].
  Future<PkMappingApplyOutcome?> applyFronterResolution({
    required Set<String> chosenLocalMemberIds,
    required PkSyncDirection direction,
    required PkSyncMode mode,
    required PKSwitch pkCurrentSwitch,
    String? resolvingFrontersStatus,
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
  }) async {
    // Fronting rows may be mid-migration; skip PK and local writes until safe.
    if (ref.read(frontingMigrationWritesBlockedProvider)) return null;

    final syncService = ref.read(pluralKitSyncServiceProvider);
    final before = state.value;
    if (before?.isApplying ?? false) return null;
    if (before != null) {
      state = AsyncData(
        before.copyWith(
          isApplying: true,
          applyProgress: 0.0,
          phase: PkMappingPhase.resolvingFronters,
          statusText: resolvingFrontersStatus,
          clearError: true,
        ),
      );
    }

    var completedSuccessfully = false;
    try {
      // Push first so PK remains the recoverable truth if the flow stops.
      // Empty choices clear PK's current fronters.
      final now = DateTime.now();
      PKSwitch? pushedSwitch;
      var pushAttempted = false;
      if (direction.pushEnabled) {
        pushAttempted = true;
        final pending = _pendingFronterResolutionPush;
        if (pending != null && pending.matches(chosenLocalMemberIds)) {
          pushedSwitch = pending.switchEntry;
        } else {
          if (pending != null) {
            _pendingFronterResolutionPush = null;
          }
          pushedSwitch = await syncService.pushOverrideSwitch(
            chosenLocalMemberIds.toList(),
            now,
          );
          if (!ref.mounted) return null;
          if (pushedSwitch == null) {
            final after = state.value;
            if (after != null) {
              state = AsyncData(
                after.copyWith(
                  isApplying: false,
                  error: _overrideSwitchPushFailedMessage,
                ),
              );
            }
            return null;
          }
          _pendingFronterResolutionPush = _PendingFronterResolutionPush(
            chosenLocalMemberIds: Set.unmodifiable(chosenLocalMemberIds),
            switchEntry: pushedSwitch,
          );
        }

        final activePush = _pendingFronterResolutionPush;
        if (activePush == null || !activePush.cursorAdvanced) {
          // Use PK's stored timestamp/id to avoid re-importing the override.
          await syncService.advanceImportCursorPast(
            switchId: pushedSwitch.id,
            timestamp: pushedSwitch.timestamp,
          );
          if (!ref.mounted) return null;
          activePush?.cursorAdvanced = true;
        }
      }

      // Preserve unchanged fronter sessions; mutate only the difference.
      final db = ref.read(databaseProvider);
      final repo = ref.read(frontingSessionRepositoryProvider);
      final mutationService = ref.read(frontingMutationServiceProvider);
      var startedNewFronts = false;
      await db.transaction(() async {
        final activeSessions = await repo.getAllActiveSessionsUnfiltered();

        for (final s in activeSessions) {
          if (s.memberId == null || s.isSleep) continue;
          if (!chosenLocalMemberIds.contains(s.memberId)) {
            await repo.endSession(s.id, now);
          }
        }

        final currentlyFronting = activeSessions
            .where((s) => s.memberId != null && !s.isSleep)
            .map((s) => s.memberId!)
            .toSet();
        final toStart = chosenLocalMemberIds.difference(currentlyFronting);
        if (toStart.isNotEmpty) {
          await mutationService.startFronting(toStart.toList(), startTime: now);
          startedNewFronts = true;
        }
      });

      if (!ref.mounted) return null;

      // This path bypasses FrontingNotifier's usual re-anchor hook.
      if (startedNewFronts) {
        scheduleFrontingReminderReanchorBestEffort(ref);
      }

      // Push paths bootstrap from the override switch; pull-only uses the
      // fetched PK switch.
      final PKSwitch? bootstrapKnown;
      if (pushAttempted) {
        bootstrapKnown = pushedSwitch; // new switch on success, null on failure
      } else {
        bootstrapKnown = pkCurrentSwitch;
      }

      await _runPostApplyBootstrap(
        mode: mode,
        direction: direction,
        syncService: syncService,
        importingHistoryStatus: importingHistoryStatus,
        pushingHistoryStatus: pushingHistoryStatus,
        knownCurrentFronters: bootstrapKnown,
      );

      if (!ref.mounted) return null;

      // Acknowledge only after bootstrap so auto-sync cannot run mid-resolution.
      await syncService.acknowledgeMapping();
      if (!ref.mounted) return null;

      ref.invalidate(pluralKitSyncProvider);
      _pendingFronterResolutionPush = null;
      completedSuccessfully = true;
      return const PkMappingApplyOutcomeApplied();
    } catch (e, st) {
      if (!ref.mounted) return null;
      final after = state.value;
      if (after != null) {
        state = AsyncData(
          after.copyWith(isApplying: false, error: e.toString()),
        );
      } else {
        state = AsyncError(e, st);
      }
      return null;
    } finally {
      if (ref.mounted) {
        final after = state.value;
        if (after != null && completedSuccessfully) {
          state = AsyncData(
            after.copyWith(
              isApplying: false,
              applyProgress: 1.0,
              clearStatusText: true,
            ),
          );
        }
      }
    }
  }

  /// Called by the setup screen after the user picks "Decide later" in the
  /// "Who's fronting?" sheet. Acknowledges the mapping (since the user
  /// explicitly chose to defer) and persists a deferred-sync flag so the
  /// setup screen can render a banner reminding the user to manually sync
  /// when ready.
  ///
  /// `acknowledgeMapping()` runs here (not in [apply]) because we must not
  /// flip `canAutoSync` true until the user has made an explicit choice on
  /// the "Who's fronting?" sheet (defer counts). See bug pairing push.
  Future<void> deferBootstrap() async {
    final syncService = ref.read(pluralKitSyncServiceProvider);
    await syncService.acknowledgeMapping();
    if (!ref.mounted) return;

    final dao = ref.read(pluralKitSyncDaoProvider);
    final row = await dao.getSyncState();
    final systemId = row.systemId;
    if (systemId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PkPrefsKeys.firstSyncDeferred(systemId), true);
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
