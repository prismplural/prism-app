/// Phase 5B of the per-member fronting refactor — the user-driven
/// app-layer migration transaction.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §4.1 (steps 1-10),
/// §4.2 (sync state reset, primary vs secondary).
///
/// One entry point: [FrontingMigrationService.runMigration]. Called by
/// the upgrade modal (Phase 5C) after the user picks a mode + role.
///
/// File-IO and FFI calls (PRISM1 export, share-sheet, Rust
/// `resetSyncState`) run OUTSIDE the Drift transaction.  The Drift
/// transaction wraps steps 3-10 atomically; on failure inside that
/// block, the local DB rolls back and `pending_fronting_migration_mode`
/// stays at `'notStarted'` so the user can retry.  The PRISM1 file from
/// step 2 is preserved on disk regardless.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:path_provider/path_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';

/// User-selected migration mode from the upgrade modal (5C).
enum MigrationMode {
  /// Preserve SP/native rows in place; fan out multi-member native rows
  /// per spec §4.1 step 4; PK rows go into the PRISM1 rescue file and
  /// then get deleted (re-imported via the new diff-sweep importer).
  upgradeAndKeep,

  /// Delete every fronting row (still produces a PRISM1 backup of the
  /// full local state first).  Skips per-row migration; relies on PK
  /// API + SP re-imports to rebuild the timeline post-migration.
  startFresh,

  /// Defer the migration.  Writes `'deferred'` to settings; no other
  /// side effects.  The upgrade modal will surface a banner reminding
  /// the user; sync stays degraded until they pick a real mode.
  notNow,
}

/// Device's role in the sync group, chosen by the upgrade modal (5C).
///
/// Solo and primary share the full per-row migration path; secondaries
/// skip per-row work and rely on re-pairing with the migrated primary
/// to resync fronting data in the new shape (see spec §4.2).
enum DeviceRole { solo, primary, secondary }

enum MigrationOutcome { success, failed, deferred }

/// Result returned from [FrontingMigrationService.runMigration].
@immutable
class MigrationResult {
  const MigrationResult({
    required this.outcome,
    this.exportFile,
    this.spRowsMigrated = 0,
    this.nativeRowsMigrated = 0,
    this.nativeRowsExpanded = 0,
    this.pkRowsDeleted = 0,
    this.commentsMigrated = 0,
    this.commentsDeleted = 0,
    this.orphanRowsAssignedToSentinel = 0,
    this.unknownSentinelCreated = false,
    this.corruptCoFronterRowIds = const [],
    this.errorMessage,
  });

  final MigrationOutcome outcome;
  final File? exportFile;
  final int spRowsMigrated;
  final int nativeRowsMigrated;

  /// Number of additional per-member rows created by fanning out
  /// multi-member native sessions (spec §4.1 step 4).  Excludes the
  /// primary row (which keeps the legacy id) — this is the count of
  /// NEW rows from the fan-out only.
  final int nativeRowsExpanded;

  final int pkRowsDeleted;
  final int commentsMigrated;
  final int commentsDeleted;
  final int orphanRowsAssignedToSentinel;
  final bool unknownSentinelCreated;

  /// Native row ids whose `co_fronter_ids` JSON failed to parse — fell
  /// back to single-member migration per §6 edge cases.  Surfaced for
  /// user review.
  final List<String> corruptCoFronterRowIds;

  final String? errorMessage;
}

/// Internal: classification bucket for a fronting session row.
enum _SessionKind { pkImported, spImported, nativeNormal, nativeSleep }

class _ClassifiedSession {
  const _ClassifiedSession(this.row, this.kind);
  final FrontingSessionRow row;
  final _SessionKind kind;
}

/// Drift `FrontingSession` row with the legacy v7 columns we still
/// need to read for the migration.  Drift's generated row class is
/// fine, but we copy the relevant fields out so the rest of the file
/// doesn't need to import the generated type explicitly.
class FrontingSessionRow {
  const FrontingSessionRow({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.memberId,
    required this.notes,
    required this.confidence,
    required this.pluralkitUuid,
    required this.coFronterIdsRaw,
    required this.sessionType,
    required this.quality,
    required this.isHealthKitImport,
  });

  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final String? memberId;
  final String? notes;
  final int? confidence;
  final String? pluralkitUuid;
  final String coFronterIdsRaw; // JSON list, possibly malformed
  final int sessionType; // 0 = normal, 1 = sleep
  final int? quality;
  final bool isHealthKitImport;
}

