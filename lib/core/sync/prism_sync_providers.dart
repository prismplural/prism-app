import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:drift/drift.dart' show TableUpdate, Variable;
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart'
    show secretUtf8Bytes;
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/biometric_service.dart';
import 'package:prism_plurality/core/services/biometric_service_provider.dart';
import 'package:prism_plurality/core/services/crypto_boot_log.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_pairing_phase.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_database_probe.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/backup_exclusion.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:prism_plurality/features/migration/services/sp_boards_backfill_service.dart';
import 'package:prism_plurality/features/migration/services/group_chat_visibility_sync_reemit_service.dart';
import 'package:prism_plurality/features/migration/services/sp_reply_quote_backfill_service.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';

// Dart-side sync integration — manages the Rust FFI handle lifecycle, keychain
// persistence (seed/drain), health state machine, and sync event routing.
//
// Keychain keys (all prefixed prism_sync.*) are written by both Dart (during
// setup/pairing) and Rust FFI (drainRustStore). If you rename a key here,
// update the Rust SecureStore drain in prism-sync-ffi/src/api.rs too.
//
// Signal model: a device-bound wrapped runtime DEK is cached after first
// Argon2id unlock so subsequent launches can fast-restore without the
// password. See _autoConfigureIfReady() for the state machine that decides
// healthy vs needsPassword vs disconnected.

const _prismSyncStructuredErrorPrefix = 'PRISM_SYNC_ERROR_JSON:';

class PrismSyncStructuredError {
  const PrismSyncStructuredError({
    required this.message,
    this.operation,
    this.errorType,
    this.relayKind,
    this.code,
    this.status,
    this.minSignatureVersion,
    this.remoteWipe,
  });

  final String message;
  final String? operation;
  final String? errorType;
  final String? relayKind;
  final String? code;
  final int? status;
  final int? minSignatureVersion;
  final bool? remoteWipe;

  bool get isDeviceIdentityMismatch => code == 'device_identity_mismatch';
  bool get isDeviceRevoked => code == 'device_revoked';

  String get userMessage {
    if (isDeviceIdentityMismatch) {
      return 'This installation no longer matches the registered device identity. Export local data if needed, then pair this installation as a new device.';
    }
    if (isDeviceRevoked) {
      return remoteWipe == true
          ? 'This device was removed from sync and requested to wipe synced data.'
          : 'This device was removed from sync.';
    }
    return message;
  }

  factory PrismSyncStructuredError.fromJson(Map<String, dynamic> json) {
    return PrismSyncStructuredError(
      message: json['message'] as String? ?? 'Unknown sync error',
      operation: json['operation'] as String?,
      errorType: json['error_type'] as String?,
      relayKind: json['relay_kind'] as String?,
      code: json['code'] as String?,
      status: (json['status'] as num?)?.toInt(),
      minSignatureVersion: (json['min_signature_version'] as num?)?.toInt(),
      remoteWipe: json['remote_wipe'] as bool?,
    );
  }

  static PrismSyncStructuredError? tryParse(Object error) {
    return tryParseMessage(error.toString());
  }

  static PrismSyncStructuredError? tryParseMessage(String rawMessage) {
    final markerIndex = rawMessage.indexOf(_prismSyncStructuredErrorPrefix);
    if (markerIndex == -1) {
      return null;
    }

    final payload = rawMessage
        .substring(markerIndex + _prismSyncStructuredErrorPrefix.length)
        .trim();
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return PrismSyncStructuredError.fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static PrismSyncStructuredError? fromSyncEvent(SyncEvent event) {
    if (!event.isError) {
      return null;
    }
    final code = event.data['code'] as String?;
    final remoteWipe = event.data['remote_wipe'] as bool?;
    if (code == null && remoteWipe == null) {
      return null;
    }

    return PrismSyncStructuredError(
      message: event.data['message'] as String? ?? 'Unknown sync error',
      relayKind: event.data['kind'] as String?,
      code: code,
      remoteWipe: remoteWipe,
    );
  }
}

const _prismSyncFailedPrefix = 'Prism sync failed: ';
const _pluralKitSyncFailedPrefix = 'PluralKit sync failed: ';

/// Return a user-facing Prism sync error message with subsystem clarity.
/// If the message was already prefixed, return it unchanged.
@visibleForTesting
String? formatPrismSyncError(Object? rawError) {
  final message = rawError?.toString().trim();
  if (message == null || message.isEmpty) {
    return null;
  }
  if (message.startsWith(_prismSyncFailedPrefix) ||
      message.startsWith(_pluralKitSyncFailedPrefix)) {
    return message;
  }
  return '$_prismSyncFailedPrefix$message';
}

/// Thrown by `createHandle` when the §5 sync DB probe returned
/// `unrecoverable`. The `build()` path catches this, marks
/// `syncKey/syncCredentials = unreadable` and the pairing phase as
/// `pendingPair`-ready (left as `unread` until the user explicitly opts
/// into a wipe via the recovery UI in §7), and returns a null handle so
/// the app continues launching in local-only mode.
class SyncDbUnrecoverableException implements Exception {
  const SyncDbUnrecoverableException();

  @override
  String toString() =>
      'SyncDbUnrecoverableException: sync DB key slots are unreadable; '
      'app continues in local-only mode pending re-pair';
}

// ---------------------------------------------------------------------------
// §5 — Sync DB startup probe + recovery
// ---------------------------------------------------------------------------
//
// Mirrors the §4 app DB probe in `database_provider.dart`, with two
// differences:
//
//   1. The fresh-install branch does NOT generate a key. The sync DB is only
//      created during the pairing flow; there is no sensible standalone key
//      to write at boot.
//   2. There are additional cross-DB recovery candidates: older installs
//      converged the two keys when `cacheRuntimeKeys` rotated both DBs to
//      the HKDF-derived local-storage key, so the app-DB primary/staging
//      slots are valid candidates for opening `prism_sync.db` on those
//      installs. (`ensureLocalSyncDatabaseKey` documents the migration
//      that seeds the dedicated sync slot from the Drift slot.)
//
// On unrecoverable: the app still launches (local-only mode); the sync
// handle is just null and the in-app banner surfaces re-pair guidance.
// See §6/§7 for the boot wiring and recovery UI.

/// Mutable holder for the sync DB startup probe result.
///
/// `main.dart` (§6) overrides this via `ProviderScope.overrides` with the
/// output of [probeSyncDatabaseStartup]. Sync reset may update the state in
/// the same app session after deleting `prism_sync.db`, so setup does not stay
/// blocked on a stale boot-time `unrecoverable` report.
final syncDatabaseStartupReportStateProvider =
    NotifierProvider<SyncDatabaseStartupReportNotifier, DbStartupReport>(
      SyncDatabaseStartupReportNotifier.new,
    );

class SyncDatabaseStartupReportNotifier extends Notifier<DbStartupReport> {
  SyncDatabaseStartupReportNotifier([this._initial]);

  final DbStartupReport? _initial;

  @override
  DbStartupReport build() {
    final initial = _initial;
    if (initial != null) return initial;
    throw UnimplementedError(
      'syncDatabaseStartupReportStateProvider must be overridden by main.dart '
      'with the sync DB probe result. See '
      'docs/0.9.2-secure-storage-remediation.md §5.',
    );
  }

  void setReport(DbStartupReport report) => state = report;
}

/// Riverpod provider exposing the current sync DB startup probe result.
final syncDatabaseStartupProvider = Provider<DbStartupReport>((ref) {
  return ref.watch(syncDatabaseStartupReportStateProvider);
});

/// Probe `prism_sync.db` at startup, returning a verified key in memory or
/// signalling unrecoverable so the boot path can route to the re-pair UI.
///
/// Order of operations (the only path through):
///
/// 1. **Fresh install.** If `prism_sync.db` does not exist, return
///    `ready(slot: 'fresh', keyInMemory: null)`. No key is generated — the
///    sync DB is created during pairing, not boot.
/// 2. **Staging crash recovery.** Mirrors the existing sync staging
///    recovery in `createHandle()` (which we keep in place — this is the
///    new probe path; that path is now no-op'd by the probe ready check).
///    If a sync staging key exists and opens the on-disk DB, promote it
///    to the primary sync slot. If it doesn't open, discard it.
/// 3. **Sync primary slot** — open with the dedicated sync slot.
/// 4. **Sync staging slot** — same.
/// 5. **App primary slot** (cross-DB recovery candidate) — only consulted
///    when [verifiedAppDbKey] is non-null. Opens the sync DB on installs
///    where `cacheRuntimeKeys` converged the two keys.
/// 6. **App staging slot** — same.
/// 7. **Unrecoverable** — no slot opened the sync DB.
///
/// The optional [directory] override exists so tests don't need to mock the
/// `path_provider` platform channel. [degradedStateService] is the §8
/// service used to record the sync slot outcome.
Future<DbStartupReport> probeSyncDatabaseStartup({
  required String? verifiedAppDbKey,
  Directory? directory,
  KeychainDegradedStateService? degradedStateService,
  SyncDatabaseOpenProbe syncDatabaseOpenProbe = rustSyncDatabaseOpenProbe,
}) async {
  final service = degradedStateService ?? KeychainDegradedStateService();
  final slotOutcomes = <String, String>{};
  final dir = directory ?? await getAppDataDir();
  final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
  final file = File(dbPath);

  Future<SecureStorageDiagnostic> buildDiagnostic({
    required String? recoveredVia,
    required DbStartupStateName syncDbState,
  }) async {
    KeychainDegradedState? degradedSnapshot;
    try {
      degradedSnapshot = await service.read();
    } catch (e) {
      debugPrint('[SYNC_PROBE] Failed to snapshot degraded state: $e');
    }
    return SecureStorageDiagnostic(
      recoveredVia: recoveredVia,
      slotOutcomes: slotOutcomes,
      syncDbState: syncDbState,
      keychainDegradedStateSnapshot: degradedSnapshot,
    );
  }

  // ── 1. Fresh install ───────────────────────────────────────────────────
  if (!file.existsSync()) {
    debugPrint(
      '[SYNC_PROBE] No prism_sync.db on disk — fresh sync (no key generated)',
    );
    slotOutcomes[DiagnosticSlotIds.syncDbFresh] = 'ok';
    await service.updateSlot('syncKey', SlotState.ok);
    return DbStartupReport(
      state: DbStartupState.ready,
      keyInMemory: null,
      usedRecoverySlot: 'fresh',
      diagnostic: await buildDiagnostic(
        recoveredVia: 'fresh',
        syncDbState: DbStartupStateName.ready,
      ),
    );
  }

  // ── 2. Staging crash recovery (best-effort; swallow guard refusal) ─────
  //
  // If a prior `cacheRuntimeKeys` rotation crashed between rekeyDb and the
  // primary-slot write, the staging slot is the real key. If `keychain_repair_pending`
  // is set, the promote write may be refused — that's fine; we'll still try
  // the staging slot directly below, it just won't get promoted yet.
  try {
    final syncStagingKey = await readStagingSyncDatabaseKeyHex();
    if (syncStagingKey != null) {
      if (await syncDatabaseOpenProbe(dbPath, syncStagingKey)) {
        debugPrint(
          '[SYNC_PROBE] Crash-recovery: sync DB staging key verified — promoting',
        );
        await promoteStagingSyncDatabaseKey(syncStagingKey);
        slotOutcomes[DiagnosticSlotIds.syncDbStagingPromote] = 'ok';
      } else {
        await discardStagingSyncDatabaseKey();
        slotOutcomes[DiagnosticSlotIds.syncDbStagingPromote] =
            'threw: discarded-stale';
      }
    } else {
      slotOutcomes[DiagnosticSlotIds.syncDbStagingPromote] = 'missing';
    }
  } catch (e) {
    slotOutcomes[DiagnosticSlotIds.syncDbStagingPromote] =
        slotOutcomeThrewString(e);
    debugPrint('[SYNC_PROBE] Sync staging crash recovery skipped: $e');
  }

  // ── 3. Sync primary slot ───────────────────────────────────────────────
  final syncPrimary = await readSlotForDiagnostic(
    kSyncDatabaseKeyStorageKey,
    slotLabel: 'sync DB key',
  );
  if (syncPrimary.hex != null) {
    if (await syncDatabaseOpenProbe(dbPath, syncPrimary.hex!)) {
      debugPrint('[SYNC_PROBE] Sync primary slot opened the sync DB');
      slotOutcomes[DiagnosticSlotIds.syncDbPrimary] = 'ok';
      await service.updateSlot('syncKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: syncPrimary.hex,
        usedRecoverySlot: 'primary',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'primary',
          syncDbState: DbStartupStateName.ready,
        ),
      );
    }
    slotOutcomes[DiagnosticSlotIds.syncDbPrimary] = 'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.syncDbPrimary] = slotOutcomeName(
      syncPrimary.outcome,
    );
  }

  // ── 4. Sync staging slot ───────────────────────────────────────────────
  final syncStaging = await readSlotForDiagnostic(
    '${kSyncDatabaseKeyStorageKey}_staging',
    slotLabel: 'sync DB staging key',
  );
  if (syncStaging.hex != null) {
    if (await syncDatabaseOpenProbe(dbPath, syncStaging.hex!)) {
      debugPrint(
        '[SYNC_PROBE] Sync staging slot opened the sync DB — repair-pending',
      );
      slotOutcomes[DiagnosticSlotIds.syncDbSyncStaging] = 'ok';
      await service.updateSlot('syncKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: syncStaging.hex,
        usedRecoverySlot: 'sync_staging',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'sync_staging',
          syncDbState: DbStartupStateName.ready,
        ),
      );
    }
    slotOutcomes[DiagnosticSlotIds.syncDbSyncStaging] =
        'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.syncDbSyncStaging] = slotOutcomeName(
      syncStaging.outcome,
    );
  }

  // ── 5. App primary slot (cross-DB recovery candidate) ──────────────────
  //
  // Older installs converged the two keys after cacheRuntimeKeys rotated
  // both DBs to the HKDF-derived local-storage key. ensureLocalSyncDatabaseKey
  // also seeded the dedicated sync slot from the Drift slot on first
  // upgrade. If the in-memory verified app DB key opens the sync DB, it's
  // the real sync key for this device.
  if (verifiedAppDbKey != null) {
    if (await syncDatabaseOpenProbe(dbPath, verifiedAppDbKey)) {
      debugPrint(
        '[SYNC_PROBE] App primary slot opened the sync DB (cross-DB recovery)',
      );
      slotOutcomes[DiagnosticSlotIds.syncDbAppPrimaryCandidate] = 'ok';
      await service.updateSlot('syncKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: verifiedAppDbKey,
        usedRecoverySlot: 'app_primary',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'app_primary',
          syncDbState: DbStartupStateName.ready,
        ),
      );
    }
    slotOutcomes[DiagnosticSlotIds.syncDbAppPrimaryCandidate] =
        'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.syncDbAppPrimaryCandidate] =
        'threw: app-db-unrecoverable';
  }

  // ── 6. App staging slot ────────────────────────────────────────────────
  final appStaging = await readSlotForDiagnostic(
    '${kDatabaseKeyStorageKey}_staging',
    slotLabel: 'app DB staging key',
  );
  if (appStaging.hex != null) {
    if (await syncDatabaseOpenProbe(dbPath, appStaging.hex!)) {
      debugPrint(
        '[SYNC_PROBE] App staging slot opened the sync DB (cross-DB recovery)',
      );
      slotOutcomes[DiagnosticSlotIds.syncDbAppStagingCandidate] = 'ok';
      await service.updateSlot('syncKey', SlotState.ok);
      return DbStartupReport(
        state: DbStartupState.ready,
        keyInMemory: appStaging.hex,
        usedRecoverySlot: 'app_staging',
        diagnostic: await buildDiagnostic(
          recoveredVia: 'app_staging',
          syncDbState: DbStartupStateName.ready,
        ),
      );
    }
    slotOutcomes[DiagnosticSlotIds.syncDbAppStagingCandidate] =
        'threw: present-but-stale';
  } else {
    slotOutcomes[DiagnosticSlotIds.syncDbAppStagingCandidate] = slotOutcomeName(
      appStaging.outcome,
    );
  }

  // ── 7. Unpaired stale DB ────────────────────────────────────────────────
  final syncIdentityState = await _readPersistentSyncIdentityState();
  if (syncIdentityState == PersistentSyncIdentityState.absent) {
    await _discardUnpairedSyncDatabase(dbPath: dbPath);
    slotOutcomes[DiagnosticSlotIds.syncDbUnpairedDiscard] = 'ok';
    debugPrint('[SYNC_PROBE] Discarded unpaired stale sync DB');
    await service.updateSlot('syncKey', SlotState.ok);
    return DbStartupReport(
      state: DbStartupState.ready,
      keyInMemory: null,
      usedRecoverySlot: 'discarded_unpaired',
      diagnostic: await buildDiagnostic(
        recoveredVia: 'discarded_unpaired',
        syncDbState: DbStartupStateName.ready,
      ),
    );
  } else if (syncIdentityState == PersistentSyncIdentityState.partial) {
    slotOutcomes[DiagnosticSlotIds.syncDbUnpairedDiscard] =
        'skipped: partial-identity';
  }

  // ── 8. Unrecoverable ───────────────────────────────────────────────────
  debugPrint(
    '[SYNC_PROBE] All recovery slots exhausted — sync DB unrecoverable. '
    'Outcomes: $slotOutcomes',
  );
  await service.updateSlot('syncKey', SlotState.unreadable);
  await service.updateSlot('syncCredentials', SlotState.unreadable);
  return DbStartupReport(
    state: DbStartupState.unrecoverable,
    keyInMemory: null,
    usedRecoverySlot: null,
    diagnostic: await buildDiagnostic(
      recoveredVia: null,
      syncDbState: DbStartupStateName.unrecoverable,
    ),
  );
}

/// Atomically wipe `prism_sync.db` and its keychain slots so a fresh pair
/// can recover the device. Tied to the [SyncPairingPhase] state machine —
/// the phase persistence is the safety mechanism: if the user goes offline
/// AFTER the wipe but BEFORE pair, we leave the device in
/// [SyncPairingPhase.pendingPair] so next launch surfaces
/// "complete the pair you started" rather than recreating the broken state.
///
/// Caller responsibilities (NOT enforced here):
///   * The pairing UI is responsible for the outer online-check / pair-flow.
///     This function does the local-only wipe and ends in `pendingPair`.
///   * The pairing UI is responsible for transitioning
///     `pendingPair → paired` on successful pair.
///
/// Guards (enforced here):
///   * Current phase must be [SyncPairingPhase.unread]. Any other phase
///     means a wipe is already in flight, completed but unpaired, or sync
///     is currently healthy — refuse.
///   * `syncKey` slot in [KeychainDegradedState] must be
///     [SlotState.unreadable]. We only wipe broken sync state.
///
/// Steps (in order):
///   1. Transition `unread → wipeInProgress`.
///   2. Stop any in-flight sync handle. Background sync jobs are currently
///      disabled (`workmanager` is commented out in main.dart) — when they
///      come back, cancel them here.
///   3. Delete `prism_sync.db` and its sidecar files (`-shm`, `-wal`).
///   4. Clear the sync key slots via guarded delete.
///   5. Clear sync-related credential slots via guarded delete (sync_id,
///      device_id, device_secret, wrapped_dek, runtime DEK cache, etc.).
///   6. Transition `wipeInProgress → pendingPair`.
///
/// The phase persistence (`SharedPref`) is set BEFORE any destructive step
/// and updated to `pendingPair` AFTER all destructive steps succeed. A
/// crash between 1 and 6 leaves the device in `wipeInProgress`; the next
/// launch will see that and re-invoke `wipeSyncDatabaseForRepair` to
/// finish.
Future<void> wipeSyncDatabaseForRepair({
  Directory? directory,
  KeychainDegradedStateService? degradedStateService,
  SyncPairingPhaseService? phaseService,
  ffi.PrismSyncHandle? currentHandle,
}) async {
  final phase = phaseService ?? SyncPairingPhaseService();
  final degraded = degradedStateService ?? KeychainDegradedStateService();
  final currentPhase = await phase.read();
  if (currentPhase != SyncPairingPhase.unread &&
      currentPhase != SyncPairingPhase.wipeInProgress) {
    debugPrint(
      '[SYNC_WIPE] Refused — phase is ${currentPhase.name}, '
      'expected unread or wipeInProgress',
    );
    throw StateError(
      'wipeSyncDatabaseForRepair refused: phase is ${currentPhase.name}, '
      'expected unread or wipeInProgress',
    );
  }
  final degradedState = await degraded.read();
  if (currentPhase == SyncPairingPhase.unread &&
      degradedState.syncKey != SlotState.unreadable) {
    debugPrint(
      '[SYNC_WIPE] Refused — syncKey state is ${degradedState.syncKey.name}, '
      'expected unreadable',
    );
    throw StateError(
      'wipeSyncDatabaseForRepair refused: syncKey is '
      '${degradedState.syncKey.name}, expected unreadable',
    );
  }

  // 1. Transition into wipeInProgress BEFORE any destructive step so a
  //    crash mid-flow is recoverable on next launch.
  if (currentPhase == SyncPairingPhase.unread) {
    await phase.transition(
      from: SyncPairingPhase.unread,
      to: SyncPairingPhase.wipeInProgress,
    );
  } else {
    debugPrint('[SYNC_WIPE] Resuming wipe from wipeInProgress');
  }

  // 2. Stop any in-flight sync handle. workmanager jobs are currently
  //    disabled — when re-enabled, cancel via Workmanager().cancelAll().
  try {
    if (identical(syncCurrentHandle.value, currentHandle)) {
      syncCurrentHandle.value = null;
    }
    currentHandle?.dispose();
  } catch (e) {
    debugPrint('[SYNC_WIPE] handle.dispose() threw (continuing): $e');
  }

  // 3. Delete prism_sync.db + sidecar files.
  final dir = directory ?? await getAppDataDir();
  final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
  for (final suffix in const <String>['', '-shm', '-wal', '-journal']) {
    final f = File('$dbPath$suffix');
    if (f.existsSync()) {
      try {
        f.deleteSync();
        debugPrint('[SYNC_WIPE] Deleted $dbPath$suffix');
      } catch (e) {
        debugPrint('[SYNC_WIPE] Failed to delete $dbPath$suffix: $e');
      }
    }
  }

  // 4. Clear sync key slots via guarded delete.
  final syncSlotKeys = <String>[
    kSyncDatabaseKeyStorageKey,
    '${kSyncDatabaseKeyStorageKey}_staging',
  ];
  for (final key in syncSlotKeys) {
    await _checkedDeleteKey(key);
  }

  // 5. Clear sync-related credential slots via guarded delete.
  //
  // Conservative — only `prism_sync.*` credential keys. App-level
  // SharedPrefs (theme, etc) are NOT touched here.
  const credentialKeys = <String>[
    kSyncIdKey,
    kSyncRelayUrlKey,
    kSyncDeviceIdKey,
    kSyncDeviceSecretKey,
    kRuntimeDekKey,
    kRuntimeDekWrappedKey,
    kSnapshotApplyCompleteKey,
    '${_secureStorePrefix}wrapped_dek',
    '${_secureStorePrefix}dek_salt',
    '${_secureStorePrefix}session_token',
    '${_secureStorePrefix}epoch',
    '${_secureStorePrefix}registration_token',
    '${_secureStorePrefix}setup_rollback_marker',
    '${_secureStorePrefix}sharing_prekey_store',
    '${_secureStorePrefix}sharing_id_cache',
    '${_secureStorePrefix}min_signature_version_floor',
  ];
  for (final key in credentialKeys) {
    await _checkedDeleteKey(key);
  }

  // 6. Transition to pendingPair. The pairing UI takes over from here.
  await phase.transition(
    from: SyncPairingPhase.wipeInProgress,
    to: SyncPairingPhase.pendingPair,
  );
  debugPrint('[SYNC_WIPE] Complete — phase is now pendingPair');
}

// ---------------------------------------------------------------------------
// Core handle
// ---------------------------------------------------------------------------

/// The opaque FFI handle to the Rust sync engine. Null when not configured.
final prismSyncHandleProvider =
    AsyncNotifierProvider<PrismSyncHandleNotifier, ffi.PrismSyncHandle?>(
      PrismSyncHandleNotifier.new,
    );

class PrismSyncHandleNotifier extends AsyncNotifier<ffi.PrismSyncHandle?> {
  ffi.PrismSyncHandle? _handle;
  Future<SyncHealthState>? _ensureConfiguredFuture;

