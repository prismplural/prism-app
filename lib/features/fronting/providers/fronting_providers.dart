import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';

/// Watches the current active fronting session (null if no one fronting).
final activeSessionProvider = StreamProvider<FrontingSession?>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchActiveSession();
});

/// Watches all active sessions (for co-fronting).
final activeSessionsProvider = StreamProvider<List<FrontingSession>>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchActiveSessions();
});

/// Current fronter member (resolved from active session).
final currentFronterProvider = StreamProvider<Member?>((ref) {
  final sessionAsync = ref.watch(activeSessionProvider);
  final memberRepo = ref.watch(memberRepositoryProvider);
  return sessionAsync.when(
    data: (session) {
      if (session?.memberId == null) return Stream.value(null);
      return memberRepo.watchMemberById(session!.memberId!);
    },
    loading: () => Stream.value(null),
    error: (error, stackTrace) => Stream.value(null),
  );
});

/// Recent fronting history, parameterized by limit. Uses a stream so
/// the UI updates automatically when sessions are created or modified.
final frontingHistoryProvider = StreamProvider.autoDispose
    .family<List<FrontingSession>, int>((ref, limit) {
      final repo = ref.watch(frontingSessionRepositoryProvider);
      return repo.watchRecentSessions(limit: limit);
    });

/// Member fronting frequency counts (member_id -> session count) for the
/// most recent sessions. Used by QuickFrontSection to sort by frequency
/// without loading full session objects.
final memberFrontingCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.getMemberFrontingCounts(recentLimit: 50);
});

/// Single session by ID. Uses a stream for real-time updates after edits.
final sessionByIdProvider = StreamProvider.autoDispose
    .family<FrontingSession?, String>((ref, id) {
      final repo = ref.watch(frontingSessionRepositoryProvider);
      return repo.watchSessionById(id);
    });

final frontingMutationServiceProvider = Provider<FrontingMutationService>((
  ref,
) {
  final memberRepository = ref.watch(memberRepositoryProvider);
  return FrontingMutationService(
    repository: ref.watch(frontingSessionRepositoryProvider),
    mutationRunner: MutationRunner.forDatabase(ref.watch(databaseProvider)),
    // Required for the auto-create-Unknown-sentinel path used by the
    // add-front sheet's "Front as Unknown" flow.
    memberRepository: memberRepository,
    // The lifecycle's delete-fill + fillGaps paths also auto-create the
    // Unknown sentinel — wire the same MemberRepository through so those
    // writes don't dangle.
    lifecycle: SessionLifecycleService(memberRepository: memberRepository),
  );
});

/// Invalidates providers that depend on active fronting session state.
/// Call this after any mutation that changes which sessions are active or
/// modifies session member IDs (e.g. via [FrontingChangeExecutor]).
void invalidateFrontingProviders(WidgetRef ref) {
  ref.invalidate(activeSessionProvider);
  ref.invalidate(activeSessionsProvider);
  ref.invalidate(memberFrontingCountsProvider);
}

