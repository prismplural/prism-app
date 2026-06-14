import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_session_repair_run_gate.dart';

/// Whether the open-session repair may run given the current sync state.
///
/// Two regimes pass: a *synced* device (healthy or reconnecting, with a live
/// handle) whose closes propagate to peers, and an *unpaired* device that
/// repairs local-only. Mid-recovery states, an in-flight migration, and
/// auto-config block it so the repair never touches a half-restored engine.
@visibleForTesting
bool frontingRepairGateAllows({
  required bool autoConfigureInProgress,
  required SyncHealthState health,
  required bool hasHandle,
  required FrontingMigrationGateStatus migrationGate,
}) {
  if (autoConfigureInProgress) return false;
  final isSynced =
      health == SyncHealthState.healthy ||
      health == SyncHealthState.reconnecting;
  if (!isSynced && health != SyncHealthState.unpaired) return false;
  // A synced repair needs a live handle to target; unpaired writes local-only.
  if (isSynced && !hasHandle) return false;
  if (migrationGate != FrontingMigrationGateStatus.complete) return false;
  return true;
}

/// One-shot, best-effort startup sweep that runs
/// [FrontingMutationService.repairMemberSessionInvariants] once per device when
/// [frontingRepairGateAllows].
///
/// Runs at most once per device (a persisted [FrontingSessionRepairRunGate]
/// flag) and is idempotent anyway, so a missed mark just re-runs next launch.
/// Keep alive from `app.dart` with `ref.listen(...)`, like the other startup
/// sweeps.
final frontingOpenSessionRepairBootstrapProvider = Provider<Object?>((ref) {
  // In-memory latch so the (frequently-firing) listeners don't reload prefs on
  // every signal once the sweep has succeeded this launch.
  var done = false;
  Future<void>? inFlight;

  Future<void> runOnce() async {
    if (done) return;

    // On an unpaired device the emit path is credential-gated, so these closes
    // touch only the local DB; pairing later seeds the corrected store. This is
    // how a standalone import (failed pairing) self-heals its zombie opens.
    if (!frontingRepairGateAllows(
      autoConfigureInProgress: syncAutoConfigureInProgress.value,
      health: ref.read(syncHealthProvider),
      hasHandle: ref.read(prismSyncHandleProvider).value != null,
      migrationGate: ref.read(frontingMigrationGateProvider),
    )) {
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