  @override
  Future<ffi.PrismSyncHandle?> build() async {
    // Dispose the FFI handle when this provider is invalidated or rebuilt.
    // PrismSyncHandle is a flutter_rust_bridge opaque type backed by
    // Arc<Mutex<PrismSync>> — dispose() eagerly drops the Rust-side Arc,
    // releasing SQLite connections, WebSocket handles, and background tasks.
    // NOTE: We capture the handle in an instance field rather than reading
    // `state.value` inside onDispose — Riverpod forbids accessing state
    // inside lifecycle callbacks.
    ref.onDispose(() {
      if (identical(syncCurrentHandle.value, _handle)) {
        syncCurrentHandle.value = null;
      }
      _handle?.dispose();
      _handle = null;
    });

    // Auto-create handle if sync credentials exist from a previous session
    final syncIdB64 = await _safeReadValue(kSyncIdKey);
    final relayUrlB64 = await _safeReadValue(kSyncRelayUrlKey);
    final deviceIdB64 = await _safeReadValue(kSyncDeviceIdKey);
    final deviceSecretB64 = await _safeReadValue(kSyncDeviceSecretKey);
    if (hasCompletePersistentSyncIdentity(
      relayUrl: relayUrlB64,
      syncId: syncIdB64,
      deviceId: deviceIdB64,
      hasDeviceSecret: deviceSecretB64 != null && deviceSecretB64.isNotEmpty,
    )) {
      try {
        // Decode base64-encoded relay URL
        String relayUrl;
        try {
          relayUrl = utf8.decode(base64Decode(relayUrlB64!));
        } catch (_) {
          relayUrl = relayUrlB64!; // Fallback: already plain text
        }
        return await createHandle(relayUrl: relayUrl);
      } on SyncDbUnrecoverableException catch (e) {
        // §5: sync DB probe was unrecoverable. The app continues in
        // local-only mode; the in-app banner (§7) surfaces re-pair
        // guidance. Mark the degraded slots so the banner derives the
        // right copy. Leave the pairing phase as `unread` — the user
        // explicitly opts into wipeSyncDatabaseForRepair() from the
        // recovery UI.
        debugPrint('[SYNC] Probe unrecoverable — running in local-only mode');
        final degraded = KeychainDegradedStateService();
        await degraded.updateSlot('syncKey', SlotState.unreadable);
        await degraded.updateSlot('syncCredentials', SlotState.unreadable);
        ErrorReportingService.instance.report(
          'Sync DB unrecoverable on boot: $e',
          severity: ErrorSeverity.warning,
        );
        return null;
      } catch (e, st) {
        // Non-fatal: user can re-setup from settings
        ErrorReportingService.instance.report(
          'Auto-create sync handle failed: $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
        return null;
      }
    }
    return null;
  }

  /// Create the handle (call once at app startup or when sync is first enabled).
  ///
  /// After creation, seeds the Rust-side MemorySecureStore with values from
  /// the platform keychain so that initialize/unlock/configureEngine can
  /// access persisted credentials.
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) async {
    BootTimings.mark('createHandle:entry');
    final previousHandle = _handle;
    final dir = await getAppDataDir();
    final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
    await excludeFromiCloudBackup(dbPath);
    final syncIdentityState = await _readPersistentSyncIdentityState();
    var discardedUnpairedDb = false;
    if (syncIdentityState == PersistentSyncIdentityState.absent &&
        File(dbPath).existsSync()) {
      await _discardUnpairedSyncDatabase(
        dbPath: dbPath,
        currentHandle: previousHandle,
      );
      if (identical(_handle, previousHandle)) {
        _handle = null;
        if (identical(syncCurrentHandle.value, previousHandle)) {
          syncCurrentHandle.value = null;
        }
        state = const AsyncData(null);
      }
      discardedUnpairedDb = true;
      debugPrint('[SYNC] Discarded unpaired sync DB before handle creation');
    }

    // Startup already verified the sync DB key and handled staging recovery.
    // If the existing sync DB cannot be opened, surface degraded sync instead
    // of generating a replacement key.
    final probeReport = ref.read(syncDatabaseStartupProvider);
    if (probeReport.state == DbStartupState.unrecoverable) {
      throw const SyncDbUnrecoverableException();
    }
    final probeKeyHex = discardedUnpairedDb ? null : probeReport.keyInMemory;
    final String databaseKeyHex;
    if (probeKeyHex != null) {
      databaseKeyHex = probeKeyHex;
    } else {
      // probe state == ready, keyInMemory == null means the fresh-install
      // branch: prism_sync.db does not exist. This is the ONE path where
      // we generate a new sync DB key, because Drift/Rust createPrismSync
      // is about to create the file and needs a key to encrypt it with.
      // Goes through the guarded writer (repair-pending refuses any
      // divergent value).
      databaseKeyHex = await ensureLocalSyncDatabaseKey();
    }
    final databaseKey = await ffi.hexDecode(hexStr: databaseKeyHex);
    final handle = await ffi.createPrismSync(
      relayUrl: relayUrl,
      dbPath: dbPath,
      allowInsecure: false,
      schemaJson: prismSyncSchema,
      databaseKey: databaseKey,
    );
    BootTimings.mark('createHandle:createPrismSync');

    // Treat the per-member fronting migration as a hard sync boundary. While
    // any known non-complete migration mode is present, skip both
    // `_seedRustStore` and `_autoConfigureIfReady` so this install cannot
    // re-attach to the old sync group before the reset/re-pair cutover.
    final pendingMigration = await _readPendingFrontingMigrationMode(ref);
    final migrationGateHealth = startupHealthForMigrationMode(pendingMigration);
    final migrationBlocksStartupSync = migrationGateHealth != null;
    if (!migrationBlocksStartupSync) {
      // Seed Rust's in-memory SecureStore from platform keychain.
      await _seedRustStore(handle);
    } else {
      debugPrint(
        '[SYNC] Skipping _seedRustStore — fronting migration is not complete; '
        'awaiting migration reset/re-pair cutover.',
      );
    }
    BootTimings.mark('createHandle:_seedRustStore');

    final preconfigureSyncId = await _safeReadValue(kSyncIdKey);
    final preconfigureDeviceId = await _safeReadValue(kSyncDeviceIdKey);
    final preconfigureDeviceSecret = await _safeReadValue(kSyncDeviceSecretKey);
    final preconfigureHealth = classifyHealthFromKeychain(
      syncId: preconfigureSyncId,
      deviceId: preconfigureDeviceId,
      deviceSecret: preconfigureDeviceSecret,
    );
    if (preconfigureHealth == SyncHealthState.unpaired) {
      ref.read(syncHealthProvider.notifier).setState(SyncHealthState.unpaired);
    }

    // Mark startup auto-config as in-progress before publishing the handle so
    // startup-sensitive listeners never observe a provisional "ready" window
    // between handle publication and configureEngine.
    syncAutoConfigureInProgress.value = true;

    // Publish the handle before auto-configuring. Startup auto-sync can emit
    // RemoteChanges almost immediately after configureEngine/setAutoSync, and
    // those changes must not beat Dart's event-stream subscription.
    if (previousHandle != null && !identical(previousHandle, handle)) {
      previousHandle.dispose();
    }
    _handle = handle;
    syncCurrentHandle.value = handle;
    state = AsyncData(handle);

    // Auto-configure sync engine if credentials already exist (app restart).
    // Writes that land in this window can see `sync not configured` even
    // though the same handle will become writable a moment later.
    //
    // Skip while the migration has not completed. Report `unpaired` rather
    // than `healthy` so the post-config block below (cacheRuntimeKeys /
    // re-emit / drainRustStore / onResume) is skipped entirely. This keeps the
    // old sync group detached until the user completes the migration reset and
    // pairs again.
    late SyncHealthState health;
    Future<SyncHealthState>? configureFuture;
    try {
      if (migrationGateHealth != null) {
        // `unpaired` already means "engine isn't configured; skip the
        // post-config drain / cacheRuntimeKeys / scheduled onResume
        // calls" — exactly the semantics we need here. The modal will
        // drive resumeCleanup() which then transitions away from
        // `inProgress`.
        health = migrationGateHealth;
      } else {
        final future = _autoConfigureIfReady(handle);
        configureFuture = future;
        _ensureConfiguredFuture = future;
        health = await future;
      }
      BootTimings.mark('createHandle:_autoConfigureIfReady');
      ref.read(syncHealthProvider.notifier).setState(health);
    } catch (e, st) {
      health = SyncHealthState.disconnected;
      ErrorReportingService.instance.report(
        'Auto-configure sync failed unexpectedly: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      ref.read(syncHealthProvider.notifier).setState(health);
    } finally {
      if (configureFuture != null &&
          identical(_ensureConfiguredFuture, configureFuture)) {
        _ensureConfiguredFuture = null;
      }
      syncAutoConfigureInProgress.value = false;
    }

    // Diagnostic: persistent boot snapshot for crypto-storage debugging.
    // Captures which prism_sync.* keychain entries existed at this cold
    // start, plus the resolved sync health. Surfaces in the Crypto
    // storage debug screen so users diagnosing intermittent re-prompts
    // can scroll back through launches and spot the boot where a key
    // disappeared. Failures are swallowed inside the service —
    // diagnostic must never break startup.
    bool? bootUnlocked;
    try {
      bootUnlocked = await ffi.isUnlocked(handle: handle);
    } catch (_) {
      bootUnlocked = null;
    }
    unawaited(
      CryptoBootLog.instance
          .capture(
            syncHealth: health.name,
            handlePresent: true,
            engineUnlocked: bootUnlocked,
            trigger: 'boot',
          )
          .then(CryptoBootLog.instance.append),
    );

    // Persist any Rust state changes from configureEngine (prevents credential
    // loss if the app crashes before an explicit drain happens).
    if (health == SyncHealthState.healthy) {
      await SyncRecordMixin.flushStartupDeferredOps(handle);

      // Refresh the runtime cache and app DB key now that runtime keys are
      // restored.
      try {
        await cacheRuntimeKeys(handle, ref.read(databaseProvider));
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Startup key-rotation check failed: $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }

      // One-time migration: re-emit enum fields as ints to overwrite any
      // legacy string-encoded winning values still in field_versions from
      // before the .name → .index fix.
      unawaited(
        _reemitSettingsEnumFieldsOnce(handle, ref.read(databaseProvider)),
      );
      try {
        await drainRustStore(handle);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Post-configure drain failed: $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
      BootTimings.mark('createHandle:drainRustStore');

      // Cold-start catch-up. `setAutoSync` enables the driver but does not emit an
      // initial trigger, and on a fresh process `last_sync_time` is None so the
      // Rust-side 5s staleness gate does not help us. Kick explicitly, in the
      // background. Run *after* cacheRuntimeKeys + drainRustStore because all three
      // contend for the same Rust handle mutex. Skip when the engine is not
      // configured (unpaired / needs-password) — onResume would just fail with
      // `sync not configured`.
      if (health == SyncHealthState.healthy) {
        unawaited(
          runPostHealthySyncCatchUp(
            handle: handle,
            db: ref.read(databaseProvider),
            failureLabel: 'Startup catch-up sync failed',
          ),
        );
      }
    }

    return handle;
  }

  /// Re-run the startup credential restore + configure path for an existing
  /// handle. Manual reconnect uses this when a handle was published but the
  /// earlier auto-configure attempt failed before `configureEngine`.
  Future<SyncHealthState> ensureConfigured(ffi.PrismSyncHandle handle) async {
    final inFlight = _ensureConfiguredFuture;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<SyncHealthState> tracked;
    tracked = _ensureConfiguredExclusive(handle).whenComplete(() {
      if (identical(_ensureConfiguredFuture, tracked)) {
        _ensureConfiguredFuture = null;
      }
    });
    _ensureConfiguredFuture = tracked;
    return tracked;
  }

  Future<SyncHealthState> _ensureConfiguredExclusive(
    ffi.PrismSyncHandle handle,
  ) async {
    syncAutoConfigureInProgress.value = true;
    try {
      final health = await _autoConfigureIfReady(handle);
      ref.read(syncHealthProvider.notifier).setState(health);
      if (health == SyncHealthState.healthy) {
        await SyncRecordMixin.flushStartupDeferredOps(handle);
        await runPostHealthySyncCatchUp(
          handle: handle,
          db: ref.read(databaseProvider),
          failureLabel: 'Post-manual-configure catch-up sync failed',
        );
      }
      return health;
    } finally {
      syncAutoConfigureInProgress.value = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Auto-configure on restart
// ---------------------------------------------------------------------------

/// Pure helper: classify the keychain-only health state without touching
/// the FFI handle. Used by `_autoConfigureIfReady` and unit-testable in
/// isolation.
///
/// Returns:
///   * `unpaired`     — sync_id or device identity absent (never paired)
///   * `null`         — credentials present; caller should attempt the
///                      runtime-keys path and may end up healthy / needsPassword
///                      / disconnected depending on what's available
@visibleForTesting
SyncHealthState? classifyHealthFromKeychain({
  required String? syncId,
  required String? deviceId,
  required String? deviceSecret,
}) {
  if (syncId == null || syncId.isEmpty) {
    return SyncHealthState.unpaired;
  }
  if (deviceId == null || deviceId.isEmpty) {
    return SyncHealthState.unpaired;
  }
  if (deviceSecret == null || deviceSecret.isEmpty) {
    return SyncHealthState.unpaired;
  }
  return null;
}

/// Pure helper: decide whether the post-restore wrapped_dek probe should
/// flip the result of `_autoConfigureIfReady` from `healthy` to `needsRewrap`.
///
/// Returns `SyncHealthState.needsRewrap` when the runtime DEK restore
/// succeeded (engine unlocked) but the keychain `wrapped_dek` slot is
/// missing or empty. Otherwise returns `SyncHealthState.healthy`.
@visibleForTesting
SyncHealthState classifyPairReadinessFromWrappedDek(String? wrappedDek) {
  if (!hasStoredWrappedDek(wrappedDek)) {
    return SyncHealthState.needsRewrap;
  }
  return SyncHealthState.healthy;
}

@visibleForTesting
bool hasStoredWrappedDek(String? wrappedDek) =>
    wrappedDek != null && wrappedDek.isNotEmpty;

@visibleForTesting
SyncHealthState classifyHealthFromRuntimeDekRestoreOutcome({
  required RuntimeDekRestoreOutcome outcome,
  required bool wrappedDekPresent,
}) {
  switch (outcome.kind) {
    case RuntimeDekRestoreOutcomeKind.restored:
      return SyncHealthState.healthy;
    case RuntimeDekRestoreOutcomeKind.retryableFailure:
    case RuntimeDekRestoreOutcomeKind.unknownFailure:
      return SyncHealthState.runtimeDekRestoreDeferred;
    case RuntimeDekRestoreOutcomeKind.missing:
    case RuntimeDekRestoreOutcomeKind.terminalFailure:
      return wrappedDekPresent
          ? SyncHealthState.needsPassword
          : SyncHealthState.disconnected;
  }
}

@visibleForTesting
SyncHealthState syncHealthForRestoredRuntimeDekMissingDeviceSecret({
  required Uint8List dekBytes,
  required bool wrappedDekPresent,
}) {
  _zeroBytesBestEffort(dekBytes);
  return wrappedDekPresent
      ? SyncHealthState.needsPassword
      : SyncHealthState.disconnected;
}

/// Pure helper: decide whether fronting migration state blocks startup sync.
///
/// During the per-member fronting migration, old-shape sync state is retired
/// rather than migrated. Any known non-complete mode must therefore skip the
/// seed/configure path and look `unpaired` until reset/re-pair completes.
/// Unknown/null values fail open so a DAO read issue does not strand a device.
@visibleForTesting
SyncHealthState? startupHealthForMigrationMode(String? mode) {
  switch (mode) {
    case 'notStarted':
    case 'deferred':
    case 'upgradeAndKeep':
    case 'startFresh':
    case 'blocked':
    case 'inProgress':
      return SyncHealthState.unpaired;
    default:
      return null;
  }
}

/// Determine sync health and auto-configure if possible.
///
/// Sync health state machine:
///   healthy       — sync configured and working
///   unpaired      — device has never been paired (sync_id/device identity absent)
///   needsPassword — wrapped runtime cache missing, wrapped_dek exists → password modal
///                   (shown by AppShell listening to syncHealthProvider)
///   needsRewrap   — runtime DEK restored cleanly but wrapped_dek missing →
///                   recovery sheet (PIN + mnemonic to regenerate wrapped_dek)
///   disconnected  — credentials gone → reconnect card in sync settings
///
/// Transitions:
///   startup → this method → a sync health state
///   DeviceRevoked WebSocket event → disconnected
///   password entry → Argon2id unlock → healthy
///   PIN + mnemonic via recovery sheet → rewrap_dek FFI → healthy
Future<SyncHealthState> _autoConfigureIfReady(
  ffi.PrismSyncHandle handle,
) async {
  // Check if we have the minimum credentials needed
  final syncId = await _safeReadValue('${_secureStorePrefix}sync_id');
  final deviceId = await _safeReadValue('${_secureStorePrefix}device_id');
  final deviceSecret = await _safeReadValue(
    '${_secureStorePrefix}device_secret',
  );
  // Not paired — distinguished from `healthy` so the post-config block in
  // `createHandle` skips cacheRuntimeKeys/drainRustStore/onResume on a
  // locked handle (which would otherwise emit benign "no DEK loaded"
  // warnings during a fresh install).
  final keychainOnly = classifyHealthFromKeychain(
    syncId: syncId,
    deviceId: deviceId,
    deviceSecret: deviceSecret,
  );
  if (keychainOnly != null) {
    return keychainOnly;
  }

  // Try the fast path: restore runtime keys from the device-bound wrapped DEK.
  final isUnlocked = await ffi.isUnlocked(handle: handle);
  if (!isUnlocked) {
    // Android may reject device-bound unwraps before first unlock; defer
    // instead of surfacing recovery while the cache is still viable.
    if (await _isAndroidDeviceLockedForRuntimeDekUnwrap()) {
      return SyncHealthState.awaitingDeviceUnlock;
    }

    final runtimeDekAad = buildRuntimeDekAad(
      syncId: decodeStoredUtf8(syncId),
      deviceId: decodeStoredUtf8(deviceId),
    );
    final deviceSecretB64 = await _safeReadValue(
      '${_secureStorePrefix}device_secret',
    );
    final dekOutcome = runtimeDekAad == null
        ? const RuntimeDekRestoreOutcome.missing()
        : await _readCachedRuntimeDekForRestoreOutcome(aad: runtimeDekAad);
    final dekBytes = dekOutcome.bytes;

    if (dekBytes != null && deviceSecretB64 == null) {
      final wrappedDek = await _safeReadValue(
        '${_secureStorePrefix}wrapped_dek',
      );
      return syncHealthForRestoredRuntimeDekMissingDeviceSecret(
        dekBytes: dekBytes,
        wrappedDekPresent: hasStoredWrappedDek(wrappedDek),
      );
    }

    if (dekBytes != null && deviceSecretB64 != null) {
      Uint8List? deviceSecretBytes;
      try {
        deviceSecretBytes = base64Decode(deviceSecretB64);
        await ffi.restoreRuntimeKeys(
          handle: handle,
          dek: dekBytes,
          deviceSecret: deviceSecretBytes,
        );
      } catch (e, st) {
        final errorSummary = e is FormatException
            ? 'FormatException'
            : e.runtimeType.toString();
        ErrorReportingService.instance.report(
          'restoreRuntimeKeys failed: $errorSummary',
          severity: ErrorSeverity.error,
          stackTrace: st,
        );
        return SyncHealthState.disconnected;
      } finally {
        _zeroBytesBestEffort(dekBytes);
        final secretBytes = deviceSecretBytes;
        if (secretBytes != null) {
          _zeroBytesBestEffort(secretBytes);
        }
      }
    } else {
      final wrappedDek = await _safeReadValue(
        '${_secureStorePrefix}wrapped_dek',
      );
      return classifyHealthFromRuntimeDekRestoreOutcome(
        outcome: dekOutcome,
        wrappedDekPresent: hasStoredWrappedDek(wrappedDek),
      );
    }
  }

  // Keys are restored — configure the engine
  try {
    await ffi.configureEngine(handle: handle);
    await ffi.setAutoSync(
      handle: handle,
      enabled: true,
      debounceMs: BigInt.from(300),
      retryDelayMs: BigInt.from(30000),
      maxRetries: 3,
    );

    // Safety-net backfill: derive and cache the local storage key if the
    // keychain slot is empty. With always-on encryption (Signal model),
    // ensureLocalDatabaseKey() populates this slot at first launch, so this
    // guard is normally a no-op. It remains as defense-in-depth for edge
    // cases (e.g. upgrade from a very old version).
    try {
      final existingDbKey = await readDatabaseKeyHex();
      if (existingDbKey == null) {
        final lskBytes = await ffi.localStorageKey(handle: handle);
        await cacheDatabaseKey(Uint8List.fromList(lskBytes));
        debugPrint(
          '[SYNC] Backfilled database encryption key from local_storage_key',
        );
      }
    } catch (e) {
      debugPrint('[SYNC] Failed to backfill database key (non-fatal): $e');
    }

    // Cold-start catch-up sync is scheduled as fire-and-forget in
    // `createHandle()` after `cacheRuntimeKeys` + `drainRustStore`, so it does
    // not block startup. See the `unawaited(...)` block there.

    // Pair-readiness probe: the runtime DEK survived but `wrapped_dek` may
    // have been lost from the keychain (rare iOS anomaly during version
    // downgrade/upgrade). Sync still works because the DEK is in RAM, but
    // pairing another device reads `wrapped_dek` to derive the joiner
    // bundle and would fail. Surface `needsRewrap` so the user can
    // regenerate it via PIN + mnemonic.
    final wrappedDekAfterRestore = await _safeReadValue(
      '${_secureStorePrefix}wrapped_dek',
    );
    return classifyPairReadinessFromWrappedDek(wrappedDekAfterRestore);
  } catch (e, st) {
    ErrorReportingService.instance.report(
      'Auto-configure sync failed: $e',
      severity: ErrorSeverity.error,
      stackTrace: st,
    );
    return SyncHealthState.disconnected;
  }
}

// ---------------------------------------------------------------------------
// SecureStore seed/drain bridge
// ---------------------------------------------------------------------------

const _secureStorePrefix = 'prism_sync.';

/// Platform-keychain keys that must survive a sync-only reset.
///
/// Everything under the `prism_sync.` namespace is wiped during reset
/// EXCEPT these slots, which hold the local-storage Signal-style DEK that
/// encrypts the app's Drift database. Clearing them makes the app DB
/// permanently unreadable until the user wipes data, so we treat them as
/// per-device persistence keys separate from sync credentials.
///
/// Tests assert against this set directly (via the re-export in
/// `reset_data_provider.dart`) to avoid hand-copying the names — adding
/// or removing a protected slot here is the single source of truth.
const kProtectedFromReset = <String>{
  '${_secureStorePrefix}database_key',
  '${_secureStorePrefix}database_key_staging',
  '${_secureStorePrefix}sync_database_key',
  '${_secureStorePrefix}sync_database_key_staging',
};

/// Keys that prism-sync stores in SecureStore.
///
/// Note: the BIP39 recovery phrase (`mnemonic`) is deliberately not here —
/// it is an offline backup credential and is not persisted to the keychain.
/// Users re-type it from their saved backup when changing their PIN or
/// pairing another device. `computeKeysToClearOnReset` and
/// `_wipeSyncKeychainEntries` still list `mnemonic` defensively so that any
/// legacy entry from earlier builds gets wiped on reset/revoke.
const _secureStoreKeys = [
  'wrapped_dek',
  'dek_salt',
  'device_secret',
  'device_id',
  'sync_id',
  'session_token',
  'epoch',
  'relay_url',
  'registration_token',
  'setup_rollback_marker',
  'sharing_prekey_store',
  'sharing_id_cache',
  'min_signature_version_floor',
];

/// Legacy raw runtime-DEK cache key. Kept only so startup can migrate/delete
/// old plaintext/base64 caches; new writes must use [kRuntimeDekWrappedKey].
const kRuntimeDekKey = '${_secureStorePrefix}runtime_dek';

/// Device-bound wrapped runtime-DEK cache key. The value is JSON metadata plus
/// AEAD ciphertext produced by [DeviceBoundRuntimeDekStore].
const kRuntimeDekWrappedKey = '${_secureStorePrefix}runtime_dek_wrapped_v1';

/// Device identity persisted by prism-sync.
const kSyncDeviceIdKey = '${_secureStorePrefix}device_id';

/// Device secret persisted by prism-sync.
const kSyncDeviceSecretKey = '${_secureStorePrefix}device_secret';

/// Durable marker written only after the joiner snapshot has applied locally.
const kSnapshotApplyCompleteKey =
    '${_secureStorePrefix}snapshot_apply_complete_v1';

const _runtimeDekStore = DeviceBoundRuntimeDekStore();

Future<Uint8List> _unwrapRuntimeDek(String blob, String aad) {
  return _runtimeDekStore.unwrap(blob, aad: aad);
}

Future<String> _wrapRuntimeDek(Uint8List dekBytes, String aad) {
  return _runtimeDekStore.wrap(dekBytes, aad: aad);
}

// ---------------------------------------------------------------------------
// Module-internal classified helpers (Prism 0.9.2 secure storage remediation §2)
// ---------------------------------------------------------------------------
//
// These wrappers preserve the existing call shape (return `String?` for reads,
// fire-and-forget semantics for writes/deletes that were already best-effort)
// while routing through the classified secure-storage wrappers. Cipher /
// transient / unknown failures are swallowed at the call site — every read
// resolves to null, every write/delete returns. The callers in this file
// already treat secure-storage failures as soft failures (the surrounding
// retry / health-classifier logic re-runs on the next event).
//
// Where the failure shape matters (e.g. credential cleanup that should mark
// the syncCredentials slot unreadable), the call site sets the
// [KeychainDegradedState] slot directly via `KeychainDegradedStateService`.

Future<String?> _safeReadValue(String key) async =>
    (await safeSecureRead(key)).value;

Future<Map<String, String>> _safeReadAllEntries() async {
  final result = await safeSecureReadAll();
  if (!result.ok) {
    throw StateError(
      'secure storage readAll failed '
      '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
      'message=${result.message})',
    );
  }
  return result.entries;
}

Future<void> _checkedWriteValue(String key, String value) async {
  final result = await safeSecureWrite(key, value);
  if (!result.ok) {
    throw StateError(
      'secure storage write failed for $key '
      '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
      'message=${result.message})',
    );
  }
}

Future<void> _checkedDeleteKey(String key) async {
  final result = await safeSecureDelete(key);
  if (!result.ok) {
    throw StateError(
      'secure storage delete failed for $key '
      '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
      'message=${result.message})',
    );
  }
}

Future<void> _bestEffortDeleteKey(String key) async {
  await safeSecureDelete(key);
}

@visibleForTesting
String? decodeStoredUtf8(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(raw));
  } catch (_) {
    return raw;
  }
}

bool hasCompletePersistentSyncIdentity({
  required String? relayUrl,
  required String? syncId,
  required String? deviceId,
  required bool hasDeviceSecret,
}) {
  return relayUrl != null &&
      relayUrl.isNotEmpty &&
      syncId != null &&
      syncId.isNotEmpty &&
      deviceId != null &&
      deviceId.isNotEmpty &&
      hasDeviceSecret;
}

enum PersistentSyncIdentityState { complete, absent, partial, unreadable }

PersistentSyncIdentityState classifyPersistentSyncIdentity({
  required String? relayUrl,
  required String? syncId,
  required String? deviceId,
  required String? deviceSecret,
}) {
  final presentCount = <String?>[
    relayUrl,
    syncId,
    deviceId,
    deviceSecret,
  ].where((value) => value != null && value.isNotEmpty).length;
  if (presentCount == 0) return PersistentSyncIdentityState.absent;
  if (presentCount == 4) return PersistentSyncIdentityState.complete;
  return PersistentSyncIdentityState.partial;
}

Future<PersistentSyncIdentityState> _readPersistentSyncIdentityState() async {
  final relayUrl = await safeSecureRead(kSyncRelayUrlKey);
  final syncId = await safeSecureRead(kSyncIdKey);
  final deviceId = await safeSecureRead(kSyncDeviceIdKey);
  final deviceSecret = await safeSecureRead(kSyncDeviceSecretKey);
  if (!relayUrl.ok || !syncId.ok || !deviceId.ok || !deviceSecret.ok) {
    return PersistentSyncIdentityState.unreadable;
  }
  return classifyPersistentSyncIdentity(
    relayUrl: relayUrl.value,
    syncId: syncId.value,
    deviceId: deviceId.value,
    deviceSecret: deviceSecret.value,
  );
}

Future<void> _discardUnpairedSyncDatabase({
  required String dbPath,
  ffi.PrismSyncHandle? currentHandle,
}) async {
  try {
    if (identical(syncCurrentHandle.value, currentHandle)) {
      syncCurrentHandle.value = null;
    }
    currentHandle?.dispose();
  } catch (e) {
    debugPrint('[SYNC] handle.dispose() before unpaired DB discard threw: $e');
  }

  for (final suffix in const <String>['', '-shm', '-wal', '-journal']) {
    final file = File('$dbPath$suffix');
    if (!file.existsSync()) continue;
    try {
      file.deleteSync();
    } catch (e) {
      debugPrint('[SYNC] Failed to delete unpaired sync DB$suffix: $e');
    }
  }

  await _bestEffortDeleteKey(kSyncDatabaseKeyStorageKey);
  await _bestEffortDeleteKey('${kSyncDatabaseKeyStorageKey}_staging');
}

String snapshotApplyCompleteMarkerValue({
  required String syncId,
  required String deviceId,
}) {
  return '$syncId\n$deviceId';
}

bool snapshotApplyCompleteMarkerMatches({
  required String? marker,
  required String syncId,
  required String deviceId,
}) {
  return marker ==
      snapshotApplyCompleteMarkerValue(syncId: syncId, deviceId: deviceId);
}

void _zeroBytesBestEffort(List<int>? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Some platform-channel byte views are immutable. The restore path copies
    // secrets before use, but scrubbing must never mask the real sync result.
  }
}

@visibleForTesting
String? buildRuntimeDekAad({
  required String? syncId,
  required String? deviceId,
}) {
  if (syncId == null ||
      syncId.isEmpty ||
      deviceId == null ||
      deviceId.isEmpty) {
    return null;
  }
  return '$syncId|$deviceId|1';
}

/// Prefixes for dynamic secure-store entries that the Rust side may write
/// at runtime (epoch rotation recovery, runtime key blobs). These are NOT
/// in `_secureStoreKeys` because they vary by epoch number / family.
///
/// `_seedRustStore` must restore them so that a device which recovered
/// `epoch_key_1` in a previous session can still push at epoch 1 after a
/// restart — otherwise `key_hierarchy.epoch_key(1)` returns `None` and
/// the engine errors with "Missing epoch key for push epoch 1".
const _dynamicSecureStorePrefixes = ['epoch_key_', 'runtime_keys_'];

/// End-to-end seed request builder.
///
/// Takes the output of [safeSecureReadAll] and returns the
/// binary map that `_seedRustStore` passes into `ffi.seedSecureStore`,
/// or `null` if there are no entries to seed. Platform keychain values
/// stay base64 strings at rest, but the FFI boundary receives bytes.
///
/// Used by `_seedRustStore` and by unit tests that want to verify the
/// full read + filter + decode pipeline without a real FFI handle.
@visibleForTesting
Map<String, Uint8List>? buildSeedEntries(Map<String, String> keychainContents) {
  final entries = computeSeedEntries(keychainContents);
  if (entries.isEmpty) return null;
  return decodeSeedEntries(entries);
}

@visibleForTesting
Map<String, Uint8List> decodeSeedEntries(Map<String, String> entries) {
  return entries.map((key, value) => MapEntry(key, base64Decode(value)));
}

@visibleForTesting
Map<String, String> encodeDrainedEntries(Map<String, Uint8List> entries) {
  return entries.map((key, value) => MapEntry(key, base64Encode(value)));
}

/// Compute the set of (un-prefixed) secure-store entries that should be
/// seeded into Rust, given the raw keychain contents.
///
/// Pure function — takes a `readAll()`-style map keyed by the full
/// platform-keychain keys (with `prism_sync.` prefix) and returns the
/// bare key -> base64 map that [buildSeedEntries] decodes before FFI.
/// Extracted so unit tests can exercise the "dynamic prefix scan"
/// behavior without touching `FlutterSecureStorage`.
@visibleForTesting
Map<String, String> computeSeedEntries(Map<String, String> all) {
  final entries = <String, String>{};

  // 1. Static allow-list lookups — explicit keys we know we care about.
  for (final key in _secureStoreKeys) {
    final full = '$_secureStorePrefix$key';
    final value = all[full];
    if (value != null) {
      entries[key] = value; // Already base64-encoded
    }
  }

  // 2. Dynamic-prefix scan — `epoch_key_*` and `runtime_keys_*`.
  for (final entry in all.entries) {
    final fullKey = entry.key;
    if (!fullKey.startsWith(_secureStorePrefix)) continue;
    final bareKey = fullKey.substring(_secureStorePrefix.length);
    if (entries.containsKey(bareKey)) continue;
    final isDynamic = _dynamicSecureStorePrefixes.any(bareKey.startsWith);
    if (isDynamic) {
      entries[bareKey] = entry.value;
    }
  }

  return entries;
}

/// Compute the full-keychain keys that should be deleted by the
/// reset/revoke cleanup path, given the current keychain contents.
///
/// Inclusion-by-prefix: returns every `prism_sync.*` entry currently
/// stored, minus the DB-encryption slots in [kProtectedFromReset]. This
/// keeps parity with `_resetSyncSystem` in `reset_data_provider.dart` —
/// the static allow-list approach used to silently leak transient
/// pairing keys (`bootstrap_joiner_bundle`, `pending_sync_id`,
/// `registration_token`, etc.) that nobody remembered to add.
List<String> computeKeysToClearOnReset(Map<String, String> all) {
  final out = <String>[];
  for (final fullKey in all.keys) {
    if (!fullKey.startsWith(_secureStorePrefix)) continue;
    if (kProtectedFromReset.contains(fullKey)) continue;
    out.add(fullKey);
  }
  return out;
}

/// Seed the Rust-side MemorySecureStore with values from platform keychain.
///
/// Reads both the static `_secureStoreKeys` allow-list and any dynamic
/// keys whose (un-prefixed) name begins with one of
/// `_dynamicSecureStorePrefixes` (`epoch_key_*`, `runtime_keys_*`). The
/// `readAll()` scan catches every entry regardless of how many epoch keys
/// have accumulated across rekey cycles.
Future<void> _seedRustStore(ffi.PrismSyncHandle handle) async {
  Map<String, String> all;
  try {
    all = await _safeReadAllEntries();
  } catch (e, st) {
    // `readAll()` is best-effort: if the keychain fails we still try
    // the static keys individually. The auto-sync driver will recover
    // any missing epoch key via `recover_epoch_key` on the next
    // WebSocket notification.
    ErrorReportingService.instance.report(
      'Dynamic secure-store seed scan failed (non-fatal): $e',
      severity: ErrorSeverity.warning,
      stackTrace: st,
    );
    all = <String, String>{};
    for (final key in _secureStoreKeys) {
      final value = await _safeReadValue('$_secureStorePrefix$key');
      if (value != null) all['$_secureStorePrefix$key'] = value;
    }
  }

  final entries = buildSeedEntries(all);
  if (entries != null) {
    await ffi.seedSecureStore(handle: handle, entries: entries);
  }
}

/// Read the current `pending_fronting_migration_mode` from the
/// `system_settings` row, returning `null` if the DAO read throws (e.g.
/// the database isn't open yet, or the column doesn't exist on this
/// schema version). Defensive — startup only needs this to detect the
/// `inProgress` state, and any failure here means we fall back to the
/// normal seed/configure path.
Future<String?> _readPendingFrontingMigrationMode(Ref ref) async {
  try {
    final db = ref.read(databaseProvider);
    return await db.systemSettingsDao.readPendingFrontingMigrationMode();
  } catch (_) {
    return null;
  }
}

/// Wipe every sync-related entry from the platform keychain.
///
/// Mirrors `SyncStatusNotifier._wipeSyncKeychainEntries` but exposed as a
/// top-level function so the per-member fronting migration can call it
/// from outside the notifier graph (the migration runs as a service, not
/// a notifier, and shouldn't depend on the SyncStatus notifier's
/// debounce/post-revoke state).
///
/// Without this, a backgrounded app between the migration's
/// `reset_sync_state` and the next launch would re-seed Rust from the
/// still-present `wrapped_dek` / `sync_id` / `device_secret` / etc. and
/// silently re-attach to the OLD sync group. Idempotent — wiping
/// already-wiped slots is a no-op.
///
/// Reads the persisted sync_id from the platform keychain for the
/// [FrontingMigrationService.resumeCleanup] path.
///
/// Background: when app startup detects the migration's `inProgress`
/// marker, it intentionally skips both `_seedRustStore` and
/// `_autoConfigureIfReady` (so a backgrounded app between FFI reset
/// and keychain wipe doesn't re-seed credentials about to be wiped).
/// That leaves the published handle UNCONFIGURED — `reset_sync_state`
/// against it would return `"sync_id not set"` because it queries the
/// live engine for the sync_id.
///
/// The previous implementation worked around this by configuring the
/// engine just-enough (seed secure store + restore runtime keys +
/// configureEngine), then calling `reset_sync_state`. That path had
/// a latent bug: `configure_engine` constructs the relay AND calls
/// `connect_websocket` BEFORE the reset runs, which contradicts the
/// "no relay round-trip" requirement of the cutover and could briefly
/// reconnect to the still-paired old sync group, possibly leaving a
/// background reconnect loop.
///
/// Fix: read the sync_id directly from the keychain (the wipe step is
/// GATED on the reset succeeding first, so the keychain entries are
/// intact when this runs) and pass it to `clear_sync_state(sync_id)`,
/// which is a surgical storage-only wipe with no engine configuration
/// and no relay touch.
///
/// Returns null when no sync_id is stored — the resume path treats
/// that as "nothing left to clear" and advances substate so the
/// remaining cleanup steps proceed.
Future<String?> readFrontingMigrationSyncId() async {
  final raw = await _safeReadValue(kSyncIdKey);
  if (raw == null || raw.isEmpty) return null;
  // Keychain values are base64-encoded by convention (see [syncIdProvider]),
  // with a plaintext fallback for legacy installs.
  try {
    return utf8.decode(base64Decode(raw));
  } catch (_) {
    return raw;
  }
}

/// Secure-store keys not tracked by `_secureStoreKeys` (the seed allow-list)
/// that the wipe path still needs to clear. `mnemonic` is kept here as a
/// defensive entry — the BIP39 mnemonic is normally never persisted (see
/// the comment on `_secureStoreKeys`), but earlier builds may have left
/// one behind. Runtime DEK cache slots are not seed material so they never
/// appear in `_secureStoreKeys`, but both legacy raw and current wrapped slots
/// must be wiped on reset.
const _legacyWipeOnlyKeys = [
  'mnemonic',
  'runtime_dek',
  'runtime_dek_wrapped_v1',
  'runtime_dek_linux_wrap_key_v1',
  'snapshot_apply_complete_v1',
];

/// Returns the full set of unprefixed secure-store keys used when a platform
/// keychain cannot provide a prefix scan. Tests pin this fallback contract so
/// every static seed entry plus wipe-only legacy entry remains covered.
Set<String> frontingMigrationWipeStaticKeys() {
  return {..._secureStoreKeys, ..._legacyWipeOnlyKeys};
}

/// Returns the dynamic prefixes the wipe path scans for after the static
/// pass. Exposed for tests.
@visibleForTesting
List<String> frontingMigrationWipeDynamicPrefixes() {
  return List.unmodifiable(_dynamicSecureStorePrefixes);
}

Set<String> _staticSyncCredentialWipeFallbackKeys() {
  return {
    for (final key in frontingMigrationWipeStaticKeys())
      '$_secureStorePrefix$key',
  }..removeAll(kProtectedFromReset);
}

Future<int> _deleteSyncCredentialKeychainEntries({
  required Future<Map<String, String>> Function() readAll,
  required Future<void> Function(String key) deleteKey,
  void Function(String message)? log,
}) async {
  Set<String> keysToDelete;
  try {
    keysToDelete = computeKeysToClearOnReset(await readAll()).toSet();
  } catch (e) {
    // Best-effort fallback for platform keychains where readAll() fails or is
    // unavailable: delete every known static sync credential/cache slot.
    log?.call(
      'Keychain readAll failed during sync wipe; using fallback list: $e',
    );
    keysToDelete = _staticSyncCredentialWipeFallbackKeys();
  }

  var deleted = 0;
  for (final fullKey in keysToDelete) {
    try {
      await deleteKey(fullKey);
      deleted++;
    } catch (e) {
      // Best effort — continue clearing remaining keys.
      log?.call('Keychain delete failed for $fullKey (non-fatal): $e');
    }
  }
  return deleted;
}

/// Wipe every `prism_sync.*` keychain entry except [kProtectedFromReset].
///
/// This is the single shared entry point used by both the sync-reset path
/// (`_resetSyncSystem`) and the pairing-failure cleanup path
/// (`_cleanupKeychainOnFailure`). Inclusion-by-prefix via `readAll()` catches
/// dynamic key families (`epoch_key_*`, `runtime_keys_*`, transient
/// `pending_*`, `setup_rollback_marker`, `bootstrap_joiner_bundle`, etc.)
/// that the older static allow-lists silently drifted away from.
///
/// On `readAll()` failure the helper falls back to the static wipe list
/// returned by [frontingMigrationWipeStaticKeys] (with [kProtectedFromReset]
/// removed) so reset/pair cleanup still makes forward progress on platforms
/// where prefix scans fail.
///
/// When [includeRuntimeDekWrappingKey] is true the AndroidKeystore-backed
/// wrapping key handled by [DeviceBoundRuntimeDekStore] is also deleted.
/// Reset-style callers pass `true`; the pairing-failure cleanup path passes
/// `false` because the wrapping key is a per-device construct that must
/// survive a failed pairing attempt (the user's existing wrapped runtime DEK
/// is unwrapped with it on every launch).
///
/// All read/delete failures are logged via [log] (when supplied) and
/// swallowed — best-effort cleanup must not throw out of either caller.
///
/// Returns the number of entries that were successfully deleted (useful for
/// diagnostics; safe to ignore).
///
/// [readAll] / [deleteKey] are pluggable so the reset path can route through
/// its `ResetSecureStore` abstraction while the pairing path can route
/// through the top-level `secureStorage`. [deleteWrappingKey] is exposed as
/// a test seam; production callers should leave it null.
Future<int> wipeSyncKeychainNamespace({
  required Future<Map<String, String>> Function() readAll,
  required Future<void> Function(String key) deleteKey,
  bool includeRuntimeDekWrappingKey = false,
  Future<void> Function()? deleteWrappingKey,
  void Function(String message)? log,
}) async {
  final deleted = await _deleteSyncCredentialKeychainEntries(
    readAll: readAll,
    deleteKey: deleteKey,
    log: log,
  );

  if (includeRuntimeDekWrappingKey) {
    final wrappingKeyDeleter =
        deleteWrappingKey ?? _runtimeDekStore.deleteWrappingKey;
    try {
      await wrappingKeyDeleter();
    } catch (e) {
      log?.call('Runtime DEK wrapping-key delete failed (non-fatal): $e');
    }
  }

  return deleted;
}

Future<void> _clearBiometricSyncDekBestEffort([Ref? ref]) async {
  try {
    if (ref != null) {
      await ref.read(biometricServiceProvider).clear();
    } else {
      await BiometricService().clear();
    }
  } catch (_) {
    // Best effort — the regular keychain wipe may already have removed the
    // non-biometric copy, and reset/revoke cleanup must continue.
  }
}

Future<void> wipeFrontingMigrationSyncKeychain() async {
  await _deleteSyncCredentialKeychainEntries(
    readAll: _safeReadAllEntries,
    deleteKey: _checkedDeleteKey,
  );
  try {
    await _runtimeDekStore.deleteWrappingKey();
  } catch (_) {
    // Best effort — the wrapped blob was already deleted above.
  }
  await _clearBiometricSyncDekBestEffort();
}

class _UnwrapAttempt {
  const _UnwrapAttempt({
    this.bytes,
    required this.classification,
    this.error,
    this.stackTrace,
  });

  final Uint8List? bytes;
  final RuntimeDekUnwrapClassification classification;
  final Object? error;
  final StackTrace? stackTrace;
}

enum RuntimeDekRestoreOutcomeKind {
  restored,
  missing,
  retryableFailure,
  unknownFailure,
  terminalFailure,
}

@visibleForTesting
class RuntimeDekRestoreOutcome {
  const RuntimeDekRestoreOutcome._(this.kind, {this.bytes, this.failure});

  const RuntimeDekRestoreOutcome.restored(Uint8List bytes)
    : this._(RuntimeDekRestoreOutcomeKind.restored, bytes: bytes);

  const RuntimeDekRestoreOutcome.missing()
    : this._(RuntimeDekRestoreOutcomeKind.missing);

  const RuntimeDekRestoreOutcome.retryableFailure(
    RuntimeDekUnwrapFailure failure,
  ) : this._(RuntimeDekRestoreOutcomeKind.retryableFailure, failure: failure);

  const RuntimeDekRestoreOutcome.unknownFailure(RuntimeDekUnwrapFailure failure)
    : this._(RuntimeDekRestoreOutcomeKind.unknownFailure, failure: failure);

  const RuntimeDekRestoreOutcome.terminalFailure(
    RuntimeDekUnwrapFailure failure,
  ) : this._(RuntimeDekRestoreOutcomeKind.terminalFailure, failure: failure);

  final RuntimeDekRestoreOutcomeKind kind;
  final Uint8List? bytes;
  final RuntimeDekUnwrapFailure? failure;

  bool get hasBytes => bytes != null;
  bool get isCachePreservedFailure =>
      kind == RuntimeDekRestoreOutcomeKind.retryableFailure ||
      kind == RuntimeDekRestoreOutcomeKind.unknownFailure;
}

Future<_UnwrapAttempt> _tryUnwrapForRestore({
  required String blob,
  required String aad,
  required Future<Uint8List> Function(String blob, String aad) unwrapDek,
  required RuntimeDekUnwrapClassification Function(Object error) classify,
}) async {
  try {
    final bytes = Uint8List.fromList(await unwrapDek(blob, aad));
    return _UnwrapAttempt(
      bytes: bytes,
      classification: RuntimeDekUnwrapClassification.unknown,
    );
  } catch (e, st) {
    return _UnwrapAttempt(
      classification: classify(e),
      error: e,
      stackTrace: st,
    );
  }
}

@visibleForTesting
Future<RuntimeDekRestoreOutcome> readCachedRuntimeDekForRestoreOutcomeCore({
  required String aad,
  required Future<String?> Function(String key) readKey,
  required Future<void> Function(String key) deleteKey,
  required Future<void> Function(String key, String value) writeKey,
  required Future<Uint8List> Function(String blob, String aad) unwrapDek,
  required Future<String> Function(Uint8List dekBytes, String aad) wrapDek,
  RuntimeDekUnwrapClassification Function(Object error)? classifyError,
  void Function(RuntimeDekUnwrapFailure failure)? recordFailure,
  void Function()? clearFailureRecord,
  void Function(String message, Object error, StackTrace stackTrace)?
  reportWarning,
}) async {
  final classify = classifyError ?? classifyRuntimeDekUnwrapError;
  final record = recordFailure ?? RuntimeDekUnwrapFailureRegistry.record;
  final clearRecord =
      clearFailureRecord ?? RuntimeDekUnwrapFailureRegistry.clear;

  RuntimeDekUnwrapFailure buildFailure({
    required _UnwrapAttempt attempt,
    required RuntimeDekUnwrapClassification classification,
    required int attempts,
    required bool cachePreserved,
  }) {
    final details = attempt.error is PlatformException
        ? (attempt.error as PlatformException).details
        : null;
    final detailsMap = details is Map ? details : const {};
    final deviceState = detailsMap['device_state'];
    final deviceStateMap = deviceState is Map ? deviceState : const {};

    int? intDetail(String key) {
      final value = detailsMap[key];
      return value is num ? value.toInt() : null;
    }

    bool? boolDetail(String key) {
      final value = detailsMap[key];
      return value is bool ? value : null;
    }

    String? stringDetail(String key) {
      final value = detailsMap[key];
      return value is String ? value : null;
    }

    bool? deviceBool(String key) {
      final value = deviceStateMap[key];
      return value is bool ? value : null;
    }

    String? errorCodeOf(Object? e) => e is PlatformException ? e.code : null;
    String? errorMessageOf(Object? e) {
      if (e == null) return null;
      if (e is PlatformException) return e.message;
      if (e is FormatException) return e.message;
      return e.runtimeType.toString();
    }

    return RuntimeDekUnwrapFailure(
      classification: classification,
      errorCode: errorCodeOf(attempt.error),
      errorMessage: errorMessageOf(attempt.error),
      attempts: attempts,
      cachePreserved: cachePreserved,
      timestamp: DateTime.now().toUtc(),
      retryPolicy: intDetail('retry_policy'),
      backoffHintMillis: intDetail('backoff_hint_millis'),
      isTransientFailure: boolDetail('is_transient_failure'),
      requiresUserAuthentication: boolDetail('requires_user_authentication'),
      isSystemError: boolDetail('is_system_error'),
      numericErrorCode: intDetail('numeric_error_code'),
      throwableClass: stringDetail('throwable_class'),
      rootCauseClass: stringDetail('root_cause_class'),
      deviceLocked: deviceBool('is_device_locked'),
      userUnlocked: deviceBool('is_user_unlocked'),
    );
  }

  RuntimeDekRestoreOutcome outcomeForFailure(RuntimeDekUnwrapFailure failure) {
    return switch (failure.classification) {
      RuntimeDekUnwrapClassification.transient =>
        RuntimeDekRestoreOutcome.retryableFailure(failure),
      RuntimeDekUnwrapClassification.terminal =>
        RuntimeDekRestoreOutcome.terminalFailure(failure),
      RuntimeDekUnwrapClassification.unknown =>
        RuntimeDekRestoreOutcome.unknownFailure(failure),
    };
  }

  RuntimeDekRestoreOutcome fallbackOutcome({
    RuntimeDekUnwrapFailure? preservedFailure,
    RuntimeDekUnwrapFailure? terminalFailure,
  }) {
    if (preservedFailure != null) return outcomeForFailure(preservedFailure);
    if (terminalFailure != null) {
      return RuntimeDekRestoreOutcome.terminalFailure(terminalFailure);
    }
    return const RuntimeDekRestoreOutcome.missing();
  }

  Object reportErrorObject(RuntimeDekUnwrapFailure failure, Object? error) {
    return error ?? StateError('unknown ${failure.classification.name}');
  }

  StackTrace reportStackTrace(_UnwrapAttempt attempt) =>
      attempt.stackTrace ?? StackTrace.empty;

  RuntimeDekUnwrapFailure? preservedFailure;
  RuntimeDekUnwrapFailure? terminalFailure;

  final wrapped = await readKey(kRuntimeDekWrappedKey);
  if (wrapped != null && wrapped.isNotEmpty) {
    final firstAttempt = await _tryUnwrapForRestore(
      blob: wrapped,
      aad: aad,
      unwrapDek: unwrapDek,
      classify: classify,
    );
    if (firstAttempt.bytes != null) {
      await deleteKey(kRuntimeDekKey);
      clearRecord();
      return RuntimeDekRestoreOutcome.restored(firstAttempt.bytes!);
    }

    // Retry once on transient failures (Android Keystore device-lock race
    // or StrongBox flake commonly resolve on a second attempt).
    if (firstAttempt.classification ==
        RuntimeDekUnwrapClassification.transient) {
      final secondAttempt = await _tryUnwrapForRestore(
        blob: wrapped,
        aad: aad,
        unwrapDek: unwrapDek,
        classify: classify,
      );
      if (secondAttempt.bytes != null) {
        await deleteKey(kRuntimeDekKey);
        clearRecord();
        return RuntimeDekRestoreOutcome.restored(secondAttempt.bytes!);
      }
      // Retry also failed — leave the cache alone for the next launch.
      final failure = buildFailure(
        attempt: secondAttempt.error != null ? secondAttempt : firstAttempt,
        classification: RuntimeDekUnwrapClassification.transient,
        attempts: 2,
        cachePreserved: true,
      );
      preservedFailure = failure;
      record(failure);
      reportWarning?.call(
        'Wrapped runtime DEK transient unwrap failed twice; cache '
        'preserved for next launch.',
        reportErrorObject(failure, secondAttempt.error ?? firstAttempt.error),
        reportStackTrace(
          secondAttempt.error != null ? secondAttempt : firstAttempt,
        ),
      );
    } else if (firstAttempt.classification ==
        RuntimeDekUnwrapClassification.terminal) {
      // Blob can't be unwrapped by any key we hold — discard so the next
      // successful unlock writes a fresh one.
      await deleteKey(kRuntimeDekWrappedKey);
      final failure = buildFailure(
        attempt: firstAttempt,
        classification: RuntimeDekUnwrapClassification.terminal,
        attempts: 1,
        cachePreserved: false,
      );
      terminalFailure = failure;
      record(failure);
      reportWarning?.call(
        'Wrapped runtime DEK terminal unwrap failure; cache deleted.',
        reportErrorObject(failure, firstAttempt.error),
        reportStackTrace(firstAttempt),
      );
    } else {
      // Unknown failure mode — preserve the cache conservatively.
      final failure = buildFailure(
        attempt: firstAttempt,
        classification: RuntimeDekUnwrapClassification.unknown,
        attempts: 1,
        cachePreserved: true,
      );
      preservedFailure = failure;
      record(failure);
      reportWarning?.call(
        'Wrapped runtime DEK unwrap failed with unclassified error; '
        'cache preserved.',
        reportErrorObject(failure, firstAttempt.error),
        reportStackTrace(firstAttempt),
      );
    }
  }

  final legacyRaw = await readKey(kRuntimeDekKey);
  if (legacyRaw == null || legacyRaw.isEmpty) {
    return fallbackOutcome(
      preservedFailure: preservedFailure,
      terminalFailure: terminalFailure,
    );
  }

  Uint8List dekBytes;
  try {
    dekBytes = Uint8List.fromList(base64Decode(legacyRaw));
  } catch (e, st) {
    await deleteKey(kRuntimeDekKey);
    reportWarning?.call(
      'Legacy runtime DEK cache was invalid; cache deleted.',
      e,
      st,
    );
    return fallbackOutcome(
      preservedFailure: preservedFailure,
      terminalFailure: terminalFailure,
    );
  }

  if (dekBytes.length != 32) {
    _zeroBytesBestEffort(dekBytes);
    await deleteKey(kRuntimeDekKey);
    return fallbackOutcome(
      preservedFailure: preservedFailure,
      terminalFailure: terminalFailure,
    );
  }

  try {
    final migrated = await wrapDek(dekBytes, aad);
    await writeKey(kRuntimeDekWrappedKey, migrated);
    await deleteKey(kRuntimeDekKey);
    clearRecord();
    return RuntimeDekRestoreOutcome.restored(dekBytes);
  } catch (e, st) {
    final classification = classify(e);
    if (classification != RuntimeDekUnwrapClassification.terminal) {
      reportWarning?.call(
        'Legacy runtime DEK migration failed; raw cache preserved for next launch.',
        e,
        st,
      );
      final fallbackFailure = preservedFailure ?? terminalFailure;
      if (fallbackFailure != null) {
        record(fallbackFailure);
      }
      return RuntimeDekRestoreOutcome.restored(dekBytes);
    }

    _zeroBytesBestEffort(dekBytes);
    await deleteKey(kRuntimeDekKey);
    reportWarning?.call(
      'Legacy runtime DEK migration failed; raw cache deleted.',
      e,
      st,
    );
    return fallbackOutcome(
      preservedFailure: preservedFailure,
      terminalFailure: terminalFailure,
    );
  }
}

@visibleForTesting
Future<Uint8List?> readCachedRuntimeDekForRestoreCore({
  required String aad,
  required Future<String?> Function(String key) readKey,
  required Future<void> Function(String key) deleteKey,
  required Future<void> Function(String key, String value) writeKey,
  required Future<Uint8List> Function(String blob, String aad) unwrapDek,
  required Future<String> Function(Uint8List dekBytes, String aad) wrapDek,
  RuntimeDekUnwrapClassification Function(Object error)? classifyError,
  void Function(RuntimeDekUnwrapFailure failure)? recordFailure,
  void Function()? clearFailureRecord,
  void Function(String message, Object error, StackTrace stackTrace)?
  reportWarning,
}) async {
  final outcome = await readCachedRuntimeDekForRestoreOutcomeCore(
    aad: aad,
    readKey: readKey,
    deleteKey: deleteKey,
    writeKey: writeKey,
    unwrapDek: unwrapDek,
    wrapDek: wrapDek,
    classifyError: classifyError,
    recordFailure: recordFailure,
    clearFailureRecord: clearFailureRecord,
    reportWarning: reportWarning,
  );
  return outcome.bytes;
}

@visibleForTesting
Duration runtimeDekRestoreRetryDelay(RuntimeDekUnwrapFailure? failure) {
  final hinted = failure?.backoffHintMillis;
  if (hinted != null && hinted > 0) {
    final clamped = hinted.clamp(100, 1200).toInt();
    return Duration(milliseconds: clamped);
  }
  return const Duration(milliseconds: 250);
}

@visibleForTesting
Future<RuntimeDekRestoreOutcome> retryRuntimeDekRestoreCore({
  required Future<RuntimeDekRestoreOutcome> Function() readOnce,
  Future<void> Function(Duration duration)? delay,
  int maxRetries = 1,
}) async {
  final delayFn = delay ?? Future<void>.delayed;
  var outcome = await readOnce();
  for (var retry = 0; retry < maxRetries; retry++) {
    if (outcome.kind != RuntimeDekRestoreOutcomeKind.retryableFailure) {
      return outcome;
    }
    await delayFn(runtimeDekRestoreRetryDelay(outcome.failure));
    outcome = await readOnce();
  }
  return outcome;
}

@visibleForTesting
bool isRuntimeDekUnwrapBlockedByDeviceState(
  Map<dynamic, dynamic>? diagnostics,
) {
  if (diagnostics == null) return false;
  final deviceState = diagnostics['device_state'];
  if (deviceState is! Map) return false;
  final locked = deviceState['is_device_locked'];
  if (locked is bool && locked) return true;
  final userUnlocked = deviceState['is_user_unlocked'];
  return userUnlocked is bool && !userUnlocked;
}

/// Returns true when running on Android AND the device is currently
/// locked according to `KeyguardManager`. Reads via the existing
/// `getRuntimeDekDiagnostics` platform method (a single fast IPC); on
/// iOS or older Android builds without the method handler, returns
/// false so the unwrap proceeds normally.
Future<bool> _isAndroidDeviceLockedForRuntimeDekUnwrap() async {
  if (!Platform.isAndroid) return false;
  try {
    final diagnostics = await _runtimeDekStore.getDiagnostics();
    return isRuntimeDekUnwrapBlockedByDeviceState(diagnostics);
  } catch (_) {
    // Diagnostic IPC failed — fall back to attempting the unwrap. The
    // existing classify-and-retry policy still protects the cache.
    return false;
  }
}

Future<RuntimeDekRestoreOutcome> _readCachedRuntimeDekForRestoreOutcome({
  required String aad,
}) {
  return retryRuntimeDekRestoreCore(
    readOnce: () => readCachedRuntimeDekForRestoreOutcomeCore(
      aad: aad,
      readKey: _safeReadValue,
      deleteKey: _bestEffortDeleteKey,
      writeKey: _checkedWriteValue,
      unwrapDek: _unwrapRuntimeDek,
      wrapDek: _wrapRuntimeDek,
      reportWarning: (message, error, stackTrace) {
        ErrorReportingService.instance.report(
          message,
          severity: ErrorSeverity.warning,
          stackTrace: stackTrace,
        );
      },
    ),
  );
}

Future<void> _deleteCachedRuntimeDek({bool deleteWrappingKey = false}) async {
  await _bestEffortDeleteKey(kRuntimeDekWrappedKey);
  await _bestEffortDeleteKey(kRuntimeDekKey);
  if (deleteWrappingKey) {
    try {
      await _runtimeDekStore.deleteWrappingKey();
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Runtime DEK wrapping-key delete failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }
}

@visibleForTesting
Future<void> writeRuntimeDekCacheCore({
  required Uint8List dekBytes,
  required String aad,
  required Future<String> Function(Uint8List dekBytes, String aad) wrapDek,
  required Future<void> Function(String key, String value) writeKey,
  required Future<void> Function(String key) deleteKey,
  bool preserveLegacyRawOnFailure = false,
  void Function(String message, Object error, StackTrace stackTrace)?
  reportWarning,
}) async {
  try {
    final wrapped = await wrapDek(dekBytes, aad);
    await writeKey(kRuntimeDekWrappedKey, wrapped);
    await deleteKey(kRuntimeDekKey);
  } catch (e, st) {
    if (!preserveLegacyRawOnFailure) {
      try {
        await deleteKey(kRuntimeDekKey);
      } catch (deleteError, deleteStackTrace) {
        reportWarning?.call(
          'Runtime DEK legacy raw cache cleanup failed after refresh failure.',
          deleteError,
          deleteStackTrace,
        );
      }
    }
    reportWarning?.call(
      'Runtime DEK cache refresh failed; previous wrapped cache preserved.',
      e,
      st,
    );
  }
}

/// Export the raw DEK from Rust and cache it as a device-bound wrapped blob.
///
/// Call after `initialize()`, `unlock()`, or a completed pairing ceremony —
/// any operation that leaves the key hierarchy unlocked. On subsequent app launches,
/// `_autoConfigureIfReady` unwraps this cached DEK to restore the unlocked
/// state without re-deriving via Argon2id.
/// If the device does not have a sync_id/device_id yet (pre-sync onboarding),
/// the runtime cache is skipped; app DB rotation still runs.
///
/// Rotates the Drift app DB to the HKDF-derived local storage key
/// (HKDF(DEK, DeviceSecret)).
Future<void> cacheRuntimeKeys(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) async {
  final runtimeDekAad = buildRuntimeDekAad(
    syncId: decodeStoredUtf8(
      await _safeReadValue('${_secureStorePrefix}sync_id'),
    ),
    deviceId: decodeStoredUtf8(
      await _safeReadValue('${_secureStorePrefix}device_id'),
    ),
  );
  if (runtimeDekAad == null) {
    await _deleteCachedRuntimeDek();
    debugPrint(
      '[SYNC] Skipping runtime DEK cache: sync_id/device_id unavailable',
    );
  } else {
    final legacyRaw = await _safeReadValue(kRuntimeDekKey);
    final preserveLegacyRawOnFailure =
        legacyRaw != null && legacyRaw.isNotEmpty;
    final dekBytes = Uint8List.fromList(await ffi.exportDek(handle: handle));
    try {
      await writeRuntimeDekCacheCore(
        dekBytes: dekBytes,
        aad: runtimeDekAad,
        wrapDek: _wrapRuntimeDek,
        writeKey: _checkedWriteValue,
        deleteKey: _bestEffortDeleteKey,
        preserveLegacyRawOnFailure: preserveLegacyRawOnFailure,
        reportWarning: (message, error, stackTrace) {
          ErrorReportingService.instance.report(
            message,
            severity: ErrorSeverity.warning,
            stackTrace: stackTrace,
          );
        },
      );
    } finally {
      _zeroBytesBestEffort(dekBytes);
    }
  }

  // Rotate only prism.db. prism_sync.db keeps its original dedicated key.
  try {
    final lskBytes = Uint8List.fromList(
      await ffi.localStorageKey(handle: handle),
    );
    final newHexKey = lskBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final currentDriftKey = await readDatabaseKeyHex();
    if (currentDriftKey != newHexKey) {
      await rotateDatabaseToKey(db: db, newKey: lskBytes);
    }

    // Keep the Rust sync DB on its original dedicated key. Rekeying it under
    // WAL has produced files that fail to reopen after Android process death.
  } catch (e) {
    // Non-fatal: the app DB keeps its current key and rotation retries on
    // the next unlock.
    debugPrint('[SYNC] Failed to rotate database keys to derived key: $e');
  }
}

/// Pure, testable core of the keychain-write phase of `drainRustStore`.
///
/// Given the parsed `entries` map (bare-key -> base64 value), runs the
/// delete-then-write loop against the supplied [deleteKey] / [writeKey]
/// callbacks, checking [shouldAbort] before every keychain mutation.
/// Used by both the real `drainRustStore` (which supplies real
/// `_storage` callbacks) and unit tests (which supply fakes to prove
/// the per-iteration abort actually short-circuits writes).
///
/// Returns the number of writes that were committed before the abort
/// short-circuited the loop. Tests use this to assert partial-write
/// invariants.
///
/// **Round 3 Fix 2 contract:**
/// - The pre-loop `shouldAbort` check is the LAST chance to bail
///   before any mutation.
/// - Every iteration of the delete and write loops re-checks
///   `shouldAbort` BEFORE the next `await`, so a revocation firing
///   mid-loop short-circuits cleanly.
@visibleForTesting
Future<int> applyDrainedEntries({
  required Map<String, String> entries,
  required Future<void> Function(String fullKey) deleteKey,
  required Future<void> Function(String fullKey, String value) writeKey,
  bool Function()? shouldAbort,
}) async {
  // Pre-loop barrier.
  if (shouldAbort?.call() ?? false) {
    return 0;
  }

  int committedWrites = 0;
  // Phase 1: delete stale static keys that Rust no longer has.
  for (final key in _secureStoreKeys) {
    if (!entries.containsKey(key)) {
      if (shouldAbort?.call() ?? false) return committedWrites;
      await deleteKey('$_secureStorePrefix$key');
    }
  }
  // Phase 2: write every entry Rust returned.
  final orderedEntries = entries.entries.toList()
    ..sort(
      (a, b) =>
          _drainWritePriority(a.key).compareTo(_drainWritePriority(b.key)),
    );
  for (final entry in orderedEntries) {
    if (shouldAbort?.call() ?? false) return committedWrites;
    await writeKey('$_secureStorePrefix${entry.key}', entry.value);
    committedWrites++;
  }
  return committedWrites;
}

int _drainWritePriority(String key) {
  // `sync_id` + `relay_url` are UI/startup gate keys. Write them only after
  // the device identity is durable so a crash mid-drain cannot make a partial
  // setup look pairable on the next launch.
  if (key == 'sync_id' || key == 'relay_url') return 2;
  return 0;
}

/// Drain the Rust-side MemorySecureStore back to platform keychain.
/// Call after state-changing operations (initialize, createSyncGroup, join, etc).
///
/// The optional [shouldAbort] callback is checked at every yield point
/// inside the write loop. If it returns `true` the drain bails before
/// committing the next keychain mutation, short-circuiting the
/// remaining writes. This is how the event-driven drain path in
/// `SyncStatusNotifier` stops a mid-flight drain when a
/// `DeviceRevoked` / credential-cleanup event fires between schedule
/// time and any specific keychain write.
///
/// Design note: the abort check runs AFTER the FFI drain (which reads
/// Rust state) but BEFORE the first keychain write. Once we start
/// writing, partial writes are worse than "fully wrote" or "fully
/// didn't", so we re-check before EACH individual write. The
/// per-iteration cost is a trivial closure call; the safety payoff is
/// that credentials can't be partially resurrected.
///
/// Existing callers that don't pass [shouldAbort] keep working — the
/// parameter defaults to a no-op that always returns `false`.
Future<void> drainRustStore(
  ffi.PrismSyncHandle handle, {
  bool Function()? shouldAbort,
}) async {
  final drained = await ffi.drainSecureStore(handle: handle);

  // Pre-write barrier: if revocation landed during the FFI call, log
  // and bail before touching the keychain.
  if (shouldAbort?.call() ?? false) {
    debugPrint('[SYNC] drainRustStore aborted: credentials revoked pre-write');
    return;
  }

  final entries = encodeDrainedEntries(drained);
  await applyDrainedEntries(
    entries: entries,
    deleteKey: _checkedDeleteKey,
    writeKey: _checkedWriteValue,
    shouldAbort: shouldAbort,
  );
}

/// Phase identifier for [DrainPartialWriteException]. Lets callers and tests
/// distinguish a Phase-1 keychain delete failure from a Phase-2 write
/// failure without string-matching the message.
enum DrainPartialWritePhase { delete, write }

/// Thrown by [drainRustStoreWithSnapshotRollback] (and the lower-level
/// [applyDrainedEntriesWithSnapshotRollback] used in tests) when the
/// keychain mirror failed mid-flight AND the caller-owned snapshot
/// rollback ran. The original storage error is preserved as [cause];
/// [failedKey] / [phase] tell the caller which mutation tripped the
/// rollback so logs / setup-failure UX can be specific.
class DrainPartialWriteException implements Exception {
  final String failedKey;
  final DrainPartialWritePhase phase;
  final Object cause;
  final StackTrace? causeStackTrace;

  DrainPartialWriteException({
    required this.failedKey,
    required this.phase,
    required this.cause,
    this.causeStackTrace,
  });

  @override
  String toString() =>
      'DrainPartialWriteException(phase=${phase.name}, key=$failedKey, '
      'cause=$cause)';
}

/// Snapshot-aware variant of [applyDrainedEntries] used by the setup
/// drain path. Behaves identically to [applyDrainedEntries] on the happy
/// path; on a delete or write throw it:
///
/// 1. Best-effort restores the keychain to [rollbackSnapshot]:
///    - Deletes any current `prism_sync.*` key NOT in the snapshot AND
///      NOT in [kProtectedFromReset].
///    - Writes every snapshot entry back.
///    - Never touches [kProtectedFromReset] — those slots hold the local
///      DB-encryption key and must survive any sync-side rollback.
/// 2. Re-throws a [DrainPartialWriteException] tagged with the failed
///    key and the phase that failed.
///
/// Restore-time failures are swallowed (logged via [debugPrint]) so the
/// original storage error survives as [DrainPartialWriteException.cause]
/// and the caller's catch path still runs.
///
/// The [shouldAbort] hook still works exactly as in [applyDrainedEntries]
/// — a clean abort is NOT a rollback trigger; only a thrown delete/write
/// is.
@visibleForTesting
Future<int> applyDrainedEntriesWithSnapshotRollback({
  required Map<String, String> entries,
  required Map<String, String> rollbackSnapshot,
  required Future<void> Function(String fullKey) deleteKey,
  required Future<void> Function(String fullKey, String value) writeKey,
  required Future<Map<String, String>> Function() readCurrentNamespace,
  bool Function()? shouldAbort,
}) async {
  // Pre-loop barrier — same contract as applyDrainedEntries. A pre-loop
  // abort is a clean no-op; rollback only fires on a thrown mutation.
  if (shouldAbort?.call() ?? false) {
    return 0;
  }

  // Track the full keys we ATTEMPTED to mutate (whether or not the
  // mutation succeeded before the throw). Used by the rollback's
  // namespace-scan-failure fallback to compute a "best-known" set of
  // keys to delete when we cannot read the live keychain to discover
  // post-drain leftovers exactly.
  final attemptedFullKeys = <String>{};

  Future<void> runRollback({
    required String failedKey,
    required DrainPartialWritePhase phase,
    required Object cause,
    required StackTrace stackTrace,
  }) async {
    // Phase A: drop everything currently in the namespace that the
    // snapshot does NOT vouch for, except the protected DB slots. If
    // the namespace scan itself fails (a realistic Android keystore
    // failure), fall back to deleting the union of:
    //   - keys we attempted to mutate during this drain that aren't in
    //     the snapshot (covers Phase 2 writes + Phase 1 deletes that
    //     succeeded mid-loop), and
    //   - keys in `_secureStoreKeys` (the static fallback list) that
    //     aren't in the snapshot (covers leftover stale identity slots
    //     a previous successful drain may have written).
    // This is "best-effort exact" — we lose the dynamic-key view
    // (`epoch_key_*`, `runtime_keys_*`) but at least clear the static
    // identity slots that gate sync.
    try {
      final current = await readCurrentNamespace();
      for (final key in current.keys) {
        if (kProtectedFromReset.contains(key)) continue;
        if (rollbackSnapshot.containsKey(key)) continue;
        try {
          await deleteKey(key);
        } catch (e) {
          // Best-effort — never mask the original failure.
          debugPrint('[SYNC] drain rollback delete failed for $key: $e');
        }
      }
    } catch (e, st) {
      // Rollback exactness is now best-effort. Surface as a warning
      // (not just debugPrint) so diagnostics can flag the degraded
      // restore path instead of silently swallowing it.
      ErrorReportingService.instance.report(
        '[SYNC] drain rollback namespace scan failed; falling back to '
        'attempted-keys + static-allowlist delete: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
      final fallbackDeletes = <String>{
        ...attemptedFullKeys,
        for (final key in _secureStoreKeys) '$_secureStorePrefix$key',
      };
      for (final fullKey in fallbackDeletes) {
        if (kProtectedFromReset.contains(fullKey)) continue;
        if (rollbackSnapshot.containsKey(fullKey)) continue;
        try {
          await deleteKey(fullKey);
        } catch (e2) {
          debugPrint(
            '[SYNC] drain rollback fallback delete failed for $fullKey: $e2',
          );
        }
      }
    }
    // Phase B: write every snapshot entry back.
    for (final entry in rollbackSnapshot.entries) {
      if (kProtectedFromReset.contains(entry.key)) continue;
      try {
        await writeKey(entry.key, entry.value);
      } catch (e) {
        debugPrint('[SYNC] drain rollback restore failed for ${entry.key}: $e');
      }
    }
    Error.throwWithStackTrace(
      DrainPartialWriteException(
        failedKey: failedKey,
        phase: phase,
        cause: cause,
        causeStackTrace: stackTrace,
      ),
      stackTrace,
    );
  }

  int committedWrites = 0;
  // Phase 1: delete stale static keys (matches applyDrainedEntries).
  for (final key in _secureStoreKeys) {
    if (!entries.containsKey(key)) {
      if (shouldAbort?.call() ?? false) return committedWrites;
      final fullKey = '$_secureStorePrefix$key';
      attemptedFullKeys.add(fullKey);
      try {
        await deleteKey(fullKey);
      } catch (e, st) {
        await runRollback(
          failedKey: fullKey,
          phase: DrainPartialWritePhase.delete,
          cause: e,
          stackTrace: st,
        );
      }
    }
  }
  // Phase 2: write every entry Rust returned, in priority order.
  final orderedEntries = entries.entries.toList()
    ..sort(
      (a, b) =>
          _drainWritePriority(a.key).compareTo(_drainWritePriority(b.key)),
    );
  for (final entry in orderedEntries) {
    if (shouldAbort?.call() ?? false) return committedWrites;
    final fullKey = '$_secureStorePrefix${entry.key}';
    attemptedFullKeys.add(fullKey);
    try {
      await writeKey(fullKey, entry.value);
    } catch (e, st) {
      await runRollback(
        failedKey: fullKey,
        phase: DrainPartialWritePhase.write,
        cause: e,
        stackTrace: st,
      );
    }
    committedWrites++;
  }
  return committedWrites;
}

/// Setup-only variant of [drainRustStore] that restores the
/// caller-owned [rollbackSnapshot] if a delete/write inside the
/// keychain mirror throws.
///
/// Call this ONLY from setup paths that captured a clean pre-write
/// snapshot of the `prism_sync.*` namespace (excluding
/// [kProtectedFromReset]). The two paths today are:
///   * Initiator setup (`sync_setup_provider._complete`).
///   * Joiner ceremony post-drain (`device_pairing_provider.completeJoinerWithPassword`).
///
/// Post-config / background drains MUST keep using [drainRustStore]
/// unchanged. Those callers do not have an authoritative pre-state to
/// restore to; using snapshot rollback there would clobber valid
/// pre-existing credentials. They keep the existing "log the failed
/// key, leave the keychain as-is" behavior so Block 6c's `needsRecovery`
/// classifier can surface partial state at next boot.
///
/// On rollback this re-throws a [DrainPartialWriteException] so callers
/// can keep their existing catch-and-restore-snapshot logic running as
/// defense in depth (the second restore is a no-op when the drain's
/// internal restore already succeeded).
Future<void> drainRustStoreWithSnapshotRollback(
  ffi.PrismSyncHandle handle, {
  required Map<String, String> rollbackSnapshot,
  bool Function()? shouldAbort,
}) async {
  final drained = await ffi.drainSecureStore(handle: handle);

  if (shouldAbort?.call() ?? false) {
    debugPrint(
      '[SYNC] drainRustStoreWithSnapshotRollback aborted: revoked pre-write',
    );
    return;
  }

  final entries = encodeDrainedEntries(drained);
  await applyDrainedEntriesWithSnapshotRollback(
    entries: entries,
    rollbackSnapshot: rollbackSnapshot,
    deleteKey: _checkedDeleteKey,
    writeKey: _checkedWriteValue,
    readCurrentNamespace: () => readPrefixed(_secureStorePrefix),
    shouldAbort: shouldAbort,
  );
}

/// Capture an authoritative pre-write snapshot of the `prism_sync.*`
/// namespace, excluding [kProtectedFromReset] (DB-encryption slots).
///
/// Returns `null` if the keychain scan throws — callers MUST treat
/// that as "I don't know what's in the keychain" and either abort the
/// operation or fall back to the non-rollback drain path. Returning
/// `{}` would treat the failure as "the keychain is authoritatively
/// empty," and a subsequent rollback could then delete real
/// pre-existing entries thinking they were never there.
///
/// Shared between `sync_setup_provider._complete`,
/// `device_pairing_provider.completeJoinerWithPassword`, and the
/// onboarding PIN-setup drain so all three paths agree on which keys
/// are sacred and how snapshot-capture failure surfaces.
Future<Map<String, String>?> snapshotPrismSyncKeychain() async {
  try {
    final all = await readPrefixed(_secureStorePrefix);
    return Map.fromEntries(
      all.entries.where((e) => !kProtectedFromReset.contains(e.key)),
    );
  } catch (e, st) {
    ErrorReportingService.instance.report(
      '[SYNC] snapshotPrismSyncKeychain failed; caller must fall back to '
      'the non-rollback drain path: $e',
      severity: ErrorSeverity.warning,
      stackTrace: st,
    );
    return null;
  }
}

// ---------------------------------------------------------------------------
// One-time enum field migration
// ---------------------------------------------------------------------------

/// Re-emits system_settings enum fields as ints exactly once after app update.
///
/// Before the .name → .index fix, these fields were encoded as strings
/// (e.g. "standard") in the Rust field_versions table. The repository fix
/// prevents new string ops, but the winning values already stored in
/// field_versions remain strings until overwritten by a newer op.
/// This function runs once per device to create new ops with correct int
/// values, which win via LWW due to their higher HLC timestamps.
Future<void> _reemitSettingsEnumFieldsOnce(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) async {
  const flagKey = 'sync.enum_fields_reemit_v1';
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) == true) return;

    final row = await (db.select(db.systemSettingsTable)).getSingleOrNull();
    if (row == null) return;

    await ffi.recordUpdate(
      handle: handle,
      table: 'system_settings',
      entityId: 'singleton',
      changedFieldsJson: jsonEncode({
        'terminology': row.terminology,
        'theme_mode': row.themeMode,
        'theme_brightness': row.themeBrightness,
        'theme_style': row.themeStyle,
        'timing_mode': row.timingMode,
      }),
    );
    // Set flag AFTER recordUpdate succeeds — if recordUpdate throws, the
    // catch block lets it retry on next launch. Duplicate ops from a crash
    // between these two lines are harmless (LWW idempotency).
    await prefs.setBool(flagKey, true);
    debugPrint('[SYNC_MIGRATE] enum fields re-emitted as ints');
  } catch (e) {
    // Non-fatal — will retry on next launch until it succeeds.
    debugPrint('[SYNC_MIGRATE] enum field re-emit failed: $e');
  }
}

Future<PkGroupSyncV2CatchupResult> catchUpPkBackedSyncOnceAfterCutover(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) {
  final service = PkGroupSyncV2CatchupService(
    db: db,
    recordGroupUpdate: ({required table, required entityId, required fields}) {
      return ffi.recordUpdate(
        handle: handle,
        table: table,
        entityId: entityId,
        changedFieldsJson: jsonEncode(fields),
      );
    },
    recordEntryCreate: ({required table, required entityId, required fields}) {
      return ffi.recordCreate(
        handle: handle,
        table: table,
        entityId: entityId,
        fieldsJson: jsonEncode(fields),
      );
    },
  );
  return service.runOnce();
}

Future<GroupChatVisibilitySyncReemitResult>
reemitGroupChatVisibilityOnceAfterUpgrade(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) {
  final service = GroupChatVisibilitySyncReemitService(
    db: db,
    recordUpdate: ({required table, required entityId, required fields}) {
      return ffi.recordUpdate(
        handle: handle,
        table: table,
        entityId: entityId,
        changedFieldsJson: jsonEncode(fields),
      );
    },
  );
  return service.runOnce();
}

Future<void> runPostHealthySyncCatchUp({
  required ffi.PrismSyncHandle handle,
  required AppDatabase db,
  required String failureLabel,
  @visibleForTesting
  Future<void> Function(ffi.PrismSyncHandle handle)? onResume,
  @visibleForTesting
  Future<GroupChatVisibilitySyncReemitResult> Function(
    ffi.PrismSyncHandle handle,
    AppDatabase db,
  )?
  reemitGroupChatVisibility,
  @visibleForTesting
  Future<PkGroupSyncV2CatchupResult> Function(
    ffi.PrismSyncHandle handle,
    AppDatabase db,
  )?
  catchUpPk,
  @visibleForTesting Future<void> Function(ffi.PrismSyncHandle handle)? drain,
}) async {
  try {
    await (onResume ?? ((h) => ffi.onResume(handle: h)))(handle);
    await (reemitGroupChatVisibility ??
        reemitGroupChatVisibilityOnceAfterUpgrade)(handle, db);
    await (catchUpPk ?? catchUpPkBackedSyncOnceAfterCutover)(handle, db);
    // Persist any state the sync cycle mutated (session_token refresh, epoch
    // advance, emitted migration ops, etc.) before a subsequent crash loses it.
    await (drain ?? drainRustStore)(handle);
  } catch (e, st) {
    final structuredError = PrismSyncStructuredError.tryParse(e);
    ErrorReportingService.instance.report(
      '$failureLabel (non-fatal): ${structuredError?.userMessage ?? e}',
      severity: ErrorSeverity.warning,
      stackTrace: st,
    );
  }
}

/// Drive the resume sync-nudge with self-healing, independent of FFI and
/// Riverpod so it can be unit-tested. `PrismApp._onResume` wires the real
/// `ffi.*` calls + health provider into the seams.
///
/// Invariants — the sync-resume-disconnect fix:
/// - A failed `onResume` NEVER transitions to `disconnected` and NEVER clears
///   credentials. It marks a transient `reconnecting`, reconfigures the relay
///   (`configureEngine` re-reads `relay_url` from the keychain and rebuilds the
///   in-memory relay), then retries `onResume` ONCE. "Relay not configured" is
///   treated as retryable here.
/// - On a successful nudge it transitions `reconnecting → healthy` and kicks an
///   explicit sync. A persistent failure leaves health at `reconnecting` (not
///   `disconnected`); the auto-sync driver and the next resume keep retrying.
/// - The real cause of a failure is surfaced via [takeLastPanic] so the masked
///   iOS resume panic stops being invisible.
Future<void> runResumeSyncNudge({
  required Future<void> Function() onResume,
  required Future<void> Function() configureEngine,
  required void Function() triggerSync,
  required Future<String?> Function() takeLastPanic,
  required SyncHealthState Function() readHealth,
  required void Function(SyncHealthState) setHealth,
  void Function(String message)? log,
}) async {
  final emit = log ?? debugPrint;

  void markReconnecting() {
    // Never clobber needsPassword / disconnected / etc.
    if (readHealth() == SyncHealthState.healthy) {
      setHealth(SyncHealthState.reconnecting);
    }
  }

  void markHealthy() {
    if (readHealth() == SyncHealthState.reconnecting) {
      setHealth(SyncHealthState.healthy);
    }
  }

  Future<void> logFailure(String stage, Object error) async {
    String? panic;
    try {
      panic = await takeLastPanic();
    } catch (_) {
      panic = null;
    }
    final structured = PrismSyncStructuredError.tryParse(error);
    emit(
      '$stage failed — recovering, relay stays configured: '
      '${structured?.userMessage ?? error}'
      '${panic != null ? ' | rust panic: $panic' : ''}',
    );
  }

  try {
    await onResume();
    markHealthy();
    triggerSync();
    return;
  } catch (e) {
    await logFailure('onResume', e);
  }

  // Transient recovery: keep credentials + relay config, reconfigure, retry.
  markReconnecting();
  try {
    await configureEngine();
    await onResume();
    markHealthy();
    triggerSync();
  } catch (e) {
    await logFailure('onResume retry after reconfigure', e);
    // Stay in `reconnecting` (non-destructive).
  }
}

// ---------------------------------------------------------------------------
// Sync quarantine
// ---------------------------------------------------------------------------

final syncQuarantineDaoProvider = Provider<SyncQuarantineDao>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncQuarantineDao(db);
});