class FrontingMigrationService {
  FrontingMigrationService({
    required this.db,
    required this.memberRepository,
    required this.frontingSessionRepository,
    required this.frontSessionCommentsRepository,
    required this.dataExportService,
    required this.syncHandle,
    Future<void> Function(ffi.PrismSyncHandle handle)? resetSyncState,
    Future<void> Function(ffi.PrismSyncHandle handle, String syncId)?
        clearSyncState,
    Future<String?> Function()? readSyncId,
    Future<void> Function()? wipeSyncKeychain,
    Future<Directory> Function()? backupDirectoryProvider,
  })  : _resetSyncState = resetSyncState ??
            ((handle) => ffi.resetSyncState(handle: handle)),
        _clearSyncState = clearSyncState ??
            ((handle, syncId) => ffi.clearSyncState(
                  handle: handle,
                  syncId: syncId,
                  forceActive: false,
                )),
        _readSyncId = readSyncId ?? (() async => null),
        _wipeSyncKeychain = wipeSyncKeychain ?? (() async {}),
        _backupDirectoryProvider =
            backupDirectoryProvider ?? getApplicationDocumentsDirectory;

  final AppDatabase db;
  final MemberRepository memberRepository;
  final FrontingSessionRepository frontingSessionRepository;
  final FrontSessionCommentsRepository frontSessionCommentsRepository;
  final DataExportService dataExportService;

  /// Opaque Rust handle.  Nullable so unit tests can run without
  /// initializing an FFI handle — when null we skip the engine reset
  /// step but still wipe `sync_quarantine` (host-side table).
  final ffi.PrismSyncHandle? syncHandle;

  /// Indirection so tests can inject a fake.  In production this is the
  /// generated `ffi.resetSyncState(handle: handle)`.  Must be passed
  /// `handle` as a positional arg by the wrapper.
  ///
  /// Used by the FIRST-attempt destructive path
  /// ([runMigrationDestructive]) where the engine is configured and we
  /// need both the storage wipe AND the in-memory teardown
  /// (`OpEmitter`, device keys, auto-sync abort).
  final Future<void> Function(ffi.PrismSyncHandle handle) _resetSyncState;

  /// Storage-only sync wipe by sync_id, no engine configuration required.
  ///
  /// Used by [resumeCleanup] when the previous attempt's `reset_sync_state`
  /// either never started or failed before persisting `substateResetDone`.
  /// On the resume path the published handle is UNCONFIGURED (see startup
  /// gate in `prism_sync_providers.dart`) — `reset_sync_state` would
  /// fail with "sync_id not set" because it queries the live engine.
  /// `clear_sync_state` takes the sync_id explicitly and wipes the same
  /// underlying storage rows without touching the engine, sidestepping
  /// the configure-then-reset dance entirely.
  ///
  /// Defaults to the generated `ffi.clearSyncState(...)`. The sync_id
  /// is sourced from [_readSyncId].
  final Future<void> Function(ffi.PrismSyncHandle handle, String syncId)
      _clearSyncState;

  /// Reads the persisted sync_id from the platform keychain.
  ///
  /// Returns null when no sync_id is stored (solo-device case, or the
  /// keychain wipe step has already run). The resume path treats a null
  /// sync_id as "nothing left to clear" and advances substate so the
  /// remaining cleanup steps (keychain wipe, quarantine clear, mark
  /// complete) run on the next attempt.
  ///
  /// Defaults to a no-op returning null so unit tests that don't exercise
  /// the resume path don't need to inject anything. Production wiring
  /// passes `readFrontingMigrationSyncId` from `prism_sync_providers.dart`.
  final Future<String?> Function() _readSyncId;

  /// Wipes platform-keychain sync credentials. Defaults to a no-op so unit
  /// tests don't need a `FlutterSecureStorage` instance; production wiring
  /// in `frontingMigrationRunnerProvider` passes
  /// `wipeFrontingMigrationSyncKeychain` (top-level helper in
  /// `prism_sync_providers.dart`). Codex P1 #5: without this, a backgrounded
  /// app between `_resetSyncState` and the next launch would re-seed Rust
  /// from the keychain entries that should have been wiped.
  final Future<void> Function() _wipeSyncKeychain;

  /// Where the PRISM1 rescue backup is written by [prepareBackup]. Defaults
  /// to `getApplicationDocumentsDirectory()` so the file survives across
  /// app launches even if the user dismisses the upgrade modal before
  /// confirming. Codex P1 #8: cache (the previous default) is purgeable
  /// by the OS or user without warning, leaving the user with no
  /// recoverable backup if they proceeded to the destructive phase.
  final Future<Directory> Function() _backupDirectoryProvider;

  /// Sentinel string written to `system_settings.pending_fronting_migration_mode`.
  static const String modeNotStarted = 'notStarted';
  static const String modeDeferred = 'deferred';
  static const String modeUpgradeAndKeep = 'upgradeAndKeep';
  static const String modeStartFresh = 'startFresh';

