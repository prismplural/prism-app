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
/// (no resolved handle) returns 0.
///
/// Awaits `prismSyncHandleProvider.future` rather than reading
/// `.value` synchronously: a synchronous read returns `null` while the
/// AsyncNotifier is still resolving on cold open, which would
/// mis-classify a paired install as solo and skip the role question.
/// Loading/error cases now propagate up as failures — the modal's
/// existing `try/catch` falls back to `pairedCount = 1` ("when in
/// doubt, ask").
///
/// The handle future can also resolve to `null` even on configured
/// installs — `prismSyncHandleProvider`'s auto-create path returns
/// `null` if FFI handle construction throws (e.g., transient SQLite
/// or keystore failure on cold open). Treating `null` uniformly as
/// solo would mis-classify a configured-but-broken paired install
/// as solo. We discriminate using the keychain-stored sync_id
/// instead.
///
/// We discriminate with the keychain-stored `prism_sync.sync_id`:
///   - handle null AND sync_id absent → genuinely unpaired, return 0.
///   - handle null AND sync_id present → configured install with a
///     transient handle problem; throw so the modal's existing
///     `try/catch` falls back to `pairedCount = 1` (ask role).
///   - handle non-null → existing logic (count active peers).
///
/// `syncIdProvider` is the right discriminator here because it reads
/// the same keychain slot (`kSyncIdKey`) that gates the auto-create
/// path in `PrismSyncHandleNotifier.build()` — if a sync_id is
/// persisted, this device WAS configured for sync at some point, even
/// if the live handle isn't currently up.
final pairedDeviceCountProvider = FutureProvider<int>((ref) async {
  final handle = await ref.watch(prismSyncHandleProvider.future);
  if (handle == null) {
    final syncId = await ref.watch(syncIdProvider.future);
    if (syncId == null || syncId.isEmpty) {
      // Never paired.
      return 0;
    }
    // Configured but handle is currently null — assume paired and let
    // the modal's catch fall back to `pairedCount = 1`.
    throw StateError(
      'prism sync handle is null but sync_id is configured — '
      'cannot determine paired-device count, defaulting to "ask role".',
    );
  }
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

/// Resolved status of the per-member fronting migration as observed by
/// runtime gates (app shell startup, PK push/poll, sync apply for
/// fronting_sessions / front_session_comments).
///
/// Distinct from the raw `pending_fronting_migration_mode` string: this
/// enum collapses the wire values into the small set of states that
/// callers care about and adds the `repairing` value as an alias for
/// `inProgress` to make intent obvious at the call site.
enum FrontingMigrationGateStatus {
  /// Migration finished successfully. All new-shape paths are safe.
  complete,

  /// Migration has not started or is deferred. The upgrade modal will
  /// surface to the user; runtime new-shape paths must stay read-only
  /// until the user picks a mode.
  needsModal,

  /// v6→v7 onUpgrade detected duplicate `(pluralkit_uuid, member_id)`
  /// rows and refused to install the composite unique index. Until the
  /// user resolves the blocker the legacy single-column unique index
  /// is still in place, so any code path that writes new-shape
  /// fronting rows or runs PK importers can corrupt local state by
  /// hitting the wrong constraint. Hard read-only — Option A in the
  /// remediation plan WS1.
  blocked,

  /// Drift transaction committed; post-tx cleanup (engine reset /
  /// keychain wipe / quarantine clear) hasn't finished. Local data is
  /// already in the new shape but the sync side hasn't been cut over.
  /// Hard read-only on PK push/poll/sync-apply until cleanup completes.
  inProgress,
}

/// Watches [frontingMigrationModeProvider] and resolves it into a
/// [FrontingMigrationGateStatus] for runtime gating.
///
/// Callers should treat any non-[FrontingMigrationGateStatus.complete]
/// result as "do not perform new-shape work." That includes:
///   - PK push (`pushPendingSwitches`, `pushMemberUpdate`).
///   - PK poll / one-shot import (`performOneTimeFullImport`,
///     `performFullImport`, `syncRecentData`).
///   - Sync engine apply path for `fronting_sessions` and
///     `front_session_comments` (see `drift_sync_adapter.dart`).
///   - Any direct fronting-session repository writes initiated by user
///     UI on the home tab while the modal is open.
///
/// Loading / error states from the underlying stream resolve to
/// [FrontingMigrationGateStatus.needsModal] — the safer default,
/// because the upstream provider's failure mode is "DAO read failed"
/// and we'd rather hold off on PK push than risk pushing a row that
/// belongs to the still-unmigrated set.
final frontingMigrationGateProvider =
    Provider<FrontingMigrationGateStatus>((ref) {
  final modeAsync = ref.watch(frontingMigrationModeProvider);
  return modeAsync.when(
    data: (mode) {
      switch (mode) {
        case FrontingMigrationService.modeComplete:
          return FrontingMigrationGateStatus.complete;
        case FrontingMigrationService.modeBlocked:
          return FrontingMigrationGateStatus.blocked;
        case FrontingMigrationService.modeInProgress:
          return FrontingMigrationGateStatus.inProgress;
        // notStarted / deferred / upgradeAndKeep / startFresh all surface
        // as "modal pending" — the modal is the user's recovery path.
        default:
          return FrontingMigrationGateStatus.needsModal;
      }
    },
    loading: () => FrontingMigrationGateStatus.needsModal,
    // ignore: unused_local_variable
    error: (err, stack) => FrontingMigrationGateStatus.needsModal,
  );
});

/// Convenience: true when the gate forbids new-shape writes (PK push,
/// sync apply for fronting tables, etc.). Equivalent to
/// `gate != complete`. Exposed as a separate provider so call sites
/// don't have to pattern-match the enum at the read site.
final frontingMigrationWritesBlockedProvider = Provider<bool>((ref) {
  final gate = ref.watch(frontingMigrationGateProvider);
  return gate != FrontingMigrationGateStatus.complete;
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
      // Wipe platform-keychain credentials after the FFI reset so a
      // backgrounded app between reset and next launch can't re-seed
      // Rust with the credentials that should have been wiped.
      wipeSyncKeychain: wipeFrontingMigrationSyncKeychain,
      // Resume path uses `clear_sync_state(sync_id)` — surgical
      // storage-only wipe that doesn't touch the engine, so we don't
      // need a configure-briefly path that risked a relay reconnect.
      readSyncId: readFrontingMigrationSyncId,
    );
  },
);