/// Fronting service for actions (start/end/switch sessions).
class FrontingNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  void _invalidateMemberStats(String? memberId) {
    if (memberId != null) {
      ref.invalidate(memberFrontingStatsProvider(memberId));
      ref.invalidate(memberRecentSessionsProvider(memberId));
    }
  }

  /// Starts a fronting session for one or more members.
  ///
  /// Each member in [memberIds] gets its own session row with the same
  /// [startTime] (per-member model — co-fronting is emergent overlap, not a
  /// field). Use `.sessions.single` for single-member calls; iterate
  /// `.sessions` for multi-member.
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    final result = await _unwrapMutation(
      ref.read(frontingMutationServiceProvider).startFronting(
        memberIds,
        confidence: confidence,
        notes: notes,
        startTime: startTime,
      ),
    );
    for (final session in result.sessions) {
      _invalidateMemberStats(session.memberId);
    }
    for (final id in result.previousMemberIds) {
      _invalidateMemberStats(id);
    }
  }

  /// Ends active fronting sessions for each member in [memberIds].
  Future<void> endFronting(List<String> memberIds) async {
    await _unwrap(
      ref.read(frontingMutationServiceProvider).endFronting(memberIds),
    );
    for (final id in memberIds) {
      _invalidateMemberStats(id);
    }
  }

  /// Adds a single co-fronter by starting a new session for [memberId].
  Future<void> addCoFronter(String memberId) async {
    final result = await _unwrapMutation(
      ref.read(frontingMutationServiceProvider).addCoFronter(memberId),
    );
    // addCoFronter guarantees exactly one session back.
    _invalidateMemberStats(result.sessions.single.memberId);
  }

  /// Removes a single co-fronter by ending their active session.
  Future<void> removeCoFronter(String memberId) async {
    await _unwrap(
      ref.read(frontingMutationServiceProvider).removeCoFronter(memberId),
    );
    _invalidateMemberStats(memberId);
  }

  Future<void> updateSession(
    String sessionId,
    UpdateFrontingSessionPatch patch,
  ) async {
    final session = await ref
        .read(frontingSessionRepositoryProvider)
        .getSessionById(sessionId);
    if (session == null) {
      throw AppFailure.notFound('Fronting session not found');
    }

    await _unwrap(
      ref.read(frontingMutationServiceProvider).updateSession(sessionId, patch),
    );

    final updated = patch.applyTo(session);
    _invalidateMemberStats(updated.memberId);
    _invalidateMemberStats(session.memberId);
  }

  Future<void> applyEdit({
    required String sessionId,
    required UpdateFrontingSessionPatch patch,
    List<FrontingSession> overlapsToTrim = const [],
    List<FrontingSession> adjacentMerges = const [],
    List<GapInfo> gapsToFill = const [],
  }) async {
    final session = await ref
        .read(frontingSessionRepositoryProvider)
        .getSessionById(sessionId);
    if (session == null) {
      throw AppFailure.notFound('Fronting session not found');
    }

    await _unwrap(
      ref
          .read(frontingMutationServiceProvider)
          .applyEdit(
            sessionId: sessionId,
            patch: patch,
            overlapsToTrim: overlapsToTrim,
            adjacentMerges: adjacentMerges,
            gapsToFill: gapsToFill,
          ),
    );

    final updated = patch.applyTo(session);
    _invalidateMemberStats(updated.memberId);
    _invalidateMemberStats(session.memberId);
  }

  Future<void> deleteSession(String sessionId) async {
    final session = await ref
        .read(frontingSessionRepositoryProvider)
        .getSessionById(sessionId);
    final allSessions = await ref
        .read(frontingSessionRepositoryProvider)
        .getRecentSessions(limit: 100);
    await _unwrap(
      ref
          .read(frontingMutationServiceProvider)
          .executeDeleteOption(
            sessionId: sessionId,
            option: DeleteOption.delete,
            allSessions: allSessions,
          ),
    );
    _invalidateMemberStats(session?.memberId);
  }

  Future<String?> executeDeleteOption({
    required String sessionId,
    required DeleteOption option,
    required List<FrontingSession> allSessions,
  }) async {
    final session = await ref
        .read(frontingSessionRepositoryProvider)
        .getSessionById(sessionId);
    final unknownId = await _unwrap(
      ref
          .read(frontingMutationServiceProvider)
          .executeDeleteOption(
            sessionId: sessionId,
            option: option,
            allSessions: allSessions,
          ),
    );
    _invalidateMemberStats(session?.memberId);
    return unknownId;
  }

  /// Splits a session at [splitTime]: the original session's end is trimmed
  /// to [splitTime] and a new session from [splitTime] onwards is created.
  ///
  /// Both halves keep the same member — per the per-member model,
  /// member-reassignment on split is done by a subsequent edit, not here.
  Future<void> splitSession(
    String sessionId,
    DateTime splitTime,
  ) async {
    final session = await ref
        .read(frontingSessionRepositoryProvider)
        .getSessionById(sessionId);
    if (session == null) {
      throw AppFailure.notFound('Fronting session not found');
    }

    // splitSession is positional (sessionId, splitTime) in the new API.
    final created = await _unwrap(
      ref
          .read(frontingMutationServiceProvider)
          .splitSession(sessionId, splitTime),
    );
    _invalidateMemberStats(session.memberId);
    _invalidateMemberStats(created.memberId);
  }

  Future<T> _unwrap<T>(Future<MutationResult<T>> resultFuture) async {
    final result = await resultFuture;
    return result.when(
      success: (data) => data,
      failure: (error) => throw error,
    );
  }

  Future<FrontingMutationResult> _unwrapMutation(
    Future<MutationResult<FrontingMutationResult>> resultFuture,
  ) async {
    final result = await resultFuture;
    return result.when(
      success: (data) => data,
      failure: (error) => throw error,
    );
  }
}