final syncQuarantineServiceProvider = Provider<SyncQuarantineService>((ref) {
  return SyncQuarantineService(ref.watch(syncQuarantineDaoProvider));
});

/// Fetches the current list of quarantined items. Refreshed by invalidating.
final quarantinedItemsProvider = FutureProvider<List<SyncQuarantineData>>((
  ref,
) async {
  final dao = ref.watch(syncQuarantineDaoProvider);
  return dao.getAll();
});

// ---------------------------------------------------------------------------
// DriftSyncAdapter
// ---------------------------------------------------------------------------

final driftSyncAdapterProvider = Provider<SyncAdapterWithCompletion>((ref) {
  final db = ref.watch(databaseProvider);
  final quarantine = ref.watch(syncQuarantineServiceProvider);
  // Gate fronting_sessions / front_session_comments apply on the
  // per-member fronting migration. While the migration is `blocked` or
  // `inProgress` the local schema is in a transitional shape (see WS1
  // step 4 + 5 in the remediation plan) and applying remote new-shape
  // rows would race with the in-flight migration. We read from
  // `frontingMigrationWritesBlockedProvider` lazily inside the closure
  // so the adapter doesn't have to be rebuilt on every state change.
  //
  // INVARIANT: `frontingMigrationModeProvider` MUST already be built
  // by the time this closure runs inside `db.transaction()`. The closure's
  // `ref.read` traverses
  //   frontingMigrationWritesBlockedProvider
  //   → frontingMigrationGateProvider
  //   → frontingMigrationModeProvider (StreamProvider over
  //     `systemSettingsDao.watchSettings()`)
  // and if the chain is cold, the StreamProvider's build callback fires
  // a Drift query from inside the open transaction, deadlocking the
  // bg-isolate commit-result message (verified 2026-05-03 on Pixel 6 Pro
  // fresh-install pairing — apply hung at chunk-1 commit). The provider
  // is kept always-warm via an `ref.listen(frontingMigrationModeProvider, …)`
  // in `app.dart` — do not remove that listener.
  return buildSyncAdapterWithCompletion(
    db,
    quarantine: quarantine,
    applyGate: (tableName) {
      if (tableName != 'fronting_sessions' &&
          tableName != 'front_session_comments') {
        return null;
      }
      final blocked = ref.read(frontingMigrationWritesBlockedProvider);
      return blocked ? DriftSyncApplyRefusal.frontingMigrationGate : null;
    },
  );
});

