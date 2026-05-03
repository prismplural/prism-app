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
///
/// Atomicity note: the [modeInProgress] sentinel is written as the FIRST
/// statement inside the destructive Drift transaction so the marker and
/// the migrated rows commit (or roll back) atomically. A crash between
/// "data fanned out" and "marker stamped" is no longer possible — the
/// only crash window left is between the transaction commit and the
/// post-tx steps (engine reset / keychain wipe / quarantine clear),
/// which is recoverable via [resumeCleanup].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show TableUpdate;
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
import 'package:prism_plurality/features/fronting/services/merge_adjacent_same_member_rows.dart';

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
}

/// Device's role in the sync group, chosen by the upgrade modal (5C).
///
/// Solo and primary share the full per-row migration path; secondaries
/// skip per-row work and rely on re-pairing with the migrated primary
/// to resync fronting data in the new shape (see spec §4.2).
enum DeviceRole { solo, primary, secondary }

enum MigrationOutcome { success, failed }

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
    this.adjacentMergesPerformed = 0,
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

  /// Number of adjacent same-member rows folded into an earlier row by
  /// the post-fan-out merge pass (spec §2.1 — old-shape session
  /// boundaries become arbitrary cosmetic artifacts under the
  /// per-member abstraction). Counts the soft-deleted "later" rows;
  /// the surviving "earlier" row stays put with its end_time extended.
  final int adjacentMergesPerformed;

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

/// Thrown by [FrontingMigrationService.prepareBackup] when the freshly
/// derived rescue filename already exists on disk. Surfacing this as a
/// typed error rather than silently overwriting protects the previous
/// attempt's PRISM1 file — that file is the only recovery path for a
/// user whose retry is itself broken.
class BackupFileCollisionException implements Exception {
  BackupFileCollisionException(this.path);

  /// Absolute path of the file we refused to overwrite.
  final String path;