final frontingNotifierProvider = AsyncNotifierProvider<FrontingNotifier, void>(
  FrontingNotifier.new,
);

/// Page size for unified session history (fronting + sleep).
const sessionPageSize = 30;

/// Tracks how many sessions to load in the unified history.
/// Starts at [sessionPageSize], increases on scroll.
class SessionLimitNotifier extends Notifier<int> {
  @override
  int build() => sessionPageSize;

  void loadMore() => state = state + sessionPageSize;
}

final sessionLimitProvider = NotifierProvider<SessionLimitNotifier, int>(
  SessionLimitNotifier.new,
);

/// Unified session history (fronting + sleep), paginated by [sessionLimitProvider].
///
/// NOTE: this is a row-page query — it orders by `start_time DESC` and
/// takes the top N rows. For most consumers (sleep tiles, simple history
/// rendering) this is fine. **Derived periods do NOT consume from this
/// stream** because a 400-day continuous host whose row started before
/// the visible page would be silently dropped; see
/// [unifiedHistoryOverlapProvider] / [derivedPeriodsProvider] for the
/// overlap-query path the sweep uses.
final unifiedHistoryProvider =
    StreamProvider.autoDispose<List<FrontingSession>>((ref) {
  final limit = ref.watch(sessionLimitProvider);
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchRecentAllSessions(limit: limit);
});

/// How far back the derived-period sweep looks when computing periods
/// for the unified history list.
///
/// 1A scope: load every session overlapping the last 90 days. This is
/// the simple version of §4.6's "paginate over derived periods" — we
/// don't yet have date-range scrubbing in the list view, so we ship a
/// conservative window large enough to catch a long-running host.
/// A future refactor can switch this to a scroll-driven `(rangeStart,
/// rangeEnd)` family parameter; the overlap-query plumbing below is
/// already shaped for that.
const _derivedPeriodsLookbackDays = 90;

/// Sessions overlapping the visible range used by the derived-period
/// sweep (§4.6 step 1).
///
/// Key correctness property: a 400-day continuous host whose row
/// started before the lookback window but is still open (or ended
/// inside it) is included — the upstream filter is
/// `start_time < range_end AND (end_time IS NULL OR end_time > range_start)`,
/// which a row-paged "newest N rows" query would silently drop.
final unifiedHistoryOverlapProvider =
    StreamProvider.autoDispose<List<FrontingSession>>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  final now = DateTime.now();
  // Half-open `[rangeStart, rangeEnd)` window. rangeEnd is "now" — the
  // sweep itself substitutes max(now, rangeEnd) for open-ended sessions
  // so trailing live periods extend correctly.
  final rangeStart = now.subtract(const Duration(days: _derivedPeriodsLookbackDays));
  return repo.watchSessionsOverlappingRange(rangeStart, now);
});