// ---------------------------------------------------------------------------
// Sync event stream
// ---------------------------------------------------------------------------

final syncEventStreamProvider = StreamProvider<SyncEvent>((ref) {
  final handle = ref.watch(prismSyncHandleProvider).value;
  if (handle == null) return const Stream.empty();

  final syncAdapter = ref.watch(driftSyncAdapterProvider);
  final db = ref.watch(databaseProvider);
  final strictCoordinator = ref.watch(strictApplyCoordinatorProvider);

  return createSyncEventStream(handle).asyncMap((event) async {
    if (kDebugMode) {
      debugPrint(
        '[SYNC_STREAM] Event type=${event.type}, changes=${event.changes.length}',
      );
    }
    if (event.isRemoteChanges) {
      final strict = strictCoordinator.isStrict;
      Object? applyError;
      StackTrace? applyStackTrace;
      syncAdapter.beginSyncBatch();
      try {
        final totalChanges = event.changes.length;
        if (strict) {
          // Bootstrap emits one full-snapshot RemoteChanges event; chunking
          // would need a snapshot-wide denominator.
          strictCoordinator.signalProgress(applied: 0, total: totalChanges);
        }
        final result = await applyRemoteChanges(
          db,
          syncAdapter.adapter,
          event,
          strict: strict,
          onProgress: strict
              ? (applied, total) => strictCoordinator.signalProgress(
                  applied: applied,
                  total: total,
                )
              : null,
        );
        if (strict && result.failedTables.isNotEmpty) {
          // Defensive — strict mode should rethrow on first failure.
          strictCoordinator.signalFailure(
            StrictApplyFailure(
              message: 'Strict apply reported failures without throwing',
              failedTables: result.failedTables,
            ),
          );
        }
      } catch (e, st) {
        if (strict) {
          strictCoordinator.signalFailure(
            e is StrictApplyFailure
                ? e
                : StrictApplyFailure(
                    message: e.toString(),
                    failedTables: const [],
                  ),
            st,
          );
        } else {
          applyError = e;
          applyStackTrace = st;
        }
      }
      await syncAdapter.completeSyncBatch();
      if (applyError != null) {
        Error.throwWithStackTrace(applyError, applyStackTrace!);
      }
      await catchUpPkBackedSyncOnceAfterCutover(handle, db);
      // Signal the strict-apply coordinator so the joiner's pre-registered
      // latch resolves with success. No-op when not in strict mode.
      if (strict) {
        strictCoordinator.signalBatchComplete();
      }
      if (kDebugMode) {
        debugPrint(
          '[SYNC_STREAM] Applied ${event.changes.length} remote changes',
        );
      }
    }
    return event;
  });
});