  /// Codex P1 #4. Written BEFORE the Drift transaction commits and BEFORE
  /// the post-tx steps (FFI reset, keychain wipe, sync_quarantine clear).
  /// Stays set until the post-tx steps all succeed; if any of them fail,
  /// the user can resume via [resumeCleanup] from the upgrade modal.
  static const String modeInProgress = 'inProgress';

  static const String modeComplete = 'complete';

  /// Codex pass 2 #B-NEW3 — values for
  /// `system_settings.pending_fronting_migration_cleanup_substate`.
  /// `''` is the inert default (no destructive post-tx step has run yet);
  /// [substateResetDone] is written ONLY after `_resetSyncState` returns
  /// success and before the keychain wipe / quarantine clear / mark
  /// complete sequence runs.
  static const String substateInert = '';
  static const String substateResetDone = 'resetDone';

  /// Phase 1 of the upgrade: build the PRISM1 backup file. No destructive
  /// work runs here, settings are not touched. Throws on export failure;
  /// the caller should surface the error and leave settings at
  /// `notStarted` so the user can retry.
  ///
  /// Codex P1 #8: writes to `getApplicationDocumentsDirectory()` (or the
  /// injected [_backupDirectoryProvider]) instead of cache so the file
  /// survives across app launches even if the user dismisses the upgrade
  /// modal between this and [runMigrationDestructive]. The user can then
  /// recover the file via the platform Files app / file manager.
  Future<File> prepareBackup({
    required MigrationMode mode,
    required String password,
  }) async {
    if (mode == MigrationMode.notNow) {
      throw StateError(
        'prepareBackup is not valid for MigrationMode.notNow — call '
        'runMigration directly for the deferred path.',
      );
    }
    final dir = await _backupDirectoryProvider();
    return dataExportService.exportEncryptedData(
      password: password,
      includeLegacyFields: true,
      targetDirectory: dir,
    );
  }

  /// Phase 2 of the upgrade: run the destructive Drift transaction +
  /// post-tx cleanup (engine reset, keychain wipe, quarantine clear).
  ///
  /// The caller MUST have already produced [exportFile] via
  /// [prepareBackup] AND surfaced it to the user with explicit
  /// acknowledgment that they saved it somewhere durable (see
  /// `FrontingUpgradeSheet.backupReady`). Calling this without that
  /// gate risks leaving the user with no recoverable backup.
  ///
  /// On failure inside the Drift transaction, settings stay at the
  /// prior value and the caller can retry. On failure of a post-tx
  /// step, settings stay at `'inProgress'` and the user can recover
  /// via [resumeCleanup].
  Future<MigrationResult> runMigrationDestructive({
    required MigrationMode mode,
    required DeviceRole role,
    required File exportFile,
  }) async {
    // Steps 3-7: wrap in a single Drift transaction. Codex P1 #3:
    // Repository writes inside this block run with `SyncRecordMixin`
    // emission SUPPRESSED so they don't push CRDT ops to the Rust
    // engine. Those ops would commit to Rust's SEPARATE SQLite store
    // (Drift can't roll them back), and auto-sync would push them to
    // peers BEFORE step 8's `reset_sync_state` runs. Suppression keeps
    // Rust's pending_ops untouched until the cutover.
    //
    // Migration mode is written OUTSIDE the transaction (Codex P1 #4)
    // so the post-tx steps' failure mode — engine reset, keychain
    // wipe, quarantine clear — remains recoverable via [resumeCleanup]
    // when the user re-opens the app. If we wrote `inProgress` inside
    // the tx, a Drift rollback would erase it and the user would be
    // back on `notStarted` even though the actual mid-tx commit work
    // had been suppressed.
    _MigrationCounters counters;
    try {
      counters = await SyncRecordMixin.suppress(() {
        return db.transaction<_MigrationCounters>(() async {
          switch (role) {
            case DeviceRole.secondary:
              // Spec §4.1 final paragraph: secondaries skip per-row
              // work and just truncate.  Re-pairing with the migrated
              // primary resyncs the data in new shape.
              return _runSecondary();
            case DeviceRole.solo:
            case DeviceRole.primary:
              return _runPrimaryOrSolo(mode);
          }
        });
      });
    } catch (e) {
      // Drift rolled back; settings still at the prior value
      // (typically `notStarted`). Suppression also cleared on the way
      // out via the `suppress` finally block.
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Migration transaction failed: $e',
      );
    }

