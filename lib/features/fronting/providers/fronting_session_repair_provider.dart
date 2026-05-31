import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_session_repair_run_gate.dart';

/// One-shot, best-effort startup sweep that runs
/// [FrontingMutationService.repairMemberSessionInvariants] once per device.
///
/// Why a bootstrap provider (mirrors [pkGroupRepairBootstrapProvider]):
///   * The repair MUST run after the sync engine is configured + healthy, so
///     the closes/merges it performs emit CRDT ops that propagate to peers. A
///     repair run before sync-config would fix the local DB only and leave
///     peers diverged — exactly the failure mode we're fixing.
///   * It MUST NOT run while the per-member fronting migration is mid-flight
///     (the migration gate forbids new-shape writes to `fronting_sessions`).
///   * It runs at most once per device (a persisted [FrontingSessionRepairRunGate]
///     version flag), and is idempotent anyway, so a missed mark just re-runs
///     harmlessly next launch.
///
/// Keep alive from `app.dart` with `ref.listen(...)`, like the other
/// startup sweeps.
final frontingOpenSessionRepairBootstrapProvider = Provider<Object?>((ref) {
  // In-memory latch so the (frequently-firing) listeners don't reload prefs on
  // every signal once the sweep has succeeded this launch.
  var done = false;
  Future<void>? inFlight;

  Future<void> runOnce() async {
    if (done) return;

    // Gate 1: sync engine configured + healthy, so the repair's ops sync.
    if (syncAutoConfigureInProgress.value) return;
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null ||
        ref.read(syncHealthProvider) != SyncHealthState.healthy) {
      return;
    }

    // Gate 2: never touch fronting rows while the per-member migration runs.
    if (ref.read(frontingMigrationGateProvider) !=
        FrontingMigrationGateStatus.complete) {
      return;
    }

    final gate = await FrontingSessionRepairRunGate.load();
    if (!gate.shouldRun) {
      done = true;
      return;
    }

    try {
      final result = await ref
          .read(frontingMutationServiceProvider)
          .repairMemberSessionInvariants();
      if (result.isSuccess) {
        await gate.markCheckedClean(DateTime.now());
        done = true;
      }
      // On failure leave `done` false so a later signal/launch retries.
    } catch (_) {
      // Best-effort: the repair is idempotent, so a retry next launch is safe.
    }
  }

  Future<void> maybeTrigger() {
    final pending = inFlight;
    if (pending != null) return pending;
    final run = runOnce().whenComplete(() => inFlight = null);
    inFlight = run;
    return run;
  }

  void onStartupSignalChanged() => unawaited(maybeTrigger());

  ref.listen(prismSyncHandleProvider, (_, _) => unawaited(maybeTrigger()));
  ref.listen(syncHealthProvider, (_, _) => unawaited(maybeTrigger()));
  ref.listen(
    frontingMigrationGateProvider,
    (_, _) => unawaited(maybeTrigger()),
  );
  // Re-check when startup auto-config settles; handle/health may already look
  // ready before this latch drops.
  syncAutoConfigureInProgress.addListener(onStartupSignalChanged);
  ref.onDispose(
    () => syncAutoConfigureInProgress.removeListener(onStartupSignalChanged),
  );
  unawaited(maybeTrigger());

  return null;
});