const _maxSyncEventLogEntries = 200;

/// Session-scoped sync event log for diagnostics.
///
/// Unlike directly listening in the debug screen, this buffer can stay alive
/// for the duration of the app so events that occur before the screen opens
/// are still visible to the user.
final syncEventLogProvider =
    NotifierProvider<SyncEventLogNotifier, List<SyncEventLogEntry>>(
      SyncEventLogNotifier.new,
    );

class SyncEventLogEntry {
  const SyncEventLogEntry({required this.timestamp, required this.event});

  final DateTime timestamp;
  final SyncEvent event;

  Map<String, dynamic> get data => event.data;

  String get timeLabel =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';

  String get summary {
    final completedError =
        (event.data['result'] as Map<String, dynamic>?)?['error'] as String?;
    if (event.isSyncStarted) {
      return 'Sync started';
    }
    if (event.isSyncCompleted) {
      return completedError != null && completedError.isNotEmpty
          ? 'Sync completed with error: $completedError'
          : 'Sync completed';
    }
    if (event.isRemoteChanges) {
      return 'Remote changes (${event.changes.length})';
    }
    if (event.isError) {
      return 'Error: ${event.data['message'] ?? 'unknown'}';
    }
    if (event.isDeviceRevoked) {
      return 'Device revoked: ${event.data['device_id'] ?? 'unknown'}';
    }
    if (event.isWebSocketStateChanged) {
      final connected = event.data['connected'] as bool? ?? false;
      return connected ? 'WebSocket connected' : 'WebSocket disconnected';
    }
    if (event.type == 'EpochRotated') {
      return 'Epoch rotated: ${event.data['epoch'] ?? 'unknown'}';
    }
    if (event.type == 'SnapshotProgress') {
      return 'Snapshot progress: '
          '${event.data['received'] ?? 0}/${event.data['total'] ?? 0}';
    }
    if (event.type == 'Warning') {
      return 'Warning: ${event.data['message'] ?? 'unknown'}';
    }
    if (event.type == 'DeviceJoined') {
      return 'Device joined: ${event.data['device_id'] ?? 'unknown'}';
    }
    return event.type;
  }
}

class SyncEventLogNotifier extends Notifier<List<SyncEventLogEntry>> {
  @override
  List<SyncEventLogEntry> build() {
    ref.listen(syncEventStreamProvider, (previous, next) {
      next.whenData((event) {
        final nextEntries = [
          ...state,
          SyncEventLogEntry(timestamp: DateTime.now(), event: event),
        ];
        final overflow = nextEntries.length - _maxSyncEventLogEntries;
        state = overflow > 0 ? nextEntries.sublist(overflow) : nextEntries;
      });
    });
    return const [];
  }

  void clear() {
    state = const [];
  }
}

/// Result of applying a batch of remote changes.
///
/// [rowsApplied] counts rows that were successfully written to Drift.
/// [failedTables] is always empty in non-strict mode (failures are logged and
/// skipped). In strict mode, when the first per-row failure occurs the function
/// rethrows a [StrictApplyFailure]; callers observe the failure via the
/// thrown exception, not this field.
class ApplyResult {
  const ApplyResult({required this.rowsApplied, this.failedTables = const []});

  final int rowsApplied;
  final List<String> failedTables;
}

/// Thrown by [applyRemoteChanges] when `strict: true` and a per-row apply
/// fails. Surfaces the row context plus the list of tables that were
/// hit (typically one, since strict rethrows on the first failure).
class StrictApplyFailure implements Exception {
  const StrictApplyFailure({
    required this.message,
    this.failedTables = const [],
    this.table,
    this.entityId,
    this.cause,
  });

  final String message;
  final List<String> failedTables;
  final String? table;
  final String? entityId;
  final Object? cause;

  @override
  String toString() {
    final ctx = table != null ? ' ($table/$entityId)' : '';
    return 'StrictApplyFailure$ctx: $message';
  }
}

/// Outcome of a strict-apply batch: either success or a structured failure.
/// Used as the return value of [StrictApplyCoordinator.outcome] so a single
/// awaiter can observe whichever event fires first without racing futures.
sealed class ApplyOutcome {
  const ApplyOutcome();
}

class ApplyOutcomeSuccess extends ApplyOutcome {
  const ApplyOutcomeSuccess();
}

class ApplyOutcomeFailure extends ApplyOutcome {
  const ApplyOutcomeFailure(this.failure, [this.stackTrace]);

  final StrictApplyFailure failure;
  final StackTrace? stackTrace;
}

class StrictApplyProgress {
  const StrictApplyProgress({this.applied, this.total});

  final int? applied;
  final int? total;

  bool get hasTotal => applied != null && total != null && total! > 0;
}

/// Coordinator for "strict apply" mode during snapshot bootstrap.
///
/// The joiner flow enables strict mode before `bootstrapFromSnapshot` so that
/// any per-row Drift failure while ingesting the snapshot aborts pairing
/// instead of silently skipping rows.
///
/// Uses a pre-registered latch so signal ordering is preserved regardless of
/// when the joiner registers its await. [enterStrictMode] creates a fresh
/// [Completer<ApplyOutcome>] BEFORE any bootstrap work kicks off; the sync
/// event stream writes into it from either [signalFailure] (strict apply
/// failed) or [signalBatchComplete] (the batch that followed bootstrap
/// applied cleanly). Whichever fires first wins — subsequent calls are
/// idempotent because both signal methods guard on `isCompleted`.
class StrictApplyCoordinator {
  bool _strict = false;
  Completer<ApplyOutcome>? _outcome;
  final StreamController<StrictApplyProgress> _progressController =
      StreamController<StrictApplyProgress>.broadcast();

  bool get isStrict => _strict;
  Stream<StrictApplyProgress> get progressStream => _progressController.stream;

  /// The future that resolves with the bootstrap batch outcome. Only valid
  /// between [enterStrictMode] and [exitStrictMode] — callers should capture
  /// it immediately after entering strict mode.
  Future<ApplyOutcome>? get outcome => _outcome?.future;

  /// Enter strict mode and return a future that completes with either a
  /// success or a failure outcome — whichever signal arrives first. Calling
  /// this replaces any in-flight completer — only one snapshot bootstrap
  /// runs at a time.
  Future<ApplyOutcome> enterStrictMode() {
    _strict = true;
    final completer = Completer<ApplyOutcome>();
    _outcome = completer;
    return completer.future;
  }