    // Mark in-progress AFTER the Drift tx commits, BEFORE the post-tx
    // cleanup steps. If any of those fail, the user can resume via
    // [resumeCleanup] — surfaced by the upgrade modal as a "Finish
    // migration" entry. App startup also checks for this marker and
    // skips Rust seeding/configuration so a backgrounded app between
    // reset and keychain wipe doesn't re-seed credentials about to be
    // wiped.
    await db.systemSettingsDao
        .writePendingFrontingMigrationMode(modeInProgress);

    return _runPostTransactionCleanup(
      exportFile: exportFile,
      counters: counters,
    );
  }

  /// Compatibility wrapper used by the `notNow` deferral path and
  /// covering tests that don't exercise the durable-backup gate.
  ///
  /// For [MigrationMode.notNow] this writes the `'deferred'` marker and
  /// returns immediately — the only path that should hit
  /// `runMigration` in production. For other modes it composes
  /// [prepareBackup] + [runMigrationDestructive] in sequence; the
  /// upgrade modal calls those two methods directly with the
  /// backup-ready acknowledgment step in between, so production never
  /// reaches this fallback path.
  ///
  /// [shareFile] is invoked between the two phases. Its return value is
  /// not inspected — callers that need the durable-save gate must drive
  /// the two phases manually (see `FrontingUpgradeSheet`).
  Future<MigrationResult> runMigration({
    required MigrationMode mode,
    required DeviceRole role,
    required Future<Uri?> Function(File file) shareFile,
    String password = '',
  }) async {
    if (mode == MigrationMode.notNow) {
      // No destructive work — just write the deferred marker.
      await db.systemSettingsDao
          .writePendingFrontingMigrationMode(modeDeferred);
      return const MigrationResult(outcome: MigrationOutcome.deferred);
    }

    File exportFile;
    try {
      exportFile = await prepareBackup(mode: mode, password: password);
    } catch (e) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        errorMessage: 'PRISM1 export failed: $e',
      );
    }

    try {
      await shareFile(exportFile);
    } catch (e) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Share-sheet failed: $e',
      );
    }

    return runMigrationDestructive(
      mode: mode,
      role: role,
      exportFile: exportFile,
    );
  }

  /// Resume the post-Drift-transaction cleanup steps after a partial
  /// failure. Settings must already be at [modeInProgress] — the
  /// upgrade modal calls this when it re-opens to that state.
  ///
  /// Skips the Drift transaction entirely (already committed); runs
  /// just the engine reset (when not already done), keychain wipe,
  /// sync_quarantine clear, and final mode write.
  ///
  /// Codex pass 2 #B-NEW3 + pass 3 P1: reads
  /// `pending_fronting_migration_cleanup_substate` to decide whether
  /// the Rust reset still needs to run. When the substate is
  /// [substateResetDone] we KNOW the previous attempt's Rust reset
  /// returned success — skip the FFI call entirely. When the substate
  /// is the inert default we MUST run a clear; the handle is
  /// unconfigured (app startup gates that detect `inProgress` publish
  /// an unconfigured handle), so we use `clear_sync_state(sync_id)`
  /// which operates on storage directly without touching the engine.
  /// This sidesteps the configure-briefly hack the previous
  /// implementation used (which had a relay-reconnect bug).
  Future<MigrationResult> resumeCleanup() async {
    final currentMode =
        await db.systemSettingsDao.readPendingFrontingMigrationMode();
    if (currentMode != modeInProgress) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        errorMessage:
            'resumeCleanup() called with mode=$currentMode (expected '
            '$modeInProgress). Nothing to do.',
      );
    }
    return _runPostTransactionCleanup(
      exportFile: null,
      counters: _MigrationCounters(),
      isResume: true,
    );
  }

  /// Step 8 (engine reset) + 8b (keychain wipe) + 8c (quarantine
  /// clear) + 10 (mark complete). Shared between the first-attempt
  /// path and [resumeCleanup]; on any failure the in-progress marker
  /// stays set so the user can retry without losing progress.
  ///
  /// Codex pass 2 #B-NEW3: writes
  /// `pending_fronting_migration_cleanup_substate = 'resetDone'`
  /// between Rust reset success and the keychain wipe so a second
  /// invocation (via [resumeCleanup]) can skip the reset call instead
  /// of relying on the "sync_id not set" heuristic — which in the
  /// failure mode this fixes was erroneously treating "engine never
  /// configured because Rust persistent state was never cleared" as
  /// "reset already succeeded."
  Future<MigrationResult> _runPostTransactionCleanup({
    required File? exportFile,
    required _MigrationCounters counters,
    bool isResume = false,
  }) async {
    final substate = await db.systemSettingsDao
        .readPendingFrontingMigrationCleanupSubstate();
    final resetAlreadyDone = substate == substateResetDone;

    // Step 8: reset sync state (Rust FFI). Skipped when the persisted
    // substate proves the previous attempt's reset returned success.
    if (syncHandle != null && !resetAlreadyDone) {
      // First-attempt path: engine IS configured (this runs immediately
      // after the destructive Drift transaction, before the startup gate
      // could trigger). Use `reset_sync_state` for the full teardown:
      // storage wipe + in-memory teardown (`OpEmitter`, device keys,
      // auto-sync abort).
      //
      // Resume path: published handle is UNCONFIGURED (startup gate
      // skipped seedRustStore + autoConfigureIfReady on `inProgress`).
      // Use `clear_sync_state(sync_id)` — it operates on storage
      // directly without touching the engine, so we don't need to
      // configure-then-reset (the previous configure-briefly path
      // had a relay-reconnect bug: configureEngine constructs the
      // relay AND calls connect_websocket BEFORE the reset runs,
      // which contradicts the no-relay-round-trip requirement and
      // could briefly reconnect to the still-paired old sync group).
      if (isResume) {
        final syncId = await _readSyncId();
        if (syncId == null) {
          // Either solo (never had a sync_id) or the keychain wipe
          // step from a prior attempt already ran. Either way there's
          // nothing left to clear in the sync DB — advance the
          // substate so the remaining cleanup steps proceed.
          await db.systemSettingsDao
              .writePendingFrontingMigrationCleanupSubstate(substateResetDone);
        } else {
          try {
            await _clearSyncState(syncHandle!, syncId);
          } catch (e) {
            return _failPostTx(
              exportFile: exportFile,
              counters: counters,
              errorMessage:
                  'Sync state clear failed: $e. Please reopen the upgrade '
                  'modal to finish migration.',
            );
          }
          await db.systemSettingsDao
              .writePendingFrontingMigrationCleanupSubstate(substateResetDone);
        }
      } else {
        try {
          await _resetSyncState(syncHandle!);
        } catch (e) {
          return _failPostTx(
            exportFile: exportFile,
            counters: counters,
            errorMessage:
                'Engine reset failed: $e. Please reopen the upgrade modal '
                'to finish migration.',
          );
        }
        // Persist the success of the FFI reset BEFORE moving on to the
        // keychain wipe. If the wipe (or any subsequent step) fails and
        // we re-run via [resumeCleanup], we need to know that the Rust
        // persistent state is already cleared — otherwise resume would
        // call clear_sync_state against an empty/missing sync_id and
        // possibly mis-classify state.
        await db.systemSettingsDao
            .writePendingFrontingMigrationCleanupSubstate(substateResetDone);
      }
    }

    // Step 8b: wipe the platform keychain. Codex P1 #5: without this,
    // a fresh app launch would re-seed Rust from the still-present
    // wrapped_dek/sync_id/device_secret/etc. and silently re-attach to
    // the OLD sync group. Idempotent — wiping already-wiped slots is
    // a no-op.
    try {
      await _wipeSyncKeychain();
    } catch (e) {
      return _failPostTx(
        exportFile: exportFile,
        counters: counters,
        errorMessage:
            'Sync keychain wipe failed: $e. Please reopen the upgrade '
            'modal to finish migration.',
      );
    }

    // Step 8c: truncate `sync_quarantine` (host-side Drift table —
    // not covered by `reset_sync_state`). Idempotent.
    try {
      await db.syncQuarantineDao.clearAll();
    } catch (e) {
      return _failPostTx(
        exportFile: exportFile,
        counters: counters,
        errorMessage:
            'Sync quarantine clear failed: $e. Please reopen the upgrade '
            'modal to finish migration.',
      );
    }

    // Step 10: mark complete. Reset the cleanup substate back to the
    // inert default so a subsequent (rare) re-run after `complete`
    // doesn't carry over stale state — though `resumeCleanup()` itself
    // refuses to run unless mode is `inProgress`.
    await db.systemSettingsDao
        .writePendingFrontingMigrationMode(modeComplete);
    await db.systemSettingsDao
        .writePendingFrontingMigrationCleanupSubstate(substateInert);

    return MigrationResult(
      outcome: MigrationOutcome.success,
      exportFile: exportFile,
      spRowsMigrated: counters.spRowsMigrated,
      nativeRowsMigrated: counters.nativeRowsMigrated,
      nativeRowsExpanded: counters.nativeRowsExpanded,
      pkRowsDeleted: counters.pkRowsDeleted,
      commentsMigrated: counters.commentsMigrated,
      commentsDeleted: counters.commentsDeleted,
      orphanRowsAssignedToSentinel: counters.orphanRowsAssignedToSentinel,
      unknownSentinelCreated: counters.unknownSentinelCreated,
      corruptCoFronterRowIds: counters.corruptCoFronterRowIds,
    );
  }

  MigrationResult _failPostTx({
    required File? exportFile,
    required _MigrationCounters counters,
    required String errorMessage,
  }) {
    return MigrationResult(
      outcome: MigrationOutcome.failed,
      exportFile: exportFile,
      spRowsMigrated: counters.spRowsMigrated,
      nativeRowsMigrated: counters.nativeRowsMigrated,
      nativeRowsExpanded: counters.nativeRowsExpanded,
      pkRowsDeleted: counters.pkRowsDeleted,
      commentsMigrated: counters.commentsMigrated,
      commentsDeleted: counters.commentsDeleted,
      orphanRowsAssignedToSentinel: counters.orphanRowsAssignedToSentinel,
      unknownSentinelCreated: counters.unknownSentinelCreated,
      corruptCoFronterRowIds: counters.corruptCoFronterRowIds,
      errorMessage: errorMessage,
    );
  }

  // -------------------------------------------------------------------
  // Primary / solo path (full §4.1 steps 3-7 + 9)
  // -------------------------------------------------------------------

  Future<_MigrationCounters> _runPrimaryOrSolo(MigrationMode mode) async {
    // Step 1: read + classify all rows.
    final allRows = await _readAllSessions();
    final spSessionIds = await _readSpSessionIds();
    final classified = _classify(allRows, spSessionIds);

    // Step 5 setup: read all comment rows BEFORE deletes so we can
    // join them back to their (about-to-be-deleted) parents.  We need
    // `session_id`, `body`, `timestamp`, `created_at`.
    final allComments = await _readAllComments();

    if (mode == MigrationMode.startFresh) {
      // Step 6: delete every fronting row + every comment.  We still
      // need to read the rows first to issue per-row `syncRecordDelete`
      // so tombstones emit (the wipe at step 8 nukes those tombstones,
      // but the local Drift `is_deleted` flips correctly).
      var commentsDeleted = 0;
      for (final c in allComments) {
        await frontSessionCommentsRepository.deleteComment(c.id);
        commentsDeleted++;
      }
      var pkRowsDeleted = 0;
      for (final r in allRows) {
        await frontingSessionRepository.deleteSession(r.id);
        pkRowsDeleted++;
      }
      return _MigrationCounters(pkRowsDeleted: pkRowsDeleted)
        ..commentsDeleted = commentsDeleted;
    }

    // upgradeAndKeep path -------------------------------------------
    final counters = _MigrationCounters();

    // Step 3: SP-imported rows.  Already 1:1 per-member; just emit a
    // v2 entity op so the new-shape sync schema picks them up.
    for (final c in classified) {
      if (c.kind != _SessionKind.spImported) continue;
      await frontingSessionRepository
          .updateSession(_rowToDomain(c.row));
      counters.spRowsMigrated++;
    }

    // Step 4: native rows (normal + sleep).  Sleep keeps nullable
    // member_id and migrates 1:1.  Normal single-member migrates 1:1.
    // Normal multi-member: primary keeps legacy id; co-fronters get
    // deterministic v5 ids from migrationFrontingNamespace.
    final orphans = <FrontingSessionRow>[];
    for (final c in classified) {
      switch (c.kind) {
        case _SessionKind.pkImported:
        case _SessionKind.spImported:
          continue;
        case _SessionKind.nativeSleep:
          await frontingSessionRepository
              .updateSession(_rowToDomain(c.row));
          counters.nativeRowsMigrated++;
          continue;
        case _SessionKind.nativeNormal:
          break;
      }

      final row = c.row;
      // Parse co-fronter list, falling back to single-member on
      // corrupt JSON (§6 edge case).
      List<String> coFronters;
      var corrupt = false;
      try {
        final decoded = jsonDecode(row.coFronterIdsRaw);
        coFronters = decoded is List
            ? decoded.whereType<String>().toList()
            : const <String>[];
      } catch (_) {
        corrupt = true;
        coFronters = const <String>[];
        counters.corruptCoFronterRowIds.add(row.id);
      }

      // Detect orphans (member_id NULL on a normal row): handle
      // separately at step 7 so we only create the sentinel when
      // there's at least one orphan.
      if (row.memberId == null) {
        orphans.add(row);
        continue;
      }

      // Migrate the primary row in place.
      await frontingSessionRepository.updateSession(_rowToDomain(row));
      counters.nativeRowsMigrated++;

      // Skip fan-out on corrupt JSON (we already counted the row).
      if (corrupt) continue;

      // Fan out additional co-fronters into new per-member rows.
      for (final coId in coFronters) {
        if (coId == row.memberId) continue; // sanity guard
        final derivedId = deriveMigrationFanoutSessionId(row.id, coId);
        // Use createSession so a v2 op emits.  CRDT field-LWW + the
        // composite (pluralkit_uuid, member_id) index are bug
        // protection; deterministic ids are correctness on concurrent
        // migrations across paired devices (§4.5 + §4.1 step 4).
        await frontingSessionRepository.createSession(
          FrontingSession(
            id: derivedId,
            startTime: row.startTime,
            endTime: row.endTime,
            memberId: coId,
            notes: row.notes,
            confidence: _intToConfidence(row.confidence),
            pluralkitUuid: null, // native rows never carry one
            sessionType: SessionType.normal,
          ),
        );
        counters.nativeRowsExpanded++;
      }
    }

    // Step 5: comments.  Walk every comment, look up its parent
    // session by legacy `session_id`, decide preserve-or-delete.
    //
    // Preserved comments use `updateComment` (NOT create) so the row
    // id stays stable and the comments DAO's plain `insert` doesn't
    // collide.  The update emits a v2 entity op carrying the new
    // `target_time` + `author_member_id` fields; the legacy
    // `session_id` column on disk stays in place (the v8 schema
    // rebuild drops it later — until then the comments mapper writes
    // the empty-string sentinel on every new insert anyway).
    final byParent = <String, FrontingSessionRow>{
      for (final r in allRows) r.id: r,
    };
    final pkParentIds = <String>{
      for (final c in classified)
        if (c.kind == _SessionKind.pkImported) c.row.id,
    };
    for (final cmt in allComments) {
      final parent = byParent[cmt.sessionId];
      final parentIsPk = parent != null && pkParentIds.contains(parent.id);
      if (parent == null || parentIsPk) {
        // Parent missing or wiped — drop the comment.  `parent ==
        // null` covers comments whose legacy session_id was empty
        // (e.g., already-migrated rows from a failed earlier attempt)
        // or pointed at a deleted session.
        await frontSessionCommentsRepository.deleteComment(cmt.id);
        counters.commentsDeleted++;
        continue;
      }

      // Migrate comment in place to new shape, anchored at the LEGACY
      // `timestamp` column (NOT createdAt — see spec warning §4.1
      // step 5).  Author is the parent session's member_id (may be
      // null for orphan/sleep parents — comments tolerate that).
      await frontSessionCommentsRepository.updateComment(
        FrontSessionComment(
          id: cmt.id,
          body: cmt.body,
          timestamp: cmt.timestamp,
          createdAt: cmt.createdAt,
          targetTime: cmt.timestamp,
          authorMemberId: parent.memberId,
        ),
      );
      counters.commentsMigrated++;
    }

    // Step 7: orphan handling.  Create the Unknown sentinel only if
    // there's at least one orphan to assign.  The shared
    // `ensureUnknownSentinelMember` helper is idempotent (returns
    // wasCreated=false if a prior failed attempt already created it).
    if (orphans.isNotEmpty) {
      final ensured = await memberRepository.ensureUnknownSentinelMember();
      if (ensured.wasCreated) {
        counters.unknownSentinelCreated = true;
      }
      final sentinelId = ensured.member.id;
      for (final r in orphans) {
        await frontingSessionRepository.updateSession(
          FrontingSession(
            id: r.id,
            startTime: r.startTime,
            endTime: r.endTime,
            memberId: sentinelId,
            notes: r.notes,
            confidence: _intToConfidence(r.confidence),
            pluralkitUuid: r.pluralkitUuid,
            sessionType: SessionType.normal,
          ),
        );
        counters.orphanRowsAssignedToSentinel++;
      }
    }

    // Step 6: delete PK-imported rows.  Done LAST among the per-row
    // steps so the comment join above could still find PK parents.
    for (final c in classified) {
      if (c.kind != _SessionKind.pkImported) continue;
      await frontingSessionRepository.deleteSession(c.row.id);
      counters.pkRowsDeleted++;
    }

    // Step 9: explicitly DO NOT clear `sp_id_map` rows with
    // entityType='session'.  The SP re-importer needs the lookup.

    return counters;
  }

  // -------------------------------------------------------------------
  // Secondary path (no per-row migration; just truncate)
  // -------------------------------------------------------------------

  Future<_MigrationCounters> _runSecondary() async {
    // Truncate `fronting_sessions` and `front_session_comments`.
    // Direct SQL because we want the entire table gone, not soft-
    // delete tombstones (those would re-emit via sync ops on next
    // pair, defeating the purpose).  The sync state wipe (step 8)
    // happens after the transaction commits.
    await db.customStatement('DELETE FROM fronting_sessions');
    await db.customStatement('DELETE FROM front_session_comments');
    return _MigrationCounters();
  }

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  Future<List<FrontingSessionRow>> _readAllSessions() async {
    // Use customSelect to read the legacy `co_fronter_ids` column —
    // the freezed FrontingSession model no longer exposes it.
    final rows = await db
        .customSelect(
          'SELECT id, start_time, end_time, member_id, notes, confidence, '
          'pluralkit_uuid, co_fronter_ids, session_type, quality, '
          'is_health_kit_import '
          'FROM fronting_sessions WHERE is_deleted = 0',
        )
        .get();
    return rows.map((r) {
      return FrontingSessionRow(
        id: r.read<String>('id'),
        startTime: r.read<DateTime>('start_time'),
        endTime: r.read<DateTime?>('end_time'),
        memberId: r.read<String?>('member_id'),
        notes: r.read<String?>('notes'),
        confidence: r.read<int?>('confidence'),
        pluralkitUuid: r.read<String?>('pluralkit_uuid'),
        coFronterIdsRaw: r.read<String?>('co_fronter_ids') ?? '[]',
        sessionType: r.read<int>('session_type'),
        quality: r.read<int?>('quality'),
        isHealthKitImport: r.read<bool>('is_health_kit_import'),
      );
    }).toList();
  }

  Future<List<_LegacyComment>> _readAllComments() async {
    final rows = await db
        .customSelect(
          'SELECT id, session_id, body, timestamp, created_at '
          'FROM front_session_comments WHERE is_deleted = 0',
        )
        .get();
    return rows
        .map((r) => _LegacyComment(
              id: r.read<String>('id'),
              sessionId: r.read<String?>('session_id') ?? '',
              body: r.read<String>('body'),
              timestamp: r.read<DateTime>('timestamp'),
              createdAt: r.read<DateTime>('created_at'),
            ))
        .toList();
  }

  Future<Set<String>> _readSpSessionIds() async {
    final rows = await db
        .customSelect(
          "SELECT prism_id FROM sp_id_map WHERE entity_type = 'session'",
        )
        .get();
    return rows.map((r) => r.read<String>('prism_id')).toSet();
  }

  List<_ClassifiedSession> _classify(
    List<FrontingSessionRow> rows,
    Set<String> spSessionIds,
  ) {
    return [
      for (final r in rows)
        _ClassifiedSession(
          r,
          _classifyOne(r, spSessionIds),
        ),
    ];
  }

  _SessionKind _classifyOne(
    FrontingSessionRow r,
    Set<String> spSessionIds,
  ) {
    if (r.pluralkitUuid != null && r.pluralkitUuid!.isNotEmpty) {
      return _SessionKind.pkImported;
    }
    if (spSessionIds.contains(r.id)) return _SessionKind.spImported;
    if (r.sessionType == SessionType.sleep.index) {
      return _SessionKind.nativeSleep;
    }
    return _SessionKind.nativeNormal;
  }

  FrontingSession _rowToDomain(FrontingSessionRow r) {
    return FrontingSession(
      id: r.id,
      startTime: r.startTime,
      endTime: r.endTime,
      memberId: r.memberId,
      notes: r.notes,
      confidence: _intToConfidence(r.confidence),
      pluralkitUuid: r.pluralkitUuid,
      sessionType: r.sessionType == SessionType.sleep.index
          ? SessionType.sleep
          : SessionType.normal,
      quality: r.quality != null &&
              r.quality! >= 0 &&
              r.quality! < SleepQuality.values.length
          ? SleepQuality.values[r.quality!]
          : null,
      isHealthKitImport: r.isHealthKitImport,
    );
  }

  FrontConfidence? _intToConfidence(int? v) {
    if (v == null) return null;
    if (v < 0 || v >= FrontConfidence.values.length) return null;
    return FrontConfidence.values[v];
  }
}

class _LegacyComment {
  const _LegacyComment({
    required this.id,
    required this.sessionId,
    required this.body,
    required this.timestamp,
    required this.createdAt,
  });

  final String id;
  final String sessionId; // legacy FK; may be empty for already-migrated rows
  final String body;
  final DateTime timestamp;
  final DateTime createdAt;
}

class _MigrationCounters {
  _MigrationCounters({
    this.pkRowsDeleted = 0,
  });

  int spRowsMigrated = 0;
  int nativeRowsMigrated = 0;
  int nativeRowsExpanded = 0;
  int pkRowsDeleted;
  int commentsMigrated = 0;
  int commentsDeleted = 0;
  int orphanRowsAssignedToSentinel = 0;
  bool unknownSentinelCreated = false;
  final List<String> corruptCoFronterRowIds = <String>[];
}