  @override
  String toString() =>
      'BackupFileCollisionException: refused to overwrite existing rescue '
      'file at $path';
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
    Future<void> Function()? midTransactionFailpoint,
    Future<void> Function()? postTransactionFailpoint,
    DateTime Function()? clock,
    Random? nonceRandom,
  }) : _resetSyncState =
           resetSyncState ?? ((handle) => ffi.resetSyncState(handle: handle)),
       _clearSyncState =
           clearSyncState ??
           ((handle, syncId) => ffi.clearSyncState(
             handle: handle,
             syncId: syncId,
             forceActive: false,
           )),
       _readSyncId = readSyncId ?? (() async => null),
       _wipeSyncKeychain = wipeSyncKeychain ?? (() async {}),
       _backupDirectoryProvider =
           backupDirectoryProvider ?? getApplicationDocumentsDirectory,
       _midTransactionFailpoint = midTransactionFailpoint,
       _postTransactionFailpoint = postTransactionFailpoint,
       _clock = clock ?? DateTime.now,
       _nonceRandom = nonceRandom ?? Random.secure();

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
  /// `prism_sync_providers.dart`). Without this, a backgrounded app between
  /// `_resetSyncState` and the next launch would re-seed Rust from the
  /// keychain entries that should have been wiped.
  final Future<void> Function() _wipeSyncKeychain;

  /// Where the PRISM1 rescue backup is written by [prepareBackup]. Defaults
  /// to `getApplicationDocumentsDirectory()` so the file survives across
  /// app launches even if the user dismisses the upgrade modal before
  /// confirming. The cache directory is purgeable by the OS or user
  /// without warning, which would leave the user with no recoverable
  /// backup if they proceeded to the destructive phase.
  final Future<Directory> Function() _backupDirectoryProvider;

  /// Test-only hook fired inside the destructive Drift transaction
  /// AFTER `modeInProgress` is stamped and BEFORE the destructive
  /// fan-out runs. Throwing from this callback exercises the
  /// transaction-rollback path (mode and data both revert).
  final Future<void> Function()? _midTransactionFailpoint;

  /// Test-only hook fired AFTER the Drift transaction commits and
  /// BEFORE any post-tx step runs (engine reset / keychain wipe /
  /// quarantine clear). Throwing from this callback exercises the
  /// resume-cleanup path (transaction stays committed; mode stays
  /// `inProgress`; user can re-enter the modal to finish).
  final Future<void> Function()? _postTransactionFailpoint;

  /// Wall-clock source. Override in tests so backup filename suffixes
  /// are deterministic.
  final DateTime Function() _clock;

  /// CSPRNG used to mint a 4-hex-char nonce for the backup filename.
  /// Override in tests for determinism.
  final Random _nonceRandom;

  /// Sentinel string written to `system_settings.pending_fronting_migration_mode`.
  static const String modeNotStarted = 'notStarted';

  /// Legacy sentinel from earlier beta builds where users could defer the
  /// migration. New code no longer writes this state; startup treats it as a
  /// mandatory modal state so users complete the sync-reset cutover.
  static const String modeDeferred = 'deferred';
  static const String modeUpgradeAndKeep = 'upgradeAndKeep';
  static const String modeStartFresh = 'startFresh';

  /// Stamped as the FIRST statement inside the destructive Drift
  /// transaction so the marker and the migrated rows commit (or roll
  /// back) atomically. Stays set until the post-tx steps all succeed;
  /// if any of them fail, the user can resume via [resumeCleanup] from
  /// the upgrade modal. App startup and the runtime migration gate
  /// treat this state as "data is in the new shape but the sync side
  /// has not been cut over yet" — sync apply, PK push/poll, and other
  /// new-shape-dependent paths are gated read-only until the user
  /// resolves cleanup.
  static const String modeInProgress = 'inProgress';

  static const String modeComplete = 'complete';

  /// v6→v7 onUpgrade sentinel. Written when duplicate `(pluralkit_uuid,
  /// member_id)` rows prevent the composite unique index from being
  /// created. The modal still surfaces and the user can run the
  /// migration to clear the duplicates; until then the runtime gate
  /// treats this state as hard read-only (Option A in the WS1 plan)
  /// for PK and fronting-session sync paths so the legacy single-column
  /// unique index doesn't reject legitimate multi-member PK switches
  /// while we're in a partially-protected schema state.
  static const String modeBlocked = 'blocked';

  /// Values for `system_settings.pending_fronting_migration_cleanup_substate`.
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
  /// Writes to `getApplicationDocumentsDirectory()` (or the injected
  /// [_backupDirectoryProvider]) instead of cache so the file survives
  /// across app launches even if the user dismisses the upgrade modal
  /// between this and [runMigrationDestructive]. The user can then
  /// recover the file via the platform Files app / file manager.
  ///
  /// Filename is `Prism-Export-yyyy-MM-dd-<epoch_seconds>-<nonce>.prism`
  /// so a same-day retry never silently overwrites the previous attempt's
  /// rescue file. Refuses to write (throws [BackupFileCollisionException])
  /// if a file at the chosen path already exists, so a clock-stuck or
  /// nonce-collision case surfaces to the modal rather than clobbering
  /// the original rescue artifact.
  Future<File> prepareBackup({
    required MigrationMode mode,
    required String password,
  }) async {
    final dir = await _backupDirectoryProvider();
    final fileName = _buildBackupFileName();
    final target = File('${dir.path}/$fileName');
    if (await target.exists()) {
      throw BackupFileCollisionException(target.path);
    }
    return dataExportService.exportEncryptedData(
      password: password,
      includeLegacyFields: true,
      targetDirectory: dir,
      fileName: fileName,
    );
  }

  /// Generates the unique backup filename. The day-stamp keeps human-
  /// readable sortability for the user; the epoch-seconds stamp gives a
  /// monotonic disambiguator within a single day; the 4-hex nonce
  /// protects against a same-second retry on a clock-stuck device.
  String _buildBackupFileName() {
    final now = _clock();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final epochSeconds = (now.millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonceHex(4);
    return 'Prism-Export-$dateStr-$epochSeconds-$nonce.prism';
  }

  String _generateNonceHex(int hexChars) {
    final byteCount = (hexChars + 1) ~/ 2;
    final bytes = List<int>.generate(
      byteCount,
      (_) => _nonceRandom.nextInt(256),
    );
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, hexChars);
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
    // Steps 3-7: wrap in a single Drift transaction. Repository writes
    // inside this block run with `SyncRecordMixin` emission SUPPRESSED
    // so they don't push CRDT ops to the Rust engine. Those ops would
    // commit to Rust's SEPARATE SQLite store (Drift can't roll them
    // back), and auto-sync would push them to peers BEFORE the post-tx
    // `reset_sync_state` runs. Suppression keeps Rust's pending_ops
    // untouched until the cutover.
    //
    // Atomicity contract: `pending_fronting_migration_mode = inProgress`
    // is the FIRST statement inside this transaction. The marker and
    // the destructive fan-out commit (or roll back) as a unit. If the
    // body throws, Drift rolls back and the marker reverts to whatever
    // it was before (typically `notStarted` after v6→v7 onUpgrade). If
    // the body succeeds, the marker is durable on disk before any
    // post-tx step runs, so a crash between commit and the post-tx
    // sequence (engine reset / keychain wipe / quarantine clear) leaves
    // the user on the recoverable resumeCleanup path rather than back
    // at `notStarted` with already-migrated data.
    _MigrationCounters counters;
    try {
      counters = await SyncRecordMixin.suppress(() {
        return db.transaction<_MigrationCounters>(() async {
          // Step 1 (atomicity): stamp the in-progress marker FIRST so
          // it commits in the same Drift transaction as the destructive
          // writes below. Calling the DAO from inside a `db.transaction`
          // block uses the active transactional connection (Drift
          // propagates the transaction via zones); no separate
          // connection is opened.
          await db.systemSettingsDao.writePendingFrontingMigrationMode(
            modeInProgress,
          );

          // Test-only failpoint: throwing here exercises the rollback
          // path — both the marker and any subsequent destructive work
          // revert atomically.
          final midHook = _midTransactionFailpoint;
          if (midHook != null) {
            await midHook();
          }

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
      // Drift rolled back; the in-progress marker reverted with the
      // destructive writes. Settings still at the prior value
      // (typically `notStarted`). Suppression also cleared on the way
      // out via the `suppress` finally block.
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Migration transaction failed: $e',
      );
    }

    // Test-only failpoint: throwing here simulates a crash between the
    // Drift commit and the post-tx cleanup. The marker is already
    // durable as `inProgress`; the user re-enters via
    // [resumeCleanup].
    final postHook = _postTransactionFailpoint;
    if (postHook != null) {
      try {
        await postHook();
      } catch (e) {
        return _failPostTx(
          exportFile: exportFile,
          counters: counters,
          errorMessage:
              'Post-transaction failpoint: $e. Please reopen the upgrade '
              'modal to finish migration.',
        );
      }
    }

    return _runPostTransactionCleanup(
      exportFile: exportFile,
      counters: counters,
    );
  }

  /// Compatibility wrapper for tests and callers that don't exercise the
  /// durable-backup gate.
  ///
  /// Production uses [prepareBackup] + [runMigrationDestructive] directly with
  /// the backup-ready acknowledgment step in between. This fallback composes
  /// those methods in sequence.
  ///
  /// [shareFile]'s return value gates the destructive phase: a `null`
  /// return is treated as user cancellation (e.g. Share dialog
  /// dismissed) and the destructive phase is skipped, returning a
  /// `failed` outcome with the export file preserved on disk so a
  /// retry can re-use it. A non-null `Uri` is treated as a successful
  /// hand-off and the destructive phase proceeds.
  Future<MigrationResult> runMigration({
    required MigrationMode mode,
    required DeviceRole role,
    required Future<Uri?> Function(File file) shareFile,
    String password = '',
  }) async {
    File exportFile;
    try {
      exportFile = await prepareBackup(mode: mode, password: password);
    } catch (e) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        errorMessage: 'PRISM1 export failed: $e',
      );
    }

    Uri? shareResult;
    try {
      shareResult = await shareFile(exportFile);
    } catch (e) {
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage: 'Share-sheet failed: $e',
      );
    }

    if (shareResult == null) {
      // User cancelled the share/save sheet. Do NOT proceed to the
      // destructive phase — the rescue file is on disk but we have no
      // confirmation it ended up anywhere recoverable. Surface the
      // export file so the modal/test caller can offer a retry.
      return MigrationResult(
        outcome: MigrationOutcome.failed,
        exportFile: exportFile,
        errorMessage:
            'Backup share/save was cancelled before destructive '
            'migration. The PRISM1 file is still on disk; retry to continue.',
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
  /// Reads `pending_fronting_migration_cleanup_substate` to decide
  /// whether the Rust reset still needs to run. When the substate is
  /// [substateResetDone] we KNOW the previous attempt's Rust reset
  /// returned success — skip the FFI call entirely. When the substate
  /// is the inert default we MUST run a clear; the handle is
  /// unconfigured (app startup gates that detect `inProgress` publish
  /// an unconfigured handle), so we use `clear_sync_state(sync_id)`
  /// which operates on storage directly without touching the engine.
  /// This sidesteps the configure-briefly path that had a
  /// relay-reconnect bug.
  Future<MigrationResult> resumeCleanup() async {
    final currentMode = await db.systemSettingsDao
        .readPendingFrontingMigrationMode();
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
  /// Writes `pending_fronting_migration_cleanup_substate = 'resetDone'`
  /// between Rust reset success and the keychain wipe so a second
  /// invocation (via [resumeCleanup]) can skip the reset call instead
  /// of relying on a "sync_id not set" heuristic — that heuristic
  /// would otherwise mis-classify "engine never configured because
  /// Rust persistent state was never cleared" as "reset already
  /// succeeded."
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
        await db.systemSettingsDao.writePendingFrontingMigrationCleanupSubstate(
          substateResetDone,
        );
      }
    }

    // Step 8b: wipe the platform keychain. Without this, a fresh app
    // launch would re-seed Rust from the still-present
    // wrapped_dek/sync_id/device_secret/etc. and silently re-attach
    // to the OLD sync group. Idempotent — wiping already-wiped slots
    // is a no-op.
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

    // Ensure the v7 fronting indexes are installed BEFORE we mark the
    // migration complete.
    //
    // v7 onUpgrade's detect-and-refuse path skips composite + orphan
    // index creation when duplicates are detected, so a DB that took
    // the blocked-mode recovery route to get here may still be missing
    // those indexes (and may still have the v2-era single-column
    // uniqueness index that would reject legitimate multi-member PK
    // switches). Ensure the v7 indexes idempotently — safe to call from
    // both blocked-mode recovery and the normal flow (where v7 onUpgrade
    // already created them, so this is a no-op).
    //
    // Run this BEFORE the modeComplete write so a failure here keeps
    // the user on the resumeCleanup path rather than stranding a
    // "completed" DB without protective constraints. Wrap with
    // _failPostTx for the same reason as the other post-tx steps.
    try {
      await db.ensurePkFrontingIndexes();
    } catch (e) {
      return _failPostTx(
        exportFile: exportFile,
        counters: counters,
        errorMessage:
            'Fronting index install failed: $e. Please reopen the upgrade '
            'modal to finish migration.',
      );
    }

    // Apply the v14 CHECK constraint on fronting_sessions. Runs after
    // step 7 routed every orphan normal row to the Unknown sentinel,
    // so the constraint can attach without rejecting any existing row.
    // Idempotent — a no-op when the constraint is already in place
    // (fresh installs at v14+ get it via `customConstraints` at
    // `createAll()` time, and v13→v14 onUpgrade may have already
    // applied it when mode was 'complete' before the modal ran).
    //
    // Same `_failPostTx` framing as the index install above: if this
    // step fails, leave the user on `inProgress` so they can resume
    // rather than stranding a 'completed' DB without the structural
    // backstop.
    try {
      await db.ensureFrontingMemberCheckConstraint();
    } catch (e) {
      return _failPostTx(
        exportFile: exportFile,
        counters: counters,
        errorMessage:
            'Fronting CHECK constraint install failed: $e. Please reopen the '
            'upgrade modal to finish migration.',
      );
    }

    // Step 10: mark complete. Reset the cleanup substate back to the
    // inert default so a subsequent (rare) re-run after `complete`
    // doesn't carry over stale state — though `resumeCleanup()` itself
    // refuses to run unless mode is `inProgress`.
    await db.systemSettingsDao.writePendingFrontingMigrationMode(modeComplete);
    await db.systemSettingsDao.writePendingFrontingMigrationCleanupSubstate(
      substateInert,
    );

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
      adjacentMergesPerformed: counters.adjacentMergesPerformed,
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
      adjacentMergesPerformed: counters.adjacentMergesPerformed,
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
      // Step 6: delete every fronting row + every comment via the
      // repository. The whole transaction body runs under
      // `SyncRecordMixin.suppress`, so these deletes emit NO sync ops;
      // the local Drift `is_deleted` flips correctly without producing
      // tombstones in `pending_ops`. The post-tx sync state wipe will
      // erase any pre-existing CRDT state, so we deliberately don't
      // emit deletes — the new-shape snapshot rebuild is the canonical
      // post-migration state for paired peers.
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
    // Member ids touched by SP migration / native migration / fan-out
    // / orphan-sentinel assignment. Fed to the post-fan-out
    // adjacent-merge pass so we don't re-scan members that the
    // migration didn't touch.
    final touchedMemberIds = <String>{};

    // Orphan bucket — populated by both Step 3 (SP normals with null
    // member_id, e.g., importer paths for `_IdKind.missing` / `cfNote`)
    // and Step 4 (native normals with null member_id). Drained by
    // Step 7 onto the Unknown sentinel. Sleep rows with null member_id
    // are not orphans — sleep legitimately allows no fronter.
    final orphans = <FrontingSessionRow>[];

    // Step 3: SP-imported rows.  Already 1:1 per-member; just emit a
    // v2 entity op so the new-shape sync schema picks them up.
    //
    // Exception: SP normal rows with NULL member_id cannot satisfy the
    // planned CHECK(session_type != 0 OR member_id IS NOT NULL)
    // constraint and must land on the Unknown sentinel instead. The SP
    // importer emits these for `_IdKind.missing` and `cfNote`
    // (`sp_mapper.dart:438, 457`), and legacy imports predating the
    // unknown-sentinel resolution may also have them on disk.
    for (final c in classified) {
      if (c.kind != _SessionKind.spImported) continue;
      if (c.row.memberId == null &&
          c.row.sessionType != SessionType.sleep.index) {
        orphans.add(c.row);
        continue;
      }
      await frontingSessionRepository.updateSession(_rowToDomain(c.row));
      counters.spRowsMigrated++;
      final mid = c.row.memberId;
      if (mid != null) touchedMemberIds.add(mid);
    }

    // Step 4: native rows (normal + sleep).  Sleep keeps nullable
    // member_id and migrates 1:1.  Normal single-member migrates 1:1.
    // Normal multi-member: primary keeps legacy id; co-fronters get
    // deterministic v5 ids from migrationFrontingNamespace.
    for (final c in classified) {
      switch (c.kind) {
        case _SessionKind.pkImported:
        case _SessionKind.spImported:
          continue;
        case _SessionKind.nativeSleep:
          await frontingSessionRepository.updateSession(_rowToDomain(c.row));
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
      touchedMemberIds.add(row.memberId!);

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
        touchedMemberIds.add(coId);
      }
    }

    // Step 5: comments.  Walk every comment, look up its parent
    // session by legacy `session_id`, decide preserve-or-delete.
    //
    // Preserved comments stay attached to their physical parent session id.
    // Native co-front comments continue on the primary per-member row because
    // that row keeps the legacy aggregate id. PK-parent comments are deleted
    // in this app-layer migration; PRISM1 rescue import has the richer final
    // session-id map needed to preserve those safely.
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

      await frontSessionCommentsRepository.updateComment(
        FrontSessionComment(
          id: cmt.id,
          sessionId: cmt.sessionId,
          body: cmt.body,
          timestamp: cmt.timestamp,
          createdAt: cmt.createdAt,
        ),
      );
      counters.commentsMigrated++;
    }

    // Step 7: orphan handling.  Create the Unknown sentinel only if
    // there's at least one orphan to assign.  The shared
    // `ensureUnknownSentinelMember` helper is idempotent (returns
    // wasCreated=false if a prior failed attempt already created it).
    //
    // Determinism contract: `unknownSentinelMemberId` is a UUIDv5
    // derived from `spFrontingNamespace` + the literal string
    // `'unknown-member-sentinel'` (see
    // `core/constants/fronting_namespaces.dart`). The id is byte-
    // identical on every device. That property is load-bearing here:
    // orphan-rescue rows reference this member id under suppression,
    // so paired devices that re-pair after migration must resolve the
    // sentinel locally without an explicit sync op carrying it across.
    if (orphans.isNotEmpty) {
      final ensured = await memberRepository.ensureUnknownSentinelMember();
      if (ensured.wasCreated) {
        counters.unknownSentinelCreated = true;
      }
      final sentinelId = ensured.member.id;
      touchedMemberIds.add(sentinelId);
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

    // Step 4b: adjacent-merge pass (spec §2.1). After fan-out, a
    // continuously-fronting member may have multiple adjacent rows
    // whose only reason for being split is that a co-fronter joined
    // or left in the old shape — boundaries that are now arbitrary
    // cosmetic artifacts under the per-member abstraction. Collapse
    // them into one continuous row before sync ships them out.
    counters.adjacentMergesPerformed = await mergeAdjacentSameMemberRows(
      frontingSessionRepository,
      memberIds: touchedMemberIds,
      commentsRepository: frontSessionCommentsRepository,
    );

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
    // customStatement bypasses Drift's typed-write notification, so live
    // streams (and the frontingTableTickerProvider) wouldn't see this
    // truncation. The migration is followed by a full app reload, so
    // the live UI doesn't actually observe the intermediate state — but
    // we notify defensively in case a future caller skips the reload.
    db.notifyUpdates({
      const TableUpdate('fronting_sessions'),
      const TableUpdate('front_session_comments'),
    });
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
        .map(
          (r) => _LegacyComment(
            id: r.read<String>('id'),
            sessionId: r.read<String?>('session_id') ?? '',
            body: r.read<String>('body'),
            timestamp: r.read<DateTime>('timestamp'),
            createdAt: r.read<DateTime>('created_at'),
          ),
        )
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
        _ClassifiedSession(r, _classifyOne(r, spSessionIds)),
    ];
  }

  _SessionKind _classifyOne(FrontingSessionRow r, Set<String> spSessionIds) {
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
      quality:
          r.quality != null &&
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
  _MigrationCounters({this.pkRowsDeleted = 0});

  int spRowsMigrated = 0;
  int nativeRowsMigrated = 0;
  int nativeRowsExpanded = 0;
  int pkRowsDeleted;
  int commentsMigrated = 0;
  int commentsDeleted = 0;
  int orphanRowsAssignedToSentinel = 0;
  bool unknownSentinelCreated = false;
  final List<String> corruptCoFronterRowIds = <String>[];
  int adjacentMergesPerformed = 0;
}