  /// Exit strict mode. Any pending outcome completer is completed with
  /// success so stale awaiters unblock cleanly (callers are expected to
  /// already have observed the outcome or abandoned it).
  void exitStrictMode() {
    _strict = false;
    final pending = _outcome;
    _outcome = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const ApplyOutcomeSuccess());
    }
  }

  /// Record a strict-mode failure. Idempotent — only the first signal wins.
  void signalFailure(StrictApplyFailure failure, [StackTrace? stackTrace]) {
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) {
      pending.complete(ApplyOutcomeFailure(failure, stackTrace));
    }
  }

  /// Heartbeat while `RemoteChanges` is still applying; downstream listeners
  /// only receive the event after the batch finishes.
  void signalProgress({int? applied, int? total}) {
    if (!_strict || _progressController.isClosed) return;
    _progressController.add(
      StrictApplyProgress(applied: applied, total: total),
    );
  }

  /// Record a successful batch-complete. Idempotent — only the first signal
  /// wins. Called from the sync event stream once the RemoteChanges batch
  /// has applied and [SyncAdapterWithCompletion.completeSyncBatch] has run.
  void signalBatchComplete() {
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const ApplyOutcomeSuccess());
    }
  }

  void dispose() {
    final pending = _outcome;
    _strict = false;
    _outcome = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(
        const ApplyOutcomeFailure(
          StrictApplyFailure(message: 'Strict apply coordinator disposed'),
        ),
      );
    }
    _progressController.close();
  }
}

final strictApplyCoordinatorProvider = Provider<StrictApplyCoordinator>((ref) {
  final coordinator = StrictApplyCoordinator();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Apply a batch of remote changes from a [SyncEvent] to the local Drift
/// database.
///
/// Non-strict mode (default): per-row failures are caught, reported to the
/// error-reporting service, and processing continues with the remaining
/// rows. Returns an [ApplyResult] with `rowsApplied` equal to the number of
/// rows that were written (NOT the number of input rows, since failures are
/// skipped). `failedTables` is always empty.
///
/// Strict mode (`strict: true`): the first per-row failure rethrows a
/// [StrictApplyFailure] describing the failing row. No further rows are
/// applied. Used by the joiner during snapshot bootstrap so a corrupt
/// snapshot aborts pairing rather than silently dropping rows.
///
/// Public (not `_`-prefixed) so the joiner/bootstrap test harness and the
/// sync event stream can both drive it; the stream is still the only
/// production caller.
Future<ApplyResult> applyRemoteChanges(
  AppDatabase db,
  DriftSyncAdapter adapter,
  SyncEvent event, {
  bool strict = false,
  void Function(int applied, int total)? onProgress,
}) async {
  // Apply changes in chunked transactions — each chunk of 20 changes runs
  // inside a single Drift transaction for fewer WAL commits, while per-row
  // try/catch keeps error handling granular (caught exceptions do NOT trigger
  // Drift transaction rollback).
  const chunkSize = 20;
  final changes = event.changes;
  var rowsApplied = 0;

  for (var offset = 0; offset < changes.length; offset += chunkSize) {
    final end = min(offset + chunkSize, changes.length);
    final chunk = changes.sublist(offset, end);

    await db.transaction(() async {
      for (final change in chunk) {
        final tableRaw = change['table'];
        final entityIdRaw = change['entity_id'];
        try {
          final table = tableRaw as String;
          final entityId = entityIdRaw as String;
          final isDelete = change['is_delete'] as bool? ?? false;
          final fields = (change['fields'] as Map<String, dynamic>?) ?? {};

          if (isDelete) {
            await adapter.hardDelete(table, entityId);
          } else {
            final skipUnknownTombstone =
                await _shouldSkipUnknownRemoteTombstone(
                  adapter,
                  table,
                  entityId,
                  fields,
                );
            if (!skipUnknownTombstone) {
              await adapter.applyFields(table, entityId, fields);
            }
          }
          rowsApplied++;
          onProgress?.call(rowsApplied, changes.length);
        } catch (e, st) {
          final fieldKeys = (change['fields'] as Map?)?.keys.toList() ?? [];
          if (strict) {
            // Abort the entire batch. Callers catch StrictApplyFailure to
            // surface a retry UI without ACKing the snapshot.
            throw StrictApplyFailure(
              message:
                  'Sync apply failed for $tableRaw/$entityIdRaw: $e '
                  '(fields: $fieldKeys)',
              failedTables: [if (tableRaw is String) tableRaw],
              table: tableRaw is String ? tableRaw : null,
              entityId: entityIdRaw is String ? entityIdRaw : null,
              cause: e,
            );
          }
          ErrorReportingService.instance.report(
            'Sync apply failed for $tableRaw/$entityIdRaw: $e '
            '(fields: $fieldKeys)',
            severity: ErrorSeverity.warning,
            stackTrace: st,
          );
          // Continue processing remaining changes — skip bad rows, apply good ones
        }
      }
    });
  }

  return ApplyResult(rowsApplied: rowsApplied);
}

Future<bool> _shouldSkipUnknownRemoteTombstone(
  DriftSyncAdapter adapter,
  String table,
  String entityId,
  Map<String, dynamic> fields,
) async {
  if (!_fieldsCarryRemoteTombstone(fields)) return false;
  if (table == 'conversations' ||
      table == 'members' ||
      table == 'member_groups' ||
      table == 'member_group_entries') {
    return false;
  }
  final entity = adapter.entityForTable(table);
  if (entity == null) return false;
  return await entity.readRow(entityId) == null;
}

bool _fieldsCarryRemoteTombstone(Map<String, dynamic> fields) {
  final value = fields['is_deleted'];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

// ---------------------------------------------------------------------------
// Sync status
// ---------------------------------------------------------------------------

/// Whether sync is enabled (derived from handle availability — no race).
final syncEnabledProvider = Provider<bool>((ref) {
  final handle = ref.watch(prismSyncHandleProvider);
  return handle.value != null;
});

// ---------------------------------------------------------------------------
// verifyMnemonicPin result type
// ---------------------------------------------------------------------------

/// Result of a [SyncHealthNotifier.verifyMnemonicPin] call.
///
/// Callers should switch exhaustively on this type to handle all branches.
sealed class VerifyMnemonicPinResult {
  const VerifyMnemonicPinResult();
}

/// The supplied mnemonic + PIN successfully unlock this install's wrapped_dek.
final class VerifyMnemonicPinMatch extends VerifyMnemonicPinResult {
  const VerifyMnemonicPinMatch();
}

/// The supplied mnemonic + PIN do NOT unlock this install's wrapped_dek, or
/// the mnemonic could not be decoded. The caller should not disclose which
/// input was wrong.
final class VerifyMnemonicPinNoMatch extends VerifyMnemonicPinResult {
  const VerifyMnemonicPinNoMatch();
}

/// The `wrapped_dek` is not present in the platform keychain — the user must
/// complete the wrapped_dek recovery flow before verification is possible.
final class VerifyMnemonicPinNeedsRewrap extends VerifyMnemonicPinResult {
  const VerifyMnemonicPinNeedsRewrap();
}

/// The sync engine handle is not yet available. Retry once the handle is
/// present (i.e. after the engine initialises).
final class VerifyMnemonicPinHandleUnavailable extends VerifyMnemonicPinResult {
  const VerifyMnemonicPinHandleUnavailable();
}

/// An infrastructure error occurred during verification — the result is
/// unknown. The caller should NOT increment the lockout counter for this
/// variant; it does not indicate a wrong credential.
final class VerifyMnemonicPinError extends VerifyMnemonicPinResult {
  const VerifyMnemonicPinError({required this.message});
  final String message;
}

// ---------------------------------------------------------------------------
// Sync health
// ---------------------------------------------------------------------------

/// Tracks whether sync is healthy, needs user intervention, or is disconnected.
enum SyncHealthState {
  /// Sync is configured and working.
  healthy,

  /// Transient: a resume/connectivity/auth blip is being retried. Credentials
  /// and relay config are intact, so this is NOT a reason to re-pair and must
  /// NEVER surface the destructive "Set up sync again" UI. Distinct from
  /// [disconnected]: that means credentials are genuinely gone / the device is
  /// confirmed revoked. `reconnecting` is treated like [healthy] for every
  /// gate; only the UI may show a subtle "reconnecting…" affordance. The sync
  /// engine self-heals out of this state (see `_onResume` reconfigure+retry).
  reconnecting,

  /// Wrapped runtime cache is missing but wrapped_dek exists — user must
  /// enter password.
  needsPassword,

  /// Engine is unlocked (runtime DEK cache restored) but `wrapped_dek` is
  /// missing from the keychain — user must re-enter PIN + mnemonic so we
  /// can regenerate `wrapped_dek` + `dek_salt` from the in-memory DEK.
  /// Sync still works; only device pairing is gated until recovery.
  needsRewrap,

  /// Credentials are gone or device was revoked — must re-pair.
  disconnected,

  /// The device has never been paired.
  unpaired,

  /// Android is locked, so device-bound runtime DEK unwrap is deferred.
  awaitingDeviceUnlock,

  /// Platform unwrap failed without proving the runtime DEK cache is dead.
  runtimeDekRestoreDeferred,
}

final syncHealthProvider =
    NotifierProvider<SyncHealthNotifier, SyncHealthState>(
      SyncHealthNotifier.new,
    );

/// Whether the sync password sheet is currently showing (duplicate guard).
final syncPasswordSheetVisibleProvider = NotifierProvider<_BoolNotifier, bool>(
  () => _BoolNotifier(false),
);

/// Whether the wrapped_dek recovery sheet is currently showing
/// (duplicate guard).
final syncRewrapSheetVisibleProvider = NotifierProvider<_BoolNotifier, bool>(
  () => _BoolNotifier(false),
);

class _BoolNotifier extends Notifier<bool> {
  _BoolNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  // ignore: use_setters_to_change_properties
  void setValue(bool value) => state = value;
}

// ---------------------------------------------------------------------------
// verifyMnemonicPin test seam
// ---------------------------------------------------------------------------

/// FFI call-sites used by [SyncHealthNotifier.verifyMnemonicPin].
///
/// Production code uses [_ProductionSyncVerifyMnemonicPinFns]. Tests inject a
/// fake via [SyncHealthNotifier.verifyFns] to exercise the real method body
/// without requiring a linked Rust dylib.
@visibleForTesting
abstract class SyncVerifyMnemonicPinFns {
  Future<List<int>> mnemonicToBytes(Uint8List mnemonic);
  Future<bool> verifyMnemonicPin({
    required ffi.PrismSyncHandle handle,
    required Uint8List password,
    required List<int> secretKey,
  });
}

class _ProductionSyncVerifyMnemonicPinFns implements SyncVerifyMnemonicPinFns {
  const _ProductionSyncVerifyMnemonicPinFns();

  @override
  Future<List<int>> mnemonicToBytes(Uint8List mnemonic) =>
      ffi.mnemonicToBytes(mnemonic: mnemonic);

  @override
  Future<bool> verifyMnemonicPin({
    required ffi.PrismSyncHandle handle,
    required Uint8List password,
    required List<int> secretKey,
  }) => ffi.verifyMnemonicPin(
    handle: handle,
    password: password,
    secretKey: secretKey,
  );
}

class SyncHealthNotifier extends Notifier<SyncHealthState> {
  /// Test seam — production uses the real FFI functions. Tests override this
  /// to inject fakes without re-implementing the method body.
  @visibleForTesting
  SyncVerifyMnemonicPinFns verifyFns =
      const _ProductionSyncVerifyMnemonicPinFns();

  @override
  SyncHealthState build() => SyncHealthState.healthy;

  void setState(SyncHealthState value) => state = value;

  /// Lock sync runtime keys in memory. With [hard] set, also removes the
  /// device-bound runtime-DEK cache so the next start requires PIN+mnemonic.
  Future<void> lock({bool hard = false}) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle != null) {
      await ffi.lock(handle: handle);
    }
    if (hard) {
      await _deleteCachedRuntimeDek(deleteWrappingKey: true);
      final wrappedDek = await _safeReadValue(
        '${_secureStorePrefix}wrapped_dek',
      );
      state = hasStoredWrappedDek(wrappedDek)
          ? SyncHealthState.needsPassword
          : SyncHealthState.disconnected;
    }
  }

  /// Attempt to unlock the key hierarchy with the user's PIN + mnemonic.
  ///
  /// The mnemonic is no longer stored in the keychain, so callers must
  /// collect it from the user (via [SyncPinSheet]) and pass it here.
  ///
  /// Returns true on success (state transitions to healthy).
  /// Returns false on failure (wrong PIN, invalid mnemonic, or missing handle).
  Future<bool> attemptUnlock({
    required String pin,
    required String mnemonic,
  }) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return false;

    final normalized = mnemonic.trim().toLowerCase();
    Uint8List? mnemonicBytes;
    Uint8List? pinBytes;
    List<int>? secretKeyBytes;
    try {
      try {
        mnemonicBytes = secretUtf8Bytes(normalized);
        secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonicBytes);
      } catch (_) {
        // Invalid mnemonic — treat as failed unlock without disclosing
        // which input was wrong.
        return false;
      } finally {
        _zeroBytesBestEffort(mnemonicBytes);
        mnemonicBytes = null;
      }

      // Unlock the key hierarchy — throws on wrong PIN or mismatched mnemonic.
      try {
        pinBytes = secretUtf8Bytes(pin);
        await ffi.unlock(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        // Wrong PIN or wrong mnemonic — don't change state; UI shows a
        // generic error and lets the user retry.
        return false;
      } finally {
        _zeroBytesBestEffort(pinBytes);
        _zeroBytesBestEffort(secretKeyBytes);
        pinBytes = null;
        secretKeyBytes = null;
      }

      // Configure engine and auto-sync BEFORE caching keys.
      // If this fails, the config is broken — set disconnected.
      try {
        await ffi.configureEngine(handle: handle);
        await ffi.setAutoSync(
          handle: handle,
          enabled: true,
          debounceMs: BigInt.from(300),
          retryDelayMs: BigInt.from(30000),
          maxRetries: 3,
        );
      } on Exception {
        state = SyncHealthState.disconnected;
        return false;
      }

      // Only cache after configureEngine succeeds
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));

      state = SyncHealthState.healthy;
      unawaited(
        runPostHealthySyncCatchUp(
          handle: handle,
          db: ref.read(databaseProvider),
          failureLabel: 'Post-unlock catch-up sync failed',
        ),
      );
      return true;
    } catch (_) {
      // Unexpected error (mnemonicToBytes, engine config, etc.)
      return false;
    } finally {
      // Always zero any secret bytes that made it into Dart memory.
      _zeroBytesBestEffort(mnemonicBytes);
      _zeroBytesBestEffort(pinBytes);
      _zeroBytesBestEffort(secretKeyBytes);
    }
  }

  /// Pre-flight check that the typed mnemonic + PIN unlock the current
  /// install's wrapped_dek. Has NO side effects (does not unlock, configure,
  /// cache keys, or set state). Use during pairing pre-flight and on the
  /// verify-backup screen. Wrap call sites in a PinLockoutState to enforce
  /// rate-limiting — a 6-digit PIN has only 10^6 entropy.
  ///
  /// The [PinBuffer] is drained when verification is actually attempted
  /// (Match / NoMatch). On [VerifyMnemonicPinHandleUnavailable] and
  /// [VerifyMnemonicPinNeedsRewrap] the caller did not consume the PIN, so
  /// the caller must clear it explicitly if they don't intend to retry.
  /// Callers must collect a fresh PIN to retry after Match / NoMatch.
  Future<VerifyMnemonicPinResult> verifyMnemonicPin({
    required PinBuffer pin,
    required String mnemonic,
  }) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return const VerifyMnemonicPinHandleUnavailable();

    final wrappedDekPresent = await ref.read(
      syncWrappedDekPresentProvider.future,
    );
    if (!wrappedDekPresent) return const VerifyMnemonicPinNeedsRewrap();

    // Past this point we commit to attempting verification — drain the PIN
    // buffer now so the docstring guarantee holds for all remaining paths.
    final normalized = mnemonic.trim().toLowerCase();
    Uint8List? mnemonicBytes;
    Uint8List? pinBytes = pin.consumeBytesAndClear();
    List<int>? secretKeyBytes;
    try {
      try {
        mnemonicBytes = secretUtf8Bytes(normalized);
        secretKeyBytes = await verifyFns.mnemonicToBytes(mnemonicBytes);
      } catch (_) {
        // Invalid mnemonic — don't disclose which input was wrong.
        return const VerifyMnemonicPinNoMatch();
      } finally {
        _zeroBytesBestEffort(mnemonicBytes);
        mnemonicBytes = null;
      }

      try {
        final matched = await verifyFns.verifyMnemonicPin(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
        return matched
            ? const VerifyMnemonicPinMatch()
            : const VerifyMnemonicPinNoMatch();
      } on Exception {
        // Infrastructure error (storage IO, Rust panic, missing dek_salt).
        // Return a distinct Error variant so callers do NOT increment the
        // lockout counter — this is not a wrong-credential outcome.
        return const VerifyMnemonicPinError(message: 'Sync engine error');
      } finally {
        _zeroBytesBestEffort(pinBytes);
        _zeroBytesBestEffort(secretKeyBytes);
        pinBytes = null;
        secretKeyBytes = null;
      }
    } catch (_) {
      // Unexpected non-Exception throwable (e.g. Error from an assertion).
      // Treat as infrastructure failure — do not increment lockout.
      return const VerifyMnemonicPinError(message: 'Sync engine error');
    } finally {
      // Belt-and-suspenders: zero anything that survived into this scope.
      _zeroBytesBestEffort(mnemonicBytes);
      _zeroBytesBestEffort(pinBytes);
      _zeroBytesBestEffort(secretKeyBytes);
    }
  }

  /// Recovery: re-derive `wrapped_dek` + `dek_salt` from the in-memory DEK.
  ///
  /// Used when the engine is still unlocked (runtime DEK survived) but the
  /// keychain `wrapped_dek` slot is empty — pairing another device needs
  /// `wrapped_dek` to derive the joiner bundle. The caller collects the
  /// user's PIN and recovery phrase; this method recomputes the secret key
  /// from the mnemonic, calls the `rewrap_dek` FFI, drains the new entries
  /// back to the platform keychain, and flips state to `healthy`.
  ///
  /// Returns true on success. On failure (wrong PIN/mnemonic, missing
  /// handle, FFI error) returns false and leaves state untouched.
  Future<bool> attemptRewrap({
    required String pin,
    required String mnemonic,
  }) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return false;

    final normalized = mnemonic.trim().toLowerCase();
    Uint8List? mnemonicBytes;
    Uint8List? pinBytes;
    List<int>? secretKeyBytes;
    try {
      try {
        mnemonicBytes = secretUtf8Bytes(normalized);
        secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonicBytes);
      } catch (_) {
        return false;
      } finally {
        _zeroBytesBestEffort(mnemonicBytes);
        mnemonicBytes = null;
      }

      try {
        pinBytes = secretUtf8Bytes(pin);
        await ffi.rewrapDek(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        return false;
      } finally {
        _zeroBytesBestEffort(pinBytes);
        _zeroBytesBestEffort(secretKeyBytes);
        pinBytes = null;
        secretKeyBytes = null;
      }

      // Persist the new wrapped_dek + dek_salt back to the platform keychain.
      await drainRustStore(handle);

      state = SyncHealthState.healthy;
      return true;
    } catch (_) {
      return false;
    } finally {
      _zeroBytesBestEffort(mnemonicBytes);
      _zeroBytesBestEffort(pinBytes);
      _zeroBytesBestEffort(secretKeyBytes);
    }
  }
}

/// Lightweight sync status derived from FFI events.
class SyncStatus {
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final int pendingOps;
  final String? lastError;
  final bool hasQuarantinedItems;

  /// Number of local push batches that the engine quarantined because
  /// their envelope exceeded the relay's 1 MB body cap. Refreshed on
  /// every `SyncEvent::QuarantinedBatch` and on `SyncCompleted`. Non-zero
  /// triggers the repair banner on the sync troubleshooting screen.
  final int quarantinedBatchCount;

  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncAt,
    this.pendingOps = 0,
    this.lastError,
    this.hasQuarantinedItems = false,
    this.quarantinedBatchCount = 0,
  });

  bool get hasSyncIssues => hasQuarantinedItems || quarantinedBatchCount > 0;

  SyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    int? pendingOps,
    String? lastError,
    bool? hasQuarantinedItems,
    int? quarantinedBatchCount,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingOps: pendingOps ?? this.pendingOps,
      lastError: lastError,
      hasQuarantinedItems: hasQuarantinedItems ?? this.hasQuarantinedItems,
      quarantinedBatchCount:
          quarantinedBatchCount ?? this.quarantinedBatchCount,
    );
  }
}

/// Pascal-case strings match the Rust `SyncErrorKind` Debug format emitted
/// by `sync_result_to_json` in `prism-sync-ffi/src/api.rs`.
@visibleForTesting
bool isRetryableSyncErrorKind(String? errorKind) {
  switch (errorKind) {
    case 'Network':
    case 'Server':
    case 'Timeout':
      return true;
    default:
      return false;
  }
}

/// Whether a sync failure should be promoted into `SyncStatus.lastError`.
///
/// Retryable failures are already handled by Rust's inner retry loop and the
/// outer auto-sync backoff driver. Keeping them out of `lastError` prevents a
/// user-facing toast for a transient attempt that may recover on the next
/// scheduled retry. Terminal retry exhaustion arrives as an `Error` event with
/// `retryable: false`, and still surfaces.
@visibleForTesting
bool shouldSurfaceSyncError({required String? errorKind, bool? retryable}) {
  return !(retryable ?? isRetryableSyncErrorKind(errorKind));
}

/// Whether the event-driven drain in `SyncStatusNotifier` should fire for
/// a `SyncCompleted` event with the given structured `errorKind`.
///
/// Returns `true` for success (`null`) and transient errors (`Network`,
/// `Server`, `Timeout`) so the secure-store stays in sync even when a
/// single cycle fails. Returns `false` for credential-state errors
/// (`Auth`, `KeyChanged`, `DeviceIdentityMismatch`) so the revoke cleanup
/// path can wipe credentials without the drain writing them back.
@visibleForTesting
bool shouldDrainForCompletedErrorKind(String? errorKind) {
  if (errorKind == null) return true;
  switch (errorKind) {
    case 'Network':
    case 'Server':
    case 'Timeout':
      return true;
    case 'Auth':
    case 'KeyChanged':
    case 'DeviceIdentityMismatch':
      return false;
    case 'EpochRotation':
    case 'Protocol':
    case 'ClockSkew':
      // Rare protocol paths — don't drain because they typically mean
      // something about the device state is inconsistent and the next
      // recovery step will handle persistence.
      return false;
    default:
      // Unknown future kinds — be conservative and drain. Worst case we
      // write slightly stale keys; alternative is losing new ones.
      return true;
  }
}

/// Outcome of the device_id self-check on a `device_revoked` signal.
///
/// We NEVER assume an ambiguous revoke targets us. The old "unknown/unreadable
/// id ⇒ wipe" behavior turned transient auth blips and momentary
/// keychain-read failures into permanent, destructive disconnects (the device
/// stayed `active` server-side, yet the client cleared credentials and showed
/// "Set up sync again"). Ambiguous signals are now confirmed against the relay
/// device registry before anything destructive happens.
enum RevokeSelfCheck {
  /// The event positively names THIS device — safe to act on directly.
  confirmedSelf,

  /// The event names a DIFFERENT device — this device's credentials are fine.
  sibling,

  /// The event carries no usable target id, or this device's own id could not
  /// be read. Must be confirmed against the relay registry before any wipe.
  ambiguous,
}

/// Pure self-check for a `device_revoked` signal. Replaces the old
/// `shouldWipeForRevokeEvent`, which assumed self on any unknown/unreadable id.
@visibleForTesting
RevokeSelfCheck classifyRevokeSelfCheck({
  required String? revokedDeviceId,
  required String? currentDeviceId,
}) {
  if (revokedDeviceId == null || revokedDeviceId.isEmpty) {
    // The relay's HTTP-401 `device_revoked` response carries no device_id, so
    // the event alone cannot tell us whether it targets this device.
    return RevokeSelfCheck.ambiguous;
  }
  if (currentDeviceId == null || currentDeviceId.isEmpty) {
    // We have a target id but cannot read our own to compare. Do NOT assume
    // self — confirm against the registry instead.
    return RevokeSelfCheck.ambiguous;
  }
  return revokedDeviceId == currentDeviceId
      ? RevokeSelfCheck.confirmedSelf
      : RevokeSelfCheck.sibling;
}

/// Result of confirming an ambiguous revoke against the relay device registry.
enum RevokeConfirmation {
  /// The registry positively confirms THIS device is revoked/removed.
  confirmedRevoked,

  /// The registry still lists THIS device as present/active — false alarm.
  stillActive,

  /// The registry could not be consulted conclusively (transient/network
  /// error, unreadable credentials). Stay non-destructive and retry later.
  unknown,
}

