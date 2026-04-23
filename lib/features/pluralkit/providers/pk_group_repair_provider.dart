import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';

class PkGroupRepairState {
  const PkGroupRepairState({
    this.isRunning = false,
    this.automaticRunAttempted = false,
    this.pendingReviewCount = 0,
    this.pendingReviewItems = const <PkGroupReviewItem>[],
    this.lastReport,
    this.error,
  });

  final bool isRunning;
  final bool automaticRunAttempted;
  final int pendingReviewCount;
  final List<PkGroupReviewItem> pendingReviewItems;
  final PkGroupRepairReport? lastReport;
  final String? error;

  PkGroupRepairState copyWith({
    bool? isRunning,
    bool? automaticRunAttempted,
    int? pendingReviewCount,
    List<PkGroupReviewItem>? pendingReviewItems,
    PkGroupRepairReport? lastReport,
    String? error,
    bool clearError = false,
  }) {
    return PkGroupRepairState(
      isRunning: isRunning ?? this.isRunning,
      automaticRunAttempted:
          automaticRunAttempted ?? this.automaticRunAttempted,
      pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
      pendingReviewItems: pendingReviewItems ?? this.pendingReviewItems,
      lastReport: lastReport ?? this.lastReport,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final pkGroupRepairServiceProvider = Provider<PkGroupRepairService>((ref) {
  final db = ref.watch(databaseProvider);
  final pkSyncService = ref.watch(pluralKitSyncServiceProvider);

  return PkGroupRepairService(
    memberGroupsDao: db.memberGroupsDao,
    aliasesDao: db.pkGroupSyncAliasesDao,
    hasRepairToken: pkSyncService.hasRepairToken,
    fetchRepairReferenceData: pkSyncService.fetchRepairReferenceData,
  );
});

class PkGroupRepairController extends AsyncNotifier<PkGroupRepairState> {
  Future<PkGroupRepairReport>? _inFlight;

  @override
  Future<PkGroupRepairState> build() async {
    final service = ref.read(pkGroupRepairServiceProvider);
    final pendingItems = await service.getPendingReviewItems();
    return PkGroupRepairState(
      pendingReviewCount: pendingItems.length,
      pendingReviewItems: pendingItems,
    );
  }

  Future<PkGroupRepairReport> run({
    String? token,
    bool allowStoredToken = true,
    bool automatic = false,
  }) async {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final current = state.value ?? await future;
    if (automatic && current.automaticRunAttempted) {
      return current.lastReport ??
          PkGroupRepairReport(
            referenceMode: PkGroupRepairReferenceMode.none,
            backfilledEntries: 0,
            canonicalizedEntryIds: 0,
            revivedTombstonesDuringCanonicalization: 0,
            legacyEntriesSoftDeletedDuringCanonicalization: 0,
            duplicateSetsMerged: 0,
            duplicateGroupsSoftDeleted: 0,
            parentReferencesRehomed: 0,
            entriesRehomed: 0,
            entryConflictsSoftDeleted: 0,
            aliasesRecorded: 0,
            ambiguousGroupsSuppressed: 0,
            pendingReviewCount: current.pendingReviewCount,
          );
    }

    state = AsyncData(
      current.copyWith(
        isRunning: true,
        automaticRunAttempted: current.automaticRunAttempted || automatic,
        clearError: true,
      ),
    );

    final futureRun = ref
        .read(pkGroupRepairServiceProvider)
        .run(token: token, allowStoredToken: allowStoredToken);
    _inFlight = futureRun;

    try {
      final report = await futureRun;
      final service = ref.read(pkGroupRepairServiceProvider);
      final pendingItems = await service.getPendingReviewItems();
      state = AsyncData(
        current.copyWith(
          isRunning: false,
          automaticRunAttempted: current.automaticRunAttempted || automatic,
          pendingReviewCount: pendingItems.length,
          pendingReviewItems: pendingItems,
          lastReport: report,
          clearError: true,
        ),
      );
      return report;
    } catch (error) {
      final pending = await ref
          .read(pkGroupRepairServiceProvider)
          .getPendingReviewItems();
      state = AsyncData(
        current.copyWith(
          isRunning: false,
          automaticRunAttempted: current.automaticRunAttempted || automatic,
          pendingReviewCount: pending.length,
          pendingReviewItems: pending,
          error: error.toString(),
        ),
      );
      rethrow;
    } finally {
      if (identical(_inFlight, futureRun)) {
        _inFlight = null;
      }
    }
  }

  Future<void> runAutomaticIfNeeded() async {
    final current = state.value ?? await future;
    if (current.automaticRunAttempted) return;
    try {
      await run(allowStoredToken: false, automatic: true);
    } catch (_) {
      // Automatic local repair is best-effort; the controller state still
      // captures the error for UI/debug surfaces.
    }
  }

  Future<void> dismissReviewItem(String groupId) async {
    await _runReviewMutation(
      (service) => service.dismissReviewItems([groupId]),
    );
  }

  Future<void> keepReviewItemLocalOnly(String groupId) async {
    await _runReviewMutation(
      (service) => service.keepReviewItemsLocalOnly([groupId]),
    );
  }

  Future<void> mergeReviewItemIntoCanonical(String groupId) async {
    await _runReviewMutation(
      (service) => service.mergeReviewItemIntoCanonical(groupId),
    );
  }

  Future<void> _runReviewMutation(
    Future<void> Function(PkGroupRepairService service) action,
  ) async {
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(isRunning: true, clearError: true));

    try {
      await action(ref.read(pkGroupRepairServiceProvider));
      final pendingItems = await ref
          .read(pkGroupRepairServiceProvider)
          .getPendingReviewItems();
      state = AsyncData(
        current.copyWith(
          isRunning: false,
          pendingReviewCount: pendingItems.length,
          pendingReviewItems: pendingItems,
          clearError: true,
        ),
      );
    } catch (error) {
      final pendingItems = await ref
          .read(pkGroupRepairServiceProvider)
          .getPendingReviewItems();
      state = AsyncData(
        current.copyWith(
          isRunning: false,
          pendingReviewCount: pendingItems.length,
          pendingReviewItems: pendingItems,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }
}

final pkGroupRepairControllerProvider =
    AsyncNotifierProvider<PkGroupRepairController, PkGroupRepairState>(
      PkGroupRepairController.new,
    );

final pkGroupRepairHasStoredTokenProvider = FutureProvider<bool>((ref) async {
  // Re-check token availability when the visible PK sync state changes so the
  // repair UI updates after connect/disconnect without owning token logic.
  ref.watch(pluralKitSyncProvider);
  return ref.watch(pluralKitSyncServiceProvider).hasRepairToken();
});

final pkGroupRepairBootstrapProvider = Provider<Object?>((ref) {
  Future<void> maybeTrigger() async {
    if (syncAutoConfigureInProgress.value) return;
    final handle = ref.read(prismSyncHandleProvider).value;
    final health = ref.read(syncHealthProvider);
    if (handle == null || health != SyncHealthState.healthy) return;
    await ref
        .read(pkGroupRepairControllerProvider.notifier)
        .runAutomaticIfNeeded();
  }

  void onStartupSignalChanged() {
    unawaited(maybeTrigger());
  }

  ref.listen(prismSyncHandleProvider, (_, _) {
    unawaited(maybeTrigger());
  });
  ref.listen(syncHealthProvider, (_, _) {
    unawaited(maybeTrigger());
  });
  // Re-check when startup auto-config settles; handle and health may already
  // look ready before this local gate drops.
  syncAutoConfigureInProgress.addListener(onStartupSignalChanged);
  ref.onDispose(() {
    syncAutoConfigureInProgress.removeListener(onStartupSignalChanged);
  });
  unawaited(maybeTrigger());

  return null;
});
