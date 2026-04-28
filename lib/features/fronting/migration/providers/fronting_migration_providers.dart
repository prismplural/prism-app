/// Phase 5C — Riverpod providers driving the per-member fronting upgrade
/// modal and the deferred-state banner.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §2.2 (selective
/// migration UX), §4.1 ("App startup, post-v7 schema"), §4.2 (paired
/// device role detection).
///
/// Three providers ship from this file:
///   - [frontingMigrationModeProvider]: stream of the
///     `system_settings.pending_fronting_migration_mode` sentinel that
///     drives modal/banner visibility.
///   - [pairedDeviceCountProvider]: count of devices in the sync group
///     (excluding self) so the modal can skip the "main device?"
///     question for solo users.
///   - [frontingMigrationRunnerProvider]: thin wrapper around the
///     [FrontingMigrationService] from 5B.  Exists so the modal can
///     invoke the migration without re-deriving its dependencies.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/settings/providers/device_management_provider.dart';

/// Streams the current value of
/// `system_settings.pending_fronting_migration_mode`.
///
/// Possible values (from [FrontingMigrationService]):
///   - `'notStarted'` — v6→v7 upgrade ran; user hasn't seen the modal.
///   - `'deferred'` — user picked "Not now"; banner reminds them.
///   - `'upgradeAndKeep'` / `'startFresh'` — mid-transaction sentinel
///     written before destructive work.  Surfaces as "in progress" in
///     the UI; on next launch we treat it as `notStarted` for retry.
///   - `'blocked'` — v7 onUpgrade detected duplicate `(pluralkit_uuid,
///     member_id)` rows and refused to create the composite index.
///   - `'complete'` — migration done; modal/banner stay hidden.
///
/// Streams via the system_settings DAO so any write — from the
/// migration service or the modal's "Not now" handler — propagates to
/// every watcher without manual invalidation.
final frontingMigrationModeProvider = StreamProvider<String>((ref) {
  final repo = ref.watch(systemSettingsRepositoryProvider);
  // Bridge the domain stream — the SystemSettings model doesn't expose
  // pendingFrontingMigrationMode (it's lifecycle infrastructure, not a
  // user-facing setting), so we read directly off the DAO row instead.
  final dao = ref.watch(databaseProvider).systemSettingsDao;
  // Touch the repo so the stream rebuilds when the singleton row reseeds.
  // ignore: unused_local_variable
  final _ = repo;
  return dao.watchSettings().map((row) => row.pendingFrontingMigrationMode);
});

/// Count of paired peer devices.
///
/// `data: 0` → solo (no peers); the upgrade modal skips the "is this
/// your main device?" step.  `data: > 0` → multi-device; modal asks.
///
/// `loading` / `error` cases are treated as paired (the safer default —
/// we'd rather show the role question to a paired user than miss it).
/// The modal itself blocks on this provider's data state before
/// rendering step 2; if it never resolves, the modal stays on step 1.
///
/// Excludes the current device from the count: [Device.deviceId] equal
/// to the local device id is filtered out.  Sync state being absent
/// (no handle) returns 0.
final pairedDeviceCountProvider = FutureProvider<int>((ref) async {
  final handle = ref.watch(prismSyncHandleProvider).value;
  if (handle == null) return 0;
  // Reuse the existing device list provider — it already handles the
  // FFI listDevices call and credential plumbing.  Errors bubble; the
  // modal treats those as "assume paired."
  final devices = await ref.watch(deviceListProvider.future);
  // The list includes self; conservatively treat any active peers as
  // "paired."  Revoked/stale entries don't count.
  return devices.where((d) => d.isActive).length > 1
      ? devices.where((d) => d.isActive).length - 1
      : 0;
});

/// Wraps [FrontingMigrationService] for the upgrade modal.
///
/// The migration service is constructed on-demand from the database +
/// repositories already exposed by [databaseProviders].  Built as a
/// `Provider` (not a `FutureProvider`) so the modal can `ref.read` it
/// synchronously when the user taps "Continue."
final frontingMigrationRunnerProvider = Provider<FrontingMigrationService>(
  (ref) {
    return FrontingMigrationService(
      db: ref.watch(databaseProvider),
      memberRepository: ref.watch(memberRepositoryProvider),
      frontingSessionRepository:
          ref.watch(frontingSessionRepositoryProvider),
      frontSessionCommentsRepository:
          ref.watch(frontSessionCommentsRepositoryProvider),
      dataExportService: ref.watch(dataExportServiceProvider),
      // Handle may be null when sync isn't configured — the service
      // skips the FFI reset step in that case (solo mode).
      syncHandle: ref.watch(prismSyncHandleProvider).value,
      // Codex P1 #5: wipe platform-keychain credentials after the FFI
      // reset so a backgrounded app between reset and next launch
      // can't re-seed Rust with the credentials that should have been
      // wiped.
      wipeSyncKeychain: wipeFrontingMigrationSyncKeychain,
      // Codex pass 3 P1: resume path uses `clear_sync_state(sync_id)`
      // — surgical storage-only wipe that doesn't touch the engine,
      // so we don't need the configure-briefly hack the previous
      // implementation used (which had a relay-reconnect bug).
      readSyncId: readFrontingMigrationSyncId,
    );
  },
);