/// Pure interpretation of a relay `list_devices` result for THIS device. Note
/// the non-obvious case: a successful listing that simply omits this device is
/// treated as confirmed-revoked.
@visibleForTesting
RevokeConfirmation interpretDeviceRegistryForSelf({
  required List<Map<String, dynamic>> devices,
  required String? currentDeviceId,
}) {
  if (currentDeviceId == null || currentDeviceId.isEmpty) {
    return RevokeConfirmation.unknown;
  }
  for (final device in devices) {
    if (device['device_id'] == currentDeviceId) {
      return device['status'] == 'revoked'
          ? RevokeConfirmation.confirmedRevoked
          : RevokeConfirmation.stillActive;
    }
  }
  // A successful listing that omits this device is positive evidence it was
  // removed from the group.
  return RevokeConfirmation.confirmedRevoked;
}

/// Test seam: when non-null, the event-driven drain path in
/// `SyncStatusNotifier` invokes this instead of acquiring a handle and
/// calling `drainRustStore`. Used by unit tests to observe drain
/// invocations without exercising the FFI or secure storage.
///
/// The override takes no arguments by default (existing tests) and
/// receives a [shouldAbortDrain] via the optional sibling hook below
/// when it wants to race-test mid-drain aborts.
@visibleForTesting
Future<void> Function()? debugDrainRustStoreOverride;

/// Test seam: when non-null, `_confirmRevokeViaRegistry` returns this instead
/// of consulting the relay device registry over FFI. Lets tests exercise both
/// the confirmed-revoke escalation and the ambiguous-unconfirmed credential
/// preservation path without a live handle / secure storage.
@visibleForTesting
Future<RevokeConfirmation> Function()? debugRevokeConfirmationOverride;

/// Test seam: when non-null, `SyncStatusNotifier._scheduleDrain` calls
/// this instead of `debugDrainRustStoreOverride`, passing the per-drain
/// `shouldAbort` closure. Use this for tests that need to prove the
/// drain bails mid-flight when revocation fires: the test's fake
/// drain can `await` on a completer, then check `shouldAbort()` to
/// confirm the gate flipped.
@visibleForTesting
Future<void> Function(bool Function() shouldAbort)?
debugDrainRustStoreOverrideWithAbort;

/// Test seam: override the debounce interval used by `SyncStatusNotifier`
/// for event-driven drains. Set to a very small value (e.g. 1ms) in tests
/// so they don't have to wait 500ms of real time per scenario. Leave as
/// `null` in production to use the default 500ms.
@visibleForTesting
Duration? debugDrainDebounceOverride;

/// Test seam: override the "post-revoke belt-and-suspenders re-cleanup"
/// delay. Production defaults to 2 seconds (longer than any realistic
/// drain write loop). Tests set this to ~50ms so they don't have to
/// wait 2s per revocation scenario.
@visibleForTesting
Duration? debugPostRevokeRecleanOverride;

/// Test seam: when non-null, the post-revoke re-cleanup timer in
/// `_abortPendingDrainForRevoke` calls this instead of
/// `_wipeSyncKeychainEntries`. Lets tests observe that the second-stage
/// cleanup fires even when the first pass was partial.
@visibleForTesting
Future<void> Function()? debugPostRevokeRecleanOverrideCallback;

/// Test seam: when non-null, `SyncStatusNotifier._queryPendingOps` calls this
/// instead of the Rust status FFI. Used to hold pending-op queries open while
/// exercising sync event ordering races.
@visibleForTesting
Future<int> Function()? debugQueryPendingOpsOverride;

@visibleForTesting
SyncStatus syncStatusAfterCompleted({
  required SyncStatus previous,
  required String? rawResultError,
  required int pendingOps,
  required bool hasQuarantinedItems,
  required int quarantinedBatchCount,
  bool surfaceResultError = true,
  DateTime? completedAt,
}) {
  final resultError = rawResultError != null && rawResultError.isNotEmpty
      ? formatPrismSyncError(rawResultError)
      : null;
  return SyncStatus(
    isSyncing: false,
    lastSyncAt: resultError == null
        ? (completedAt ?? DateTime.now())
        : previous.lastSyncAt,
    pendingOps: pendingOps,
    hasQuarantinedItems: hasQuarantinedItems,
    quarantinedBatchCount: quarantinedBatchCount,
    lastError: surfaceResultError ? resultError : null,
  );
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  Timer? _drainDebounce;

  /// Monotonic generation for async status refreshes spawned by sync events.
  ///
  /// SyncStarted and SyncCompleted both query extra state asynchronously. Fast
  /// failure paths can emit SyncStarted followed by SyncCompleted/Error before
  /// those futures resolve; this token keeps an older callback from overwriting
  /// the terminal `isSyncing: false` state that re-enables the settings UI.
  int _statusEventGeneration = 0;

  /// Timer for the belt-and-suspenders post-revoke re-cleanup pass.
  Timer? _postRevokeRecleanTimer;

  /// Monotonic drain generation. Incremented every time
  /// `_abortPendingDrainSafe` runs (which `_abortPendingDrainForRevoke`
  /// calls internally). Each scheduled drain captures this value at
  /// schedule time, and both the timer callback AND the inner
  /// `shouldAbort` hook inside `drainRustStore` compare it to the
  /// current field value. A mismatch means "revocation fired between
  /// schedule and this check — bail." This is the atomic barrier that a
  /// plain `bool` flag can't provide: a timer callback that already
  /// started running has its `myGeneration` captured on the stack and
  /// can't be affected by further bumps, but every suspension point
  /// (`await`) re-checks and bails if it's stale.
  ///
  /// **Monotonic for the lifetime of the notifier — NEVER reset.**
  /// The only writes to this field are the `++` in `_abortPendingDrainSafe`
  /// and the initial `0`. Resetting it on fresh-handle transitions would
  /// reopen a race where a stale in-flight drain from the previous
  /// session could find `myGeneration == _drainGeneration == 0` after
  /// the reset and resume writing. 64-bit int can't wrap in practice
  /// (a billion revokes per second for 292 years).
  int _drainGeneration = 0;

  /// Once credentials have been wiped (device revoked, sync reset,
  /// unrecoverable auth failure), this flag is flipped to `true` and
  /// stays `true` until a fresh handle is created (new pairing / new
  /// unlock). While set, `_scheduleDrain` is a no-op and any in-flight
  /// timer callback bails before touching `drainRustStore`. This is the
  /// belt-and-suspenders gate for Fix 1 of the 2026-04-11 robustness
  /// plan: timer cancellation alone is not enough because a drain
  /// callback may already have started running when revocation fires.
  bool _credentialsRevoked = false;

  /// Debounce interval for event-driven `drainRustStore` calls.
  ///
  /// 500ms (trailing-edge) matches Appendix B.6 of the 2026-04-11 sync
  /// robustness plan: short enough to persist keys quickly after a sync
  /// cycle settles, long enough to coalesce bursts (SyncStarted ->
  /// RemoteChanges -> SyncCompleted) without queuing serial keychain
  /// writes faster than they complete. 200ms would overdrive Android/iOS
  /// secure storage on large drains (15–20 entries, ~30–80ms each).
  static const _drainDebounceInterval = Duration(milliseconds: 500);

  /// Default post-revocation re-cleanup delay. Longer than any realistic
  /// drain write loop (~30-80ms × 15 entries = 450-1200ms) so an
  /// in-flight drain has time to finish its writes before we re-wipe.
  static const _postRevokeRecleanInterval = Duration(seconds: 2);

  Duration get _effectiveDrainDebounce =>
      debugDrainDebounceOverride ?? _drainDebounceInterval;

  Duration get _effectivePostRevokeRecleanDelay =>
      debugPostRevokeRecleanOverride ?? _postRevokeRecleanInterval;

  /// Minimal, always-safe "cancel any in-flight drain" step.
  ///
  /// Bumps the generation token (invalidating any running drain
  /// callback's captured `myGeneration`) and cancels the pending
  /// debounce timer. **Does NOT** set `_credentialsRevoked` and does
  /// NOT schedule the post-revoke re-cleanup. Safe to call from both
  /// self-revoke and sibling-revoke paths, and safe to call when the
  /// event may or may not turn out to target this device.
  ///
  /// Used as the defensive first statement of `_handleDeviceRevoked`
  /// (before any `await`) so a pending drain cannot fire during the
  /// async self-vs-sibling check. If the revocation turns out to be
  /// a sibling, the caller leaves state exactly like this — the flag
  /// stays `false` and the re-cleanup timer never fires, so a fresh
  /// drain can be scheduled immediately after this function returns.
  void _abortPendingDrainSafe() {
    _drainGeneration++;
    _drainDebounce?.cancel();
    _drainDebounce = null;
  }

  /// Full self-revoke abort: suppresses future drains for the lifetime
  /// of this session, invalidates in-flight drains, and schedules the
  /// belt-and-suspenders keychain re-cleanup timer. **Only call this
  /// when the CURRENT device has been revoked** — calling it on a
  /// sibling-revoke path would wipe this device's credentials via the
  /// delayed re-cleanup timer even though this device wasn't revoked.
  ///
  /// The function is idempotent with `_abortPendingDrainSafe`: it
  /// reuses the safe-abort as its first step, so calling both in
  /// sequence (safe first, then full) is fine.
  void _abortPendingDrainForRevoke() {
    _abortPendingDrainSafe();
    _credentialsRevoked = true;

    // Belt-and-suspenders: schedule a delayed keychain re-wipe. If a
    // drain callback was already running when we aborted, its writes
    // may land after `_clearSyncCredentials` completes. The timer fires
    // ~2s later (longer than any realistic drain write loop) and wipes
    // the keychain again, unless a fresh handle has appeared in the
    // meantime (via the `prismSyncHandleProvider` listener resetting
    // `_credentialsRevoked`).
    _postRevokeRecleanTimer?.cancel();
    _postRevokeRecleanTimer = Timer(_effectivePostRevokeRecleanDelay, () async {
      if (!_credentialsRevoked) return; // New handle appeared, skip.
      try {
        final override = debugPostRevokeRecleanOverrideCallback;
        if (override != null) {
          await override();
        } else {
          await _wipeSyncKeychainEntries();
        }
        debugPrint('[SYNC] Post-revoke keychain re-clean completed');
      } catch (e) {
        debugPrint('[SYNC] Post-revoke keychain re-clean failed: $e');
      }
    });
  }

  /// Reset the revoked flag. Must ONLY be called when a fresh handle is
  /// created (new pairing / new unlock) — NOT on the next successful
  /// SyncCompleted, which would re-enable drains against a still-wiped
  /// keychain if any remnant of a prior session leaked through.
  ///
  /// Does NOT reset `_drainGeneration`: that counter is monotonic for
  /// the lifetime of the notifier, see the field's doc comment for why.
  @visibleForTesting
  void debugResetCredentialsRevoked() {
    _credentialsRevoked = false;
    _postRevokeRecleanTimer?.cancel();
    _postRevokeRecleanTimer = null;
  }

  /// Prepare for an explicit local reset/re-pair flow.
  ///
  /// This uses the same drain-suppression barrier as self-revoke cleanup so a
  /// queued or already-running event-driven drain cannot write old credentials
  /// back into the keychain after the reset path deletes them.
  void prepareForCredentialReset() {
    _abortPendingDrainForRevoke();
    state = const SyncStatus();
  }

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _drainDebounce?.cancel();
      _drainDebounce = null;
      _postRevokeRecleanTimer?.cancel();
      _postRevokeRecleanTimer = null;
    });

    // When a fresh handle is created (new pairing or new unlock) the
    // `prismSyncHandleProvider` transitions from null (or from a
    // previous handle) to a new instance. That's the only moment we
    // allow the revoked flag to reset — NOT on the next SyncCompleted,
    // which would re-enable drains if any remnant of the previous
    // session leaked through.
    //
    // **Round 4 Fix 2:** do NOT reset `_drainGeneration` here. The
    // counter is monotonic for the lifetime of the notifier. A stale
    // in-flight drain from the previous session may still resume after
    // the reset; if we zeroed the counter, its captured `myGeneration`
    // could suddenly match and the drain would write back wiped
    // credentials. Because the generation was bumped at least once by
    // the abort that preceded the new handle, any captured value is
    // guaranteed to be strictly less than the current field value.
    ref.listen<AsyncValue<ffi.PrismSyncHandle?>>(prismSyncHandleProvider, (
      prev,
      next,
    ) {
      final nextHandle = next.value;
      final prevHandle = prev?.value;
      if (nextHandle != null && !identical(prevHandle, nextHandle)) {
        _credentialsRevoked = false;
        _postRevokeRecleanTimer?.cancel();
        _postRevokeRecleanTimer = null;
      }
    });

    ref.listen(syncEventStreamProvider, (prev, next) {
      next.whenData((event) {
        if (event.isSyncCompleted) {
          final generation = ++_statusEventGeneration;
          final rawResultError =
              (event.data['result'] as Map<String, dynamic>?)?['error']
                  as String?;
          final resultMap = event.data['result'] as Map<String, dynamic>?;
          // Structured `error_code` + `remote_wipe` propagated from the
          // Rust engine via `populate_result_error`. When the engine
          // wraps a `device_revoked` response into `Ok(result)`, the
          // retry loop surfaces it here instead of through a separate
          // `Error` event. We must trigger credential cleanup on this
          // path too, otherwise a mid-cycle 401 would leak the creds.
          // (Fix 2 of the 2026-04-11 sync robustness plan.)
          final resultErrorCode = resultMap?['error_code'] as String?;
          final resultRemoteWipe = resultMap?['remote_wipe'] as bool?;
          final isDeviceRevokedFromResult = resultErrorCode == 'device_revoked';
          final structuredError = rawResultError == null
              ? null
              : PrismSyncStructuredError.tryParseMessage(rawResultError);
          final completedError = structuredError?.userMessage ?? rawResultError;
          final displayableCompletedError =
              completedError != null && completedError.isNotEmpty
              ? formatPrismSyncError(completedError)
              : null;
          final surfaceCompletedError =
              displayableCompletedError != null &&
              shouldSurfaceSyncError(
                errorKind: event.errorKind,
                retryable: null,
              );
          final previous = state;
          state = state.copyWith(
            isSyncing: false,
            lastError: surfaceCompletedError ? displayableCompletedError : null,
          );
          // Re-query pending ops, schema-quarantine, and push-quarantine
          // state after sync completes. The push-quarantine count needs to
          // refresh here in addition to the per-event handler below because
          // a cycle may have cleared quarantines via recovery (Phase 1C).
          Future.wait<dynamic>([
            _queryPendingOps(),
            _queryQuarantine(),
            _queryQuarantinedBatchCount(),
          ]).then((results) {
            if (generation != _statusEventGeneration) {
              return;
            }
            state = syncStatusAfterCompleted(
              previous: previous,
              rawResultError: displayableCompletedError,
              pendingOps: results[0] as int,
              hasQuarantinedItems: results[1] as bool,
              quarantinedBatchCount: results[2] as int,
              surfaceResultError: surfaceCompletedError,
              completedAt: DateTime.now(),
            );
          });
          final isRevoked =
              (structuredError?.isDeviceRevoked ?? false) ||
              isDeviceRevokedFromResult;
          if (isRevoked) {
            final wipe =
                structuredError?.remoteWipe ?? resultRemoteWipe ?? false;
            final revokedDeviceId =
                resultMap?['device_id'] as String? ??
                event.data['device_id'] as String?;
            _handleDeviceRevokedFromAuthFailure(
              wipe,
              revokedDeviceId: revokedDeviceId,
            );
          }
          // Event-driven drain: persist the Rust MemorySecureStore back to
          // the platform keychain whenever a sync cycle completes. Covers
          // the auto-sync driver path (`api.rs:1361`) which runs entirely
          // inside Rust and never invoked `drainRustStore` before. Skip
          // the drain for credential-state errors so revoke cleanup can
          // wipe the keychain without our writing stale keys back.
          if (!isRevoked && shouldDrainForCompletedErrorKind(event.errorKind)) {
            _scheduleDrain();
          }
        } else if (event.isEpochRotated) {
          // Epoch rotation is the most important persistence moment: a new
          // epoch key was recovered and must reach the keychain before the
          // next restart.
          _scheduleDrain();
        } else if (event.isSyncStarted) {
          final generation = ++_statusEventGeneration;
          state = state.copyWith(isSyncing: true);
          // Snapshot current pending ops count when sync begins so the UI
          // can show how many ops are waiting to be pushed.
          _queryPendingOps().then((count) {
            if (generation != _statusEventGeneration) {
              return;
            }
            state = state.copyWith(isSyncing: true, pendingOps: count);
          });
        } else if (event.isError) {
          _statusEventGeneration++;
          final structuredError =
              PrismSyncStructuredError.fromSyncEvent(event) ??
              PrismSyncStructuredError.tryParseMessage(
                event.data['message'] as String? ?? '',
              );
          final errorMessage = event.data['message'] as String? ?? '';
          final displayableError =
              (structuredError?.userMessage ?? errorMessage).isNotEmpty
              ? formatPrismSyncError(
                  structuredError?.userMessage ?? errorMessage,
                )
              : null;
          final surfaceError =
              displayableError != null &&
              shouldSurfaceSyncError(
                errorKind: event.errorKind,
                retryable: event.data['retryable'] as bool?,
              );
          state = state.copyWith(
            isSyncing: false,
            lastError: surfaceError ? displayableError : null,
          );
          if (structuredError?.isDeviceRevoked ?? false) {
            _handleDeviceRevokedFromAuthFailure(
              structuredError?.remoteWipe ?? false,
              revokedDeviceId: event.data['device_id'] as String?,
            );
          }
        } else if (event.isDeviceRevoked) {
          _statusEventGeneration++;
          state = state.copyWith(isSyncing: false);
          _handleDeviceRevoked(event);
        } else if (event.isQuarantinedBatch) {
          // The Rust engine just quarantined a push batch (or another one
          // already in the queue). Refresh the count so the
          // sync-troubleshooting banner appears immediately, without
          // waiting for the next SyncCompleted.
          _queryQuarantinedBatchCount().then((count) {
            state = state.copyWith(quarantinedBatchCount: count);
          });
        }
      });
    });
    return const SyncStatus();
  }

  /// Schedule a trailing-edge debounced drain of the Rust MemorySecureStore
  /// back to the platform keychain.
  ///
  /// Rapid bursts (e.g. SyncCompleted + EpochRotated in the same cycle)
  /// coalesce into a single drain call that fires after the debounce
  /// window elapses. If the handle is disposed before the window elapses,
  /// the cancelled timer simply drops the callback.
  ///
  /// **Generation token:** each scheduled drain captures
  /// `_drainGeneration` at schedule time. If `_abortPendingDrainForRevoke`
  /// fires before the timer callback runs (bumping the counter), the
  /// captured value becomes stale and both the callback and the
  /// `shouldAbort` hook passed into `drainRustStore` bail. A single bool
  /// gate can't catch the case where a drain is already mid-`await` when
  /// revocation fires; the generation comparison can.
  void _scheduleDrain() {
    if (_credentialsRevoked) {
      // Credentials have been wiped. A drain at this point would read
      // the (still populated) Rust MemorySecureStore and write the
      // secrets back to the keychain, undoing revocation.
      return;
    }
    _drainDebounce?.cancel();
    final myGeneration = _drainGeneration;
    _drainDebounce = Timer(_effectiveDrainDebounce, () async {
      // Check 1: synchronous gate at the top of the callback. If
      // revocation fired during the debounce window, bail immediately
      // before even touching the FFI.
      if (_credentialsRevoked || _drainGeneration != myGeneration) {
        return;
      }
      // Shared `shouldAbort` closure passed into `drainRustStore`. It
      // is re-evaluated at every await point inside the drain loop,
      // so a revocation firing mid-write short-circuits the remaining
      // writes. See `drainRustStore` for placement details.
      bool shouldAbort() =>
          _credentialsRevoked || _drainGeneration != myGeneration;
      final plainOverride = debugDrainRustStoreOverride;
      final abortAwareOverride = debugDrainRustStoreOverrideWithAbort;
      try {
        if (abortAwareOverride != null) {
          await abortAwareOverride(shouldAbort);
          return;
        }
        if (plainOverride != null) {
          await plainOverride();
          return;
        }
        final handle = ref.read(prismSyncHandleProvider).value;
        if (handle == null) return;
        await drainRustStore(handle, shouldAbort: shouldAbort);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Event-driven drain failed (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    });
  }

  /// Query the Rust sync engine for the current number of unpushed pending ops.
  Future<int> _queryPendingOps() async {
    final override = debugQueryPendingOpsOverride;
    if (override != null) {
      return await override();
    }
    try {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) return 0;
      final json = await ffi.status(handle: handle);
      final status = jsonDecode(json) as Map<String, dynamic>;
      return (status['pending_ops'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Check whether any fields have been quarantined due to type mismatches.
  Future<bool> _queryQuarantine() async {
    try {
      final quarantine = ref.read(syncQuarantineServiceProvider);
      await quarantine.repairLegacyMemberAgeStringMismatches();
      return await quarantine.hasQuarantinedItems();
    } catch (_) {
      return false;
    }
  }

  /// Count push batches that the Rust engine has quarantined because their
  /// envelope exceeded the relay's 1 MB body cap. Used by the sync
  /// troubleshooting banner to surface the repair flow. Returns 0 if no
  /// handle is configured or the FFI call fails — Phase 1B is a defense-
  /// in-depth path, so a transient query failure must not block UI.
  Future<int> _queryQuarantinedBatchCount() async {
    try {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) return 0;
      final count = await ffi.quarantinedBatchCount(handle: handle);
      return count.toInt();
    } catch (_) {
      return 0;
    }
  }

  /// Re-query the quarantined-batch count from the Rust engine and merge it
  /// into `state`. Used by the Phase 1C `repairQuarantinedBatches` provider
  /// after a successful repair to drop the banner to zero immediately,
  /// rather than waiting for the next SyncCompleted event.
  Future<void> refreshQuarantinedBatchCount() async {
    final count = await _queryQuarantinedBatchCount();
    state = state.copyWith(quarantinedBatchCount: count);
  }

  /// Handle a DeviceRevoked event. Rust emits this event for BOTH
  /// self-revoke AND sibling-revoke (another device in the group being
  /// revoked), so the first thing we do is determine which case this
  /// is and only wipe this device's credentials on self-revoke.
  ///
  /// On self-revoke: clears sync credentials, stops auto-sync, and if
  /// `remoteWipe` is set also deletes the sync database file.
  ///
  /// On sibling-revoke: nothing to do except defensively cancel any
  /// pending drain that was already scheduled — we do NOT wipe
  /// credentials and we do NOT schedule the post-revoke re-cleanup
  /// timer.
  ///
  /// **Round 4 Fix 1:** the earlier round called the FULL
  /// `_abortPendingDrainForRevoke` as the first statement, which set
  /// `_credentialsRevoked = true` and scheduled the 2-second re-cleanup
  /// timer unconditionally. On sibling-revoke, the re-cleanup timer
  /// would then fire and wipe THIS device's credentials even though
  /// this device wasn't revoked. The split below preserves the
  /// "cancel at the top before any await" pattern for the pending
  /// drain (via the safe variant) while keeping the full wipe behind
  /// the self-revoke branch.
  Future<void> _handleDeviceRevoked(SyncEvent event) async {
    // Step 1 — always safe: cancel any pending debounced drain and
    // invalidate any in-flight drain via the generation bump. This is
    // the "cancel at the top, before any await" pattern, but WITHOUT
    // setting `_credentialsRevoked` and WITHOUT scheduling re-cleanup.
    // Safe to call on both self and sibling paths.
    _abortPendingDrainSafe();

    final revokedDeviceId = event.data['device_id'] as String?;
    final wipe = event.remoteWipe;

    // Step 2 — determine whether this event targets us. We NEVER assume an
    // ambiguous revoke is self-targeted; an unreadable own id or a missing
    // target id is confirmed against the relay registry first.
    final currentDeviceId = await _readDecodedCredential('device_id');
    switch (classifyRevokeSelfCheck(
      revokedDeviceId: revokedDeviceId,
      currentDeviceId: currentDeviceId,
    )) {
      case RevokeSelfCheck.sibling:
        // Sibling revoke: our credentials are fine. The pending drain was
        // cancelled defensively by `_abortPendingDrainSafe`, but
        // `_credentialsRevoked` is NOT set and no re-cleanup was scheduled,
        // so THIS device's keychain stays intact.
        return;
      case RevokeSelfCheck.ambiguous:
        final confirmation = await _confirmRevokeViaRegistry();
        if (confirmation != RevokeConfirmation.confirmedRevoked) {
          debugPrint(
            '[SYNC] Ambiguous device_revoked notification not confirmed by '
            'registry ($confirmation) — preserving credentials',
          );
          return;
        }
      case RevokeSelfCheck.confirmedSelf:
        break;
    }

    // Step 3 — confirmed self-revoke. Escalate from safe-abort to the full
    // revoke path: this sets the suppression flag and schedules the
    // post-revoke re-cleanup timer.
    _abortPendingDrainForRevoke();

    // Stop auto-sync to prevent background retry loops.
    try {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle != null) {
        await ffi.setAutoSync(
          handle: handle,
          enabled: false,
          debounceMs: BigInt.from(0),
          retryDelayMs: BigInt.from(0),
          maxRetries: 0,
        );
      }
    } catch (e) {
      debugPrint('[SYNC] Failed to disable auto-sync after revocation: $e');
    }

    // If remote wipe was requested, delete the sync database.
    if (wipe) {
      await _wipeLocalData();
    }

    // Clear sync credentials from keychain.
    await _clearSyncCredentials();

    ref
        .read(syncHealthProvider.notifier)
        .setState(SyncHealthState.disconnected);
  }

  Future<void> _handleDeviceRevokedFromAuthFailure(
    bool remoteWipe, {
    String? revokedDeviceId,
  }) async {
    // Step 1 — always safe: cancel any pending debounced drain. We do NOT
    // yet escalate to the full revoke path because the event might target
    // a sibling device.
    _abortPendingDrainSafe();

    // Step 2 — self-check. Only a POSITIVE self-match acts outright; an
    // ambiguous signal (the HTTP-401 `device_revoked` response carries no
    // device_id, or our own id is unreadable) is confirmed against the relay
    // device registry before anything destructive. We NEVER assume self on an
    // unknown id — that turned transient auth blips into permanent
    // disconnects while the device was still active server-side.
    final currentDeviceId = await _readDecodedCredential('device_id');
    switch (classifyRevokeSelfCheck(
      revokedDeviceId: revokedDeviceId,
      currentDeviceId: currentDeviceId,
    )) {
      case RevokeSelfCheck.sibling:
        debugPrint(
          '[SYNC] Auth-failure revoke targets sibling '
          '($revokedDeviceId != $currentDeviceId) — keeping credentials',
        );
        return;
      case RevokeSelfCheck.ambiguous:
        final confirmation = await _confirmRevokeViaRegistry();
        if (confirmation != RevokeConfirmation.confirmedRevoked) {
          // Not a confirmed revoke (registry still lists us, or the check was
          // inconclusive). Keep credentials + relay config so the engine stays
          // usable and can self-heal — this is the core false-revoke fix.
          debugPrint(
            '[SYNC] Ambiguous device_revoked not confirmed by registry '
            '($confirmation) — preserving credentials',
          );
          return;
        }
      case RevokeSelfCheck.confirmedSelf:
        break;
    }

    // Step 3 — confirmed self-revoke. Escalate from safe-abort to the full
    // revoke path.
    _abortPendingDrainForRevoke();
    try {
      if (remoteWipe) {
        debugPrint('[SYNC] Device flagged for remote wipe — wiping sync data');
        await _wipeLocalData();
      }
      await _clearSyncCredentials();
      ref
          .read(syncHealthProvider.notifier)
          .setState(SyncHealthState.disconnected);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Wipe status handling failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }

  /// Read a `prism_sync.<key>` credential from secure storage and decode it
  /// (base64 → utf8, falling back to the raw value). Returns null when the
  /// entry is missing/empty or unreadable — callers MUST treat null as
  /// "unknown", never "assume self".
  Future<String?> _readDecodedCredential(String key) async {
    String? raw;
    try {
      raw = await _safeReadValue('$_secureStorePrefix$key');
    } catch (_) {
      // Read failed (transient, or missing plugin under test) → unknown.
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(raw));
    } catch (_) {
      return raw; // Already plain text.
    }
  }

  /// Confirm whether THIS device is genuinely revoked by consulting the relay
  /// device registry. Used to resolve an *ambiguous* `device_revoked` signal
  /// (no target id, or unreadable own id) BEFORE any destructive wipe.
  ///
  /// Returns [RevokeConfirmation.confirmedRevoked] only on positive evidence:
  /// either `list_devices` itself rejects this device as revoked, or the
  /// listing omits/marks-revoked this device. Anything inconclusive (missing
  /// credentials, network/transient error, unparseable response) returns a
  /// non-confirming result so credentials are preserved.
  Future<RevokeConfirmation> _confirmRevokeViaRegistry() async {
    final override = debugRevokeConfirmationOverride;
    if (override != null) return override();

    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return RevokeConfirmation.unknown;

    final syncId = await _readDecodedCredential('sync_id');
    final deviceId = await _readDecodedCredential('device_id');
    final sessionToken = await _readDecodedCredential('session_token');
    if (syncId == null || deviceId == null || sessionToken == null) {
      return RevokeConfirmation.unknown;
    }

    final String jsonStr;
    try {
      jsonStr = await ffi.listDevices(
        handle: handle,
        syncId: syncId,
        deviceId: deviceId,
        sessionToken: sessionToken,
      );
    } catch (e) {
      // If the registry check ITSELF is rejected as device_revoked, that's an
      // independent positive confirmation. Anything else (network/timeout/
      // transient auth) is inconclusive — do NOT wipe.
      final structured = PrismSyncStructuredError.tryParse(e);
      if (structured?.isDeviceRevoked ?? false) {
        return RevokeConfirmation.confirmedRevoked;
      }
      debugPrint('[SYNC] Revoke registry check failed (inconclusive): $e');
      return RevokeConfirmation.unknown;
    }

    final List<Map<String, dynamic>> devices;
    try {
      final decoded = jsonDecode(jsonStr);
      devices = (decoded as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return RevokeConfirmation.unknown;
    }

    return interpretDeviceRegistryForSelf(
      devices: devices,
      currentDeviceId: deviceId,
    );
  }

  /// Delete the sync database file and its WAL/SHM companions, clear all
  /// synced content from the Drift app database, and clear the media cache.
  Future<void> _wipeLocalData() async {
    // 1. Delete the Rust sync DB files.
    try {
      final dir = await getAppDataDir();
      final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final wal = File('$dbPath-wal');
      final shm = File('$dbPath-shm');
      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
      debugPrint('[SYNC] Sync database wiped');
    } catch (e) {
      debugPrint('[SYNC] Failed to delete sync DB (non-fatal): $e');
    }

    // 2. Delete all synced content rows from the Drift app database.
    try {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        await db.customStatement('DELETE FROM habit_completions');
        await db.customStatement('DELETE FROM habits');
        await db.customStatement('DELETE FROM poll_votes');
        await db.customStatement('DELETE FROM poll_options');
        await db.customStatement('DELETE FROM polls');
        await db.customStatement('DELETE FROM chat_messages');
        await db.customStatement('DELETE FROM conversation_categories');
        await db.customStatement('DELETE FROM conversations');
        await db.customStatement('DELETE FROM front_session_comments');
        await db.customStatement('DELETE FROM fronting_sessions');
        await db.customStatement('DELETE FROM sleep_sessions');
        await db.customStatement('DELETE FROM custom_field_values');
        await db.customStatement('DELETE FROM custom_fields');
        await db.customStatement('DELETE FROM member_group_entries');
        await db.customStatement('DELETE FROM member_groups');
        await db.customStatement('DELETE FROM notes');
        await db.customStatement('DELETE FROM reminders');
        await db.customStatement('DELETE FROM friends');
        await db.customStatement('DELETE FROM sharing_requests');
        await db.customStatement('DELETE FROM media_attachments');
        await db.customStatement('DELETE FROM members');
        await db.customStatement('DELETE FROM plural_kit_sync_state');
        await db.customStatement('DELETE FROM system_settings');
        await db.customStatement('DELETE FROM sync_quarantine');
      });
      // customStatement bypasses Drift's typed-write notification.
      // A remote-revoke wipe normally triggers a full app reload, but
      // if the app stays live after revoke (rare but possible), the
      // frontingTableTickerProvider and any active stream queries
      // would otherwise still reflect the pre-wipe state. Notify
      // explicitly across every table touched above so the live UI
      // collapses to the empty state without needing the reload.
      db.notifyUpdates({
        const TableUpdate('habit_completions'),
        const TableUpdate('habits'),
        const TableUpdate('poll_votes'),
        const TableUpdate('poll_options'),
        const TableUpdate('polls'),
        const TableUpdate('chat_messages'),
        const TableUpdate('conversation_categories'),
        const TableUpdate('conversations'),
        const TableUpdate('front_session_comments'),
        const TableUpdate('fronting_sessions'),
        const TableUpdate('sleep_sessions'),
        const TableUpdate('custom_field_values'),
        const TableUpdate('custom_fields'),
        const TableUpdate('member_group_entries'),
        const TableUpdate('member_groups'),
        const TableUpdate('notes'),
        const TableUpdate('reminders'),
        const TableUpdate('friends'),
        const TableUpdate('sharing_requests'),
        const TableUpdate('media_attachments'),
        const TableUpdate('members'),
        const TableUpdate('plural_kit_sync_state'),
        const TableUpdate('system_settings'),
        const TableUpdate('sync_quarantine'),
      });
      debugPrint('[SYNC] App database content wiped');
    } catch (e) {
      debugPrint('[SYNC] Failed to wipe app DB content (non-fatal): $e');
    }

    // 3. Clear the media cache.
    try {
      await ref.read(downloadManagerProvider).clearCache();
      debugPrint('[SYNC] Media cache cleared');
    } catch (e) {
      debugPrint('[SYNC] Failed to clear media cache (non-fatal): $e');
    }
  }

  /// Narrow keychain-wipe helper — deletes every static allow-list
  /// entry plus any dynamic `prism_sync.*` entries present in the keychain.
  /// No state transitions, no provider invalidation, no UI side effects.
  /// Shared between `_clearSyncCredentials` (primary cleanup) and
  /// `_abortPendingDrainForRevoke`'s belt-and-suspenders post-revoke
  /// re-cleanup timer.
  Future<void> _wipeSyncKeychainEntries() async {
    await _deleteSyncCredentialKeychainEntries(
      readAll: _safeReadAllEntries,
      deleteKey: _checkedDeleteKey,
    );
    try {
      await _runtimeDekStore.deleteWrappingKey();
    } catch (_) {
      // Best effort — the wrapped blob was already deleted above.
    }
    await _clearBiometricSyncDekBestEffort(ref);
  }

  /// Clear all sync credentials from the platform keychain.
  ///
  /// Wipes the static allow-list first, then scans for any dynamic
  /// `epoch_key_*` / `runtime_keys_*` entries and deletes them too.
  /// Dynamic cleanup is required because those keys accumulate across
  /// epoch rotations — leaving stale entries behind would let them seed
  /// into a freshly-paired handle and corrupt the new group's key
  /// hierarchy.
  Future<void> _clearSyncCredentials() async {
    // Abort any pending debounced drain FIRST. If a drain callback is
    // already queued for 500ms from now, it would otherwise run after
    // we've deleted everything and write the secrets back from Rust.
    _abortPendingDrainForRevoke();
    await _wipeSyncKeychainEntries();
    debugPrint('[SYNC] Sync credentials cleared');
  }

  /// Clears the quarantine flag after the user dismisses quarantined items.
  void clearQuarantineFlag() {
    state = SyncStatus(
      isSyncing: state.isSyncing,
      lastSyncAt: state.lastSyncAt,
      pendingOps: state.pendingOps,
      lastError: state.lastError,
      hasQuarantinedItems: false,
      quarantinedBatchCount: state.quarantinedBatchCount,
    );
  }
}

// ---------------------------------------------------------------------------
// Persisted sync settings (relay URL, sync ID)
// ---------------------------------------------------------------------------

const kSyncRelayUrlKey = 'prism_sync.relay_url';
const kSyncIdKey = 'prism_sync.sync_id';

/// The relay URL configured for sync. Null when sync is not set up.
/// Values are stored base64-encoded in the keychain.
final relayUrlProvider = FutureProvider<String?>((ref) async {
  final value = await _safeReadValue(kSyncRelayUrlKey);
  if (value == null || value.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(value));
  } catch (_) {
    return value; // Fallback: already plain text (legacy)
  }
});

/// The sync group ID for this device. Null when sync is not set up.
/// Values are stored base64-encoded in the keychain.
final syncIdProvider = FutureProvider<String?>((ref) async {
  final value = await _safeReadValue(kSyncIdKey);
  if (value == null || value.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(value));
  } catch (_) {
    return value; // Fallback: already plain text (legacy)
  }
});

/// The durable device ID from the platform keychain.
final syncDeviceIdProvider = FutureProvider<String?>((ref) async {
  return decodeStoredUtf8(await _safeReadValue(kSyncDeviceIdKey));
});

/// Whether the device secret is durably present in the platform keychain.
final syncDeviceSecretPresentProvider = FutureProvider<bool>((ref) async {
  final value = await _safeReadValue(kSyncDeviceSecretKey);
  return value != null && value.isNotEmpty;
});

/// Whether the wrapped DEK is durably present in the platform keychain.
/// Used to gate the device-pairing entry point: missing `wrapped_dek`
/// breaks the inviter side of the pairing ceremony, so the user must
/// run the wrapped_dek recovery flow before attempting to pair.
final syncWrappedDekPresentProvider = FutureProvider<bool>((ref) async {
  final value = await _safeReadValue('${_secureStorePrefix}wrapped_dek');
  return value != null && value.isNotEmpty;
});

// ---------------------------------------------------------------------------
// Device identity (node ID)
// ---------------------------------------------------------------------------

/// The node ID for this device. Used in diagnostics and debug views.
/// Returns null when the handle is not yet initialised or before pairing.
final nodeIdProvider = FutureProvider<String?>((ref) async {
  final handle = ref.watch(prismSyncHandleProvider).value;
  if (handle == null) return null;
  return ffi.getNodeId(handle: handle);
});

// ---------------------------------------------------------------------------
// Last sync time (convenience alias from SyncStatus)
// ---------------------------------------------------------------------------

/// The time of the last successful sync. Null when no sync has occurred.
final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  return ref.watch(syncStatusProvider).lastSyncAt;
});

// ---------------------------------------------------------------------------
// WebSocket connection status
// ---------------------------------------------------------------------------

/// Whether the WebSocket is currently authenticated and receiving notifications.
/// Event-driven: updates instantly when the Rust WebSocket connects or disconnects
/// via the SyncEvent stream (no polling).
final websocketConnectedProvider =
    NotifierProvider<WebSocketConnectedNotifier, bool>(
      WebSocketConnectedNotifier.new,
    );

class WebSocketConnectedNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Listen to the sync event stream for WebSocket state changes.
    ref.listen(syncEventStreamProvider, (prev, next) {
      next.whenData((event) {
        if (event.type == 'WebSocketStateChanged') {
          state = event.data['connected'] as bool? ?? false;
        }
      });
    });
    // The WebSocket may already be connected (auth_ok fires during
    // configureEngine, before the event stream subscription exists).
    // Query the actual state after the synchronous frame completes so the
    // event-stream listener above is already subscribed — avoids a race
    // where a WebSocketStateChanged event fires during the query.
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle != null) {
      Future(() async {
        try {
          final connected = await ffi.isWebsocketConnected(handle: handle);
          if (state != connected) {
            state = connected;
          }
        } catch (_) {
          // Non-fatal — event stream will update on next transition
        }
      });
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Convenience
// ---------------------------------------------------------------------------

/// Call to trigger an immediate sync cycle.
///
/// Also attempts to reconnect the WebSocket if it is currently disconnected,
/// resetting the exponential backoff so real-time notifications resume
/// immediately rather than waiting for the next backoff interval.
///
/// Fire-and-forget semantics: this used to let [ffi.syncNow] throw through.
/// After the inner-retry rewrite in `sync_service.rs`, exhausted retries now
/// surface as a thrown `CoreError::Relay` rather than being silently buried
/// in the `SyncResult.error` field. Callers of `triggerSync` (auto-resume,
/// background triggers) don't want the exception to propagate — the outer
/// auto-sync driver will handle sustained failures. Log as a warning and
/// continue.
Future<void> triggerSync(ffi.PrismSyncHandle handle) async {
  // Best-effort WebSocket reconnect (non-fatal if it fails).
  try {
    await ffi.reconnectWebsocket(handle: handle);
  } catch (_) {}
  try {
    await ffi.syncNow(handle: handle);
  } catch (e, st) {
    ErrorReportingService.instance.report(
      'triggerSync: sync_now failed (non-fatal, driver will retry): $e',
      severity: ErrorSeverity.warning,
      stackTrace: st,
    );
  }
}

/// Phase 1C — repair any push-quarantined batches by repartitioning their
/// ops into smaller sub-batches.
///
/// Calls the Rust `repair_quarantined_batches` FFI, then refreshes the
/// quarantined-batch count on `syncStatusProvider` so the troubleshooting
/// banner drops to zero immediately on success. Triggers an auto-sync so
/// the freshly repartitioned batches push without waiting for the next
/// scheduled cycle.
///
/// Returns the number of `push_quarantine` rows successfully repaired.
/// Throws on FFI errors; callers are expected to surface a user-facing
/// snackbar around the call.
///
/// **Test seam:** when [debugRepairQuarantinedBatchesOverride] is non-null,
/// the FFI call is skipped and the override is invoked instead. Used by
/// widget tests that need to assert the action fires without exercising
/// the Rust engine.
Future<int> repairQuarantinedBatches(WidgetRef ref) async {
  final override = debugRepairQuarantinedBatchesOverride;
  int repaired;
  if (override != null) {
    repaired = await override();
  } else {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      throw StateError('repairQuarantinedBatches: no active handle');
    }
    final result = await ffi.repairQuarantinedBatches(handle: handle);
    repaired = result.toInt();
  }

  // Refresh the count immediately so the banner drops without waiting for
  // the next SyncCompleted event.
  await ref.read(syncStatusProvider.notifier).refreshQuarantinedBatchCount();

  // Best-effort: kick off an auto-sync so the freshly repartitioned batches
  // push right away. We don't await this — the auto-sync driver handles
  // sustained failures on its own.
  final handle = ref.read(prismSyncHandleProvider).value;
  if (handle != null) {
    unawaited(triggerSync(handle));
  }

  return repaired;
}

/// Test seam: when non-null, [repairQuarantinedBatches] calls this instead
/// of the Rust FFI. Returns the synthetic "repaired" count for tests.
@visibleForTesting
Future<int> Function()? debugRepairQuarantinedBatchesOverride;

// ---------------------------------------------------------------------------
// SP boards backfill startup trigger
// ---------------------------------------------------------------------------

const _spBoardsBackfillStartupDelay = Duration(seconds: 5);

/// Runs the SP boards backfill once after a v14→v15 schema upgrade.
///
/// Gated on `system_settings.spBoardsBackfilledAt == null` so it is a
/// no-op on subsequent launches. Runs in the background so it does not block
/// app startup. Two-device safety: the service writes a sentinel before
/// touching any rows; if a peer already ran the backfill, the sentinel check
/// aborts the local run without inserting duplicates.
///
/// This provider is intentionally NOT read from an init hook inside
/// `prism_sync_providers.dart` to avoid the circular-import chain:
///   database_providers → prism_sync_providers → database_providers.
///
/// Instead, callers (e.g. `app.dart` or `database_providers.dart`) should
/// read this provider after app startup to trigger the backfill.
final spBoardsBackfillProvider = FutureProvider<SpBoardsBackfillResult?>((
  ref,
) async {
  // Construct repos directly from the database to avoid importing
  // database_providers.dart (which imports this file, causing a cycle).
  final db = ref.read(databaseProvider);
  final settingsDao = db.systemSettingsDao;
  // syncHandle is null — the backfill run is local-only; no sync ops emitted.
  // The sentinel write goes through the CRDT system on next sync.
  final settingsRepo = DriftSystemSettingsRepository(settingsDao, null);

  final settings = await settingsRepo.getSettings();

  // Already backfilled (or sentinel set by a peer) — skip.
  if (settings.spBoardsBackfilledAt != null) return null;

  // Quick candidate check: any board-emoji DM conversations?
  final candidates = await db
      .customSelect(
        '''
    SELECT COUNT(*) AS c
    FROM conversations
    WHERE is_direct_message = 1
      AND emoji = ?
      AND json_array_length(participant_ids) <= 2
      AND is_deleted = 0
    LIMIT 1
    ''',
        variables: [Variable.withString('\u{1F4DD}')],
      )
      .get();

  final count = candidates.firstOrNull?.read<int>('c') ?? 0;
  if (count == 0) {
    // No candidates — mark as done without running the full service.
    debugPrint('[BOARDS_BACKFILL] No candidate DMs found; marking done.');
    await settingsRepo.updateSpBoardsBackfilledAt(DateTime.now().toUtc());
    return const SpBoardsBackfillResult(
      postsConverted: 0,
      abortedByPeer: false,
    );
  }

  debugPrint(
    '[BOARDS_BACKFILL] Found $count candidate DM(s); delaying startup run '
    'by ${_spBoardsBackfillStartupDelay.inSeconds}s.',
  );
  await Future<void>.delayed(_spBoardsBackfillStartupDelay);

  final refreshedSettings = await settingsRepo.getSettings();
  if (refreshedSettings.spBoardsBackfilledAt != null) return null;

  final boardPostsDao = db.memberBoardPostsDao;
  final membersDao = db.membersDao;
  final boardPostsRepo = DriftMemberBoardPostsRepository(
    boardPostsDao,
    membersDao,
    null, // syncHandle: null — sync ops skipped during backfill (local only)
  );

  final service = SpBoardsBackfillService(
    db: db,
    boardPostsRepo: boardPostsRepo,
    boardPostsDao: boardPostsDao,
    settingsRepo: settingsRepo,
  );

  try {
    final result = await service.run();
    debugPrint(
      '[BOARDS_BACKFILL] Done: ${result.postsConverted} posts converted, '
      'abortedByPeer=${result.abortedByPeer}.',
    );
    // If the backfill produced posts, also ensure boardsEnabled is on.
    if (result.postsConverted > 0) {
      final refreshed = await settingsRepo.getSettings();
      if (!refreshed.boardsEnabled) {
        await settingsRepo.updateBoardsEnabled(true);
      }
      // Idempotently append 'boards' to nav overflow.
      final re2 = await settingsRepo.getSettings();
      final primaryIds = re2.navBarItems;
      final overflowIds = re2.navBarOverflowItems;
      if (!primaryIds.contains('boards') && !overflowIds.contains('boards')) {
        await settingsRepo.updateNavBarOverflowItems([
          ...overflowIds,
          'boards',
        ]);
      }
    }
    return result;
  } catch (e, st) {
    ErrorReportingService.instance.report(
      'SP boards backfill failed (non-fatal): $e',
      severity: ErrorSeverity.warning,
      stackTrace: st,
    );
    return null;
  }
});

// ---------------------------------------------------------------------------
// SP reply quote startup repair
// ---------------------------------------------------------------------------

const _spReplyQuoteBackfillStartupDelay = Duration(seconds: 10);

/// Repairs legacy SP-imported replies that have `reply_to_id` but are missing
/// the quoted author/content snapshot needed by the chat UI.
///
/// Candidate-gated so it is effectively one-time: after the local rows are
/// repaired, later launches return before waiting on sync setup. When sync is
/// available, the repaired fields are emitted as normal chat-message updates so
/// paired devices can converge without reimporting.
final spReplyQuoteBackfillProvider = FutureProvider<SpReplyQuoteBackfillResult?>(
  (ref) async {
    final db = ref.read(databaseProvider);

    // Keep the candidate scan and repair writes out of the critical startup
    // path. If a user opens chat before this runs, legacy imported replies may
    // briefly show without quote snapshots; the repair catches up shortly.
    await Future<void>.delayed(_spReplyQuoteBackfillStartupDelay);

    final hasCandidates = await SpReplyQuoteBackfillService.hasCandidates(db);
    if (!hasCandidates) return null;

    // Start sync setup if it has not already been requested, but don't block
    // local repair batches on the handle. SyncRecordMixin will use the current
    // configured handle when available or defer ops during startup configure.
    unawaited(ref.read(prismSyncHandleProvider.future));
    final service = SpReplyQuoteBackfillService(db: db, syncHandle: null);

    try {
      return await service.run();
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'SP reply quote backfill failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
      return null;
    }
  },
);
