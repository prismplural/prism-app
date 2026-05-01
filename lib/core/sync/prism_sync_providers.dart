import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:drift/drift.dart' show TableUpdate;
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/backup_exclusion.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';

// Dart-side sync integration — manages the Rust FFI handle lifecycle, keychain
// persistence (seed/drain), health state machine, and sync event routing.
//
// Keychain keys (all prefixed prism_sync.*) are written by both Dart (during
// setup/pairing) and Rust FFI (drainRustStore). If you rename a key here, also
// update the Rust SecureStore drain in prism-sync-ffi/src/api.rs and the key
// table in app/CLAUDE.md.
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
      _handle?.dispose();
      _handle = null;
    });

    // Auto-create handle if sync credentials exist from a previous session
    final syncIdB64 = await _storage.read(key: '${_secureStorePrefix}sync_id');
    final relayUrlB64 = await _storage.read(
      key: '${_secureStorePrefix}relay_url',
    );
    if (syncIdB64 != null && syncIdB64.isNotEmpty && relayUrlB64 != null) {
      try {
        // Decode base64-encoded relay URL
        String relayUrl;
        try {
          relayUrl = utf8.decode(base64Decode(relayUrlB64));
        } catch (_) {
          relayUrl = relayUrlB64; // Fallback: already plain text
        }
        return await createHandle(relayUrl: relayUrl);
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

    // Crash recovery for the Rust sync DB staging slot.
    //
    // If a previous cacheRuntimeKeys() wrote the sync DB staging slot but
    // crashed between rekeyDb() and the primary slot write, we need to detect
    // which state the DB is in and promote or discard the staging slot before
    // passing any key to createPrismSync.
    final syncStagingKey = await readStagingSyncDatabaseKeyHex();
    if (syncStagingKey != null) {
      if (File(dbPath).existsSync() &&
          tryOpenEncryptedDb(dbPath, syncStagingKey)) {
        // rekeyDb() completed — promote the staging key to the primary slot.
        debugPrint(
          '[SYNC] Crash-recovery: sync DB staging key verified — promoting',
        );
        await promoteStagingSyncDatabaseKey(syncStagingKey);
      } else {
        // rekeyDb() did NOT complete — staging key is stale. The DB still has
        // the key from the primary slot; discard staging and proceed normally.
        await discardStagingSyncDatabaseKey();
      }
    }

    final databaseKeyHex = await ensureLocalSyncDatabaseKey();
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
    late final SyncHealthState health;
    try {
      if (migrationGateHealth != null) {
        // `unpaired` already means "engine isn't configured; skip the
        // post-config drain / cacheRuntimeKeys / scheduled onResume
        // calls" — exactly the semantics we need here. The modal will
        // drive resumeCleanup() which then transitions away from
        // `inProgress`.
        health = migrationGateHealth;
      } else {
        health = await _autoConfigureIfReady(handle);
      }
      BootTimings.mark('createHandle:_autoConfigureIfReady');
      ref.read(syncHealthProvider.notifier).setState(health);
    } finally {
      syncAutoConfigureInProgress.value = false;
    }

    // Persist any Rust state changes from configureEngine (prevents credential
    // loss if the app crashes before an explicit drain happens).
    if (health == SyncHealthState.healthy) {
      // Check and repair DB key mismatch from a prior crash between Drift and
      // sync DB rotations. If the previous session crashed between the two
      // rotations, the sync DB still has the old key. Now that runtime keys are
      // restored we can derive localStorageKey() and retry the rotation.
      //
      // On normal startups both keys already match LSK so this is a fast no-op
      // (two HKDF derivations + two keychain reads, no PRAGMA rekey).
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
      // contend for the same Rust handle mutex, and run PK-backed group cutover
      // catch-up only after `onResume` has applied startup remote changes. Skip when
      // the engine is not configured (unpaired / needs-password) — onResume would
      // just fail with `sync not configured`.
      if (health == SyncHealthState.healthy) {
        unawaited(() async {
          try {
            await ffi.onResume(handle: handle);
            await catchUpPkBackedSyncOnceAfterCutover(
              handle,
              ref.read(databaseProvider),
            );
            // Persist any state the sync cycle mutated (session_token refresh,
            // epoch advance, etc.) before a subsequent crash could lose it.
            await drainRustStore(handle);
          } catch (e, st) {
            final structuredError = PrismSyncStructuredError.tryParse(e);
            ErrorReportingService.instance.report(
              'Startup catch-up sync failed (non-fatal): '
              '${structuredError?.userMessage ?? e}',
              severity: ErrorSeverity.warning,
              stackTrace: st,
            );
          }
        }());
      }
    }

    return handle;
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
///   * `unpaired`     — sync_id or device_id absent (never paired)
///   * `null`         — credentials present; caller should attempt the
///                      runtime-keys path and may end up healthy / needsPassword
///                      / disconnected depending on what's available
@visibleForTesting
SyncHealthState? classifyHealthFromKeychain({
  required String? syncId,
  required String? deviceId,
}) {
  if (syncId == null || deviceId == null) {
    return SyncHealthState.unpaired;
  }
  return null;
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
///   unpaired      — device has never been paired (sync_id/device_id absent)
///   needsPassword — wrapped runtime cache missing, wrapped_dek exists → password modal
///                   (shown by AppShell listening to syncHealthProvider)
///   disconnected  — credentials gone → reconnect card in sync settings
///
/// Transitions:
///   startup → this method → one of the four states
///   DeviceRevoked WebSocket event → disconnected
///   password entry → Argon2id unlock → healthy
Future<SyncHealthState> _autoConfigureIfReady(
  ffi.PrismSyncHandle handle,
) async {
  // Check if we have the minimum credentials needed
  final syncId = await _storage.read(key: '${_secureStorePrefix}sync_id');
  final deviceId = await _storage.read(key: '${_secureStorePrefix}device_id');
  // Not paired — distinguished from `healthy` so the post-config block in
  // `createHandle` skips cacheRuntimeKeys/drainRustStore/onResume on a
  // locked handle (which would otherwise emit benign "no DEK loaded"
  // warnings during a fresh install).
  final keychainOnly = classifyHealthFromKeychain(
    syncId: syncId,
    deviceId: deviceId,
  );
  if (keychainOnly != null) {
    return keychainOnly;
  }

  // Try the fast path: restore runtime keys from the device-bound wrapped DEK.
  final isUnlocked = await ffi.isUnlocked(handle: handle);
  if (!isUnlocked) {
    final runtimeDekAad = buildRuntimeDekAad(
      syncId: decodeStoredUtf8(syncId),
      deviceId: decodeStoredUtf8(deviceId),
    );
    final deviceSecretB64 = await _storage.read(
      key: '${_secureStorePrefix}device_secret',
    );
    final dekBytes = runtimeDekAad == null
        ? null
        : await _readCachedRuntimeDekForRestore(aad: runtimeDekAad);

    if (dekBytes != null && deviceSecretB64 != null) {
      try {
        await ffi.restoreRuntimeKeys(
          handle: handle,
          dek: dekBytes,
          deviceSecret: base64Decode(deviceSecretB64),
        );
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'restoreRuntimeKeys failed: $e',
          severity: ErrorSeverity.error,
          stackTrace: st,
        );
        return SyncHealthState.disconnected;
      } finally {
        dekBytes.fillRange(0, dekBytes.length, 0);
      }
    } else {
      // No cached DEK. Check if we can recover with a password.
      final wrappedDek = await _storage.read(
        key: '${_secureStorePrefix}wrapped_dek',
      );
      if (wrappedDek != null) {
        return SyncHealthState.needsPassword;
      }
      return SyncHealthState.disconnected;
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

    return SyncHealthState.healthy;
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

const _storage = secureStorage;
const _runtimeDekStore = DeviceBoundRuntimeDekStore();

@visibleForTesting
String? decodeStoredUtf8(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(raw));
  } catch (_) {
    return raw;
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
/// Takes the output of `FlutterSecureStorage.readAll()` and returns the
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
@visibleForTesting
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
    all = await _storage.readAll();
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
      final value = await _storage.read(key: '$_secureStorePrefix$key');
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
  final raw = await _storage.read(key: kSyncIdKey);
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
];

/// Returns the full set of unprefixed secure-store keys the migration's
/// wipe path will clear via the static allow-list, before the dynamic
/// prefix scan runs. Exposed for tests so they can pin the contract that
/// every entry in `_secureStoreKeys` (plus the wipe-only legacy entries)
/// is part of the wipe set.
@visibleForTesting
Set<String> frontingMigrationWipeStaticKeys() {
  return {..._secureStoreKeys, ..._legacyWipeOnlyKeys};
}

/// Returns the dynamic prefixes the wipe path scans for after the static
/// pass. Exposed for tests.
@visibleForTesting
List<String> frontingMigrationWipeDynamicPrefixes() {
  return List.unmodifiable(_dynamicSecureStorePrefixes);
}

Future<void> wipeFrontingMigrationSyncKeychain() async {
  // Static allow-list — drives off the same constants the seed/reset
  // paths use. Adding a new sync-storage key in `_secureStoreKeys` (or a
  // new dynamic prefix in `_dynamicSecureStorePrefixes`) is automatically
  // covered here without a second hand-maintained list.
  for (final key in frontingMigrationWipeStaticKeys()) {
    try {
      await _storage.delete(key: '$_secureStorePrefix$key');
    } catch (_) {
      // Best effort — continue clearing remaining keys.
    }
  }
  try {
    await _runtimeDekStore.deleteWrappingKey();
  } catch (_) {
    // Best effort — the wrapped blob was already deleted above.
  }
  // Dynamic-prefix scan for any `epoch_key_*` / `runtime_keys_*`
  // entries left over from prior pairings.
  try {
    final all = await _storage.readAll();
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_secureStorePrefix)) continue;
      final bare = entry.key.substring(_secureStorePrefix.length);
      if (_dynamicSecureStorePrefixes.any(bare.startsWith)) {
        try {
          await _storage.delete(key: entry.key);
        } catch (_) {}
      }
    }
  } catch (_) {
    // Non-fatal — the next reset will pick them up.
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
  void Function(String message, Object error, StackTrace stackTrace)?
  reportWarning,
}) async {
  final wrapped = await readKey(kRuntimeDekWrappedKey);
  if (wrapped != null && wrapped.isNotEmpty) {
    try {
      final dekBytes = await unwrapDek(wrapped, aad);
      await deleteKey(kRuntimeDekKey);
      return dekBytes;
    } catch (e, st) {
      await deleteKey(kRuntimeDekWrappedKey);
      reportWarning?.call(
        'Wrapped runtime DEK restore failed; cache deleted: $e',
        e,
        st,
      );
    }
  }

  final legacyRaw = await readKey(kRuntimeDekKey);
  if (legacyRaw == null || legacyRaw.isEmpty) return null;

  Uint8List dekBytes;
  try {
    dekBytes = Uint8List.fromList(base64Decode(legacyRaw));
  } catch (e, st) {
    await deleteKey(kRuntimeDekKey);
    reportWarning?.call(
      'Legacy runtime DEK cache was invalid; cache deleted: $e',
      e,
      st,
    );
    return null;
  }

  if (dekBytes.length != 32) {
    dekBytes.fillRange(0, dekBytes.length, 0);
    await deleteKey(kRuntimeDekKey);
    return null;
  }

  try {
    final migrated = await wrapDek(dekBytes, aad);
    await writeKey(kRuntimeDekWrappedKey, migrated);
    await deleteKey(kRuntimeDekKey);
    return dekBytes;
  } catch (e, st) {
    dekBytes.fillRange(0, dekBytes.length, 0);
    await deleteKey(kRuntimeDekKey);
    reportWarning?.call(
      'Legacy runtime DEK migration failed; raw cache deleted: $e',
      e,
      st,
    );
    return null;
  }
}

Future<Uint8List?> _readCachedRuntimeDekForRestore({required String aad}) {
  return readCachedRuntimeDekForRestoreCore(
    aad: aad,
    readKey: (key) => _storage.read(key: key),
    deleteKey: (key) => _storage.delete(key: key),
    writeKey: (key, value) => _storage.write(key: key, value: value),
    unwrapDek: (blob, aad) => _runtimeDekStore.unwrap(blob, aad: aad),
    wrapDek: (dekBytes, aad) => _runtimeDekStore.wrap(dekBytes, aad: aad),
    reportWarning: (message, error, stackTrace) {
      ErrorReportingService.instance.report(
        message,
        severity: ErrorSeverity.warning,
        stackTrace: stackTrace,
      );
    },
  );
}

Future<void> _deleteCachedRuntimeDek({bool deleteWrappingKey = false}) async {
  await _storage.delete(key: kRuntimeDekWrappedKey);
  await _storage.delete(key: kRuntimeDekKey);
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

/// Export the raw DEK from Rust and cache it as a device-bound wrapped blob.
///
/// Call after `initialize()`, `unlock()`, or a completed pairing ceremony —
/// any operation that leaves the key hierarchy unlocked. On subsequent app launches,
/// `_autoConfigureIfReady` unwraps this cached DEK to restore the unlocked
/// state without re-deriving via Argon2id.
/// If the device does not have a sync_id/device_id yet (pre-sync onboarding),
/// the runtime cache is skipped; database-key rotation still runs.
///
/// Also rotates both the Drift app DB and the Rust sync DB to the HKDF-derived
/// local storage key (HKDF(DEK, DeviceSecret)) so the database is tied to
/// both the sync group identity and the device identity.
Future<void> cacheRuntimeKeys(
  ffi.PrismSyncHandle handle,
  AppDatabase db,
) async {
  final runtimeDekAad = buildRuntimeDekAad(
    syncId: decodeStoredUtf8(
      await _storage.read(key: '${_secureStorePrefix}sync_id'),
    ),
    deviceId: decodeStoredUtf8(
      await _storage.read(key: '${_secureStorePrefix}device_id'),
    ),
  );
  if (runtimeDekAad == null) {
    await _deleteCachedRuntimeDek();
    debugPrint(
      '[SYNC] Skipping runtime DEK cache: sync_id/device_id unavailable',
    );
  } else {
    final dekBytes = Uint8List.fromList(await ffi.exportDek(handle: handle));
    try {
      final wrapped = await _runtimeDekStore.wrap(dekBytes, aad: runtimeDekAad);
      await _storage.write(key: kRuntimeDekWrappedKey, value: wrapped);
      await _storage.delete(key: kRuntimeDekKey);
    } catch (e, st) {
      await _deleteCachedRuntimeDek();
      ErrorReportingService.instance.report(
        'Runtime DEK cache wrap failed; cache deleted: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    } finally {
      dekBytes.fillRange(0, dekBytes.length, 0);
    }
  }

  // Rotate both DBs to the HKDF-derived local storage key.
  //
  // Each DB has its own dedicated keychain slot and staging slot for crash
  // safety. The two databases are rotated independently:
  //
  //   1. Drift app DB (prism.db): uses rotateDatabaseToKey() which writes a
  //      staging slot, issues PRAGMA rekey, updates the primary slot, and
  //      deletes the staging slot. Crash recovery is handled in
  //      database_provider.dart _openConnection() on the next startup.
  //
  //   2. Rust sync DB (prism_sync.db): uses the same staging protocol via
  //      rotateSyncDatabaseKey(). Crash recovery is handled in createHandle()
  //      on the next startup before createPrismSync() is called.
  //
  // Order: Drift first, Rust second.
  //
  // A crash between the two rotations leaves Drift on LSK (new key) and Rust
  // on the old key. On the next launch:
  //   - createHandle() opens the sync DB with the old key (primary sync slot
  //     was not yet updated) — succeeds.
  //   - _autoConfigureIfReady → cacheRuntimeKeys: reads both slots, sees
  //     sync slot ≠ LSK, retries the sync DB rotation only.
  //
  // This ordering is safe because each DB's slot is updated atomically within
  // its own staging protocol, and the mismatch check below covers BOTH slots.
  try {
    final lskBytes = Uint8List.fromList(
      await ffi.localStorageKey(handle: handle),
    );
    final newHexKey = lskBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // Check Drift slot.
    final currentDriftKey = await readDatabaseKeyHex();
    if (currentDriftKey != newHexKey) {
      await rotateDatabaseToKey(db: db, newKey: lskBytes);
    }

    // Check sync DB slot independently — it may lag if a previous rotation
    // crashed between the Drift and Rust rotations.
    final currentSyncKey = await readSyncDatabaseKeyHex();
    if (currentSyncKey != newHexKey) {
      await _rotateSyncDatabaseKey(handle: handle, newKey: lskBytes);
    }
  } catch (e) {
    // Non-fatal: databases will retain their current keys. Rotation will be
    // retried on the next unlock when cacheRuntimeKeys is called again.
    debugPrint('[SYNC] Failed to rotate database keys to derived key: $e');
  }
}

/// Rotate the Rust sync database to [newKey] using the same staging protocol
/// as [rotateDatabaseToKey] for the Drift app database.
///
/// 1. Write staging slot — crash recovery on next startup if we die here or
///    between rekeyDb() and the primary-slot write.
/// 2. rekeyDb() — re-encrypts prism_sync.db in place.
/// 3. Write primary slot.
/// 4. Delete staging slot.
///
/// Crash recovery is handled in [PrismSyncHandleNotifier.createHandle] before
/// [ffi.createPrismSync] is called, mirroring the Drift recovery in
/// _openConnection() in database_provider.dart.
Future<void> _rotateSyncDatabaseKey({
  required ffi.PrismSyncHandle handle,
  required Uint8List newKey,
}) async {
  if (newKey.length != 32) {
    throw ArgumentError(
      '_rotateSyncDatabaseKey: key must be exactly 32 bytes, got ${newKey.length}',
    );
  }
  final newHexKey = newKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  // Write staging slot before rekeyDb — crash before rekeyDb means staging key
  // ≠ DB key, so createHandle discards the staging slot on next startup.
  await _storage.write(
    key: '${kSyncDatabaseKeyStorageKey}_staging',
    value: newHexKey,
  );
  await ffi.rekeyDb(handle: handle, newKey: newKey);
  await _storage.write(key: kSyncDatabaseKeyStorageKey, value: newHexKey);
  await _storage.delete(key: '${kSyncDatabaseKeyStorageKey}_staging');
  debugPrint('[SYNC] Rust sync DB rotated to HKDF-derived local storage key');
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
  for (final entry in entries.entries) {
    if (shouldAbort?.call() ?? false) return committedWrites;
    await writeKey('$_secureStorePrefix${entry.key}', entry.value);
    committedWrites++;
  }
  return committedWrites;
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
    deleteKey: (full) => _storage.delete(key: full),
    writeKey: (full, value) => _storage.write(key: full, value: value),
    shouldAbort: shouldAbort,
  );
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
      try {
        final result = await applyRemoteChanges(
          db,
          syncAdapter.adapter,
          event,
          strict: strict,
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
          rethrow;
        }
      }
      await syncAdapter.completeSyncBatch();
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

  bool get isStrict => _strict;

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

  /// Record a successful batch-complete. Idempotent — only the first signal
  /// wins. Called from the sync event stream once the RemoteChanges batch
  /// has applied and [SyncAdapterWithCompletion.completeSyncBatch] has run.
  void signalBatchComplete() {
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const ApplyOutcomeSuccess());
    }
  }
}

final strictApplyCoordinatorProvider = Provider<StrictApplyCoordinator>((ref) {
  return StrictApplyCoordinator();
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

          if (kDebugMode) {
            debugPrint(
              '[SYNC_APPLY] table=$table id=$entityId delete=$isDelete fields=${fields.keys.toList()}',
            );
          }

          if (isDelete) {
            await adapter.hardDelete(table, entityId);
          } else {
            await adapter.applyFields(table, entityId, fields);
          }
          rowsApplied++;
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

// ---------------------------------------------------------------------------
// Sync status
// ---------------------------------------------------------------------------

/// Whether sync is enabled (derived from handle availability — no race).
final syncEnabledProvider = Provider<bool>((ref) {
  final handle = ref.watch(prismSyncHandleProvider);
  return handle.value != null;
});

// ---------------------------------------------------------------------------
// Sync health
// ---------------------------------------------------------------------------

/// Tracks whether sync is healthy, needs user intervention, or is disconnected.
enum SyncHealthState {
  /// Sync is configured and working.
  healthy,

  /// Wrapped runtime cache is missing but wrapped_dek exists — user must
  /// enter password.
  needsPassword,

  /// Credentials are gone or device was revoked — must re-pair.
  disconnected,

  /// The device has never been paired. Behaves like healthy from the user's
  /// perspective (no password sheet, no reconnect card), but skips the
  /// post-config drain / cacheRuntimeKeys / scheduled onResume calls that
  /// would otherwise warn "no DEK loaded" on a locked handle.
  unpaired,
}

final syncHealthProvider =
    NotifierProvider<SyncHealthNotifier, SyncHealthState>(
      SyncHealthNotifier.new,
    );

/// Whether the sync password sheet is currently showing (duplicate guard).
final syncPasswordSheetVisibleProvider = NotifierProvider<_BoolNotifier, bool>(
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

class SyncHealthNotifier extends Notifier<SyncHealthState> {
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
      final wrappedDek = await _storage.read(
        key: '${_secureStorePrefix}wrapped_dek',
      );
      state = wrappedDek != null
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
    List<int>? secretKeyBytes;
    try {
      try {
        secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: normalized);
      } catch (_) {
        // Invalid mnemonic — treat as failed unlock without disclosing
        // which input was wrong.
        return false;
      }

      // Unlock the key hierarchy — throws on wrong PIN or mismatched mnemonic.
      try {
        await ffi.unlock(
          handle: handle,
          password: pin,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        // Wrong PIN or wrong mnemonic — don't change state; UI shows a
        // generic error and lets the user retry.
        return false;
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
      return true;
    } catch (_) {
      // Unexpected error (mnemonicToBytes, engine config, etc.)
      return false;
    } finally {
      // Always zero any secret-key bytes that made it into Dart memory.
      if (secretKeyBytes != null) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
      }
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

  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncAt,
    this.pendingOps = 0,
    this.lastError,
    this.hasQuarantinedItems = false,
  });

  SyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    int? pendingOps,
    String? lastError,
    bool? hasQuarantinedItems,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingOps: pendingOps ?? this.pendingOps,
      lastError: lastError,
      hasQuarantinedItems: hasQuarantinedItems ?? this.hasQuarantinedItems,
    );
  }
}

/// Whether the event-driven drain in `SyncStatusNotifier` should fire for
/// a `SyncCompleted` event with the given structured `errorKind`.
///
/// Returns `true` for success (`null`) and transient errors (`Network`,
/// `Server`, `Timeout`) so the secure-store stays in sync even when a
/// single cycle fails. Returns `false` for credential-state errors
/// (`Auth`, `KeyChanged`, `DeviceIdentityMismatch`) so the revoke cleanup
/// path can wipe credentials without the drain writing them back.
///
/// Pascal-case strings match the Rust `SyncErrorKind` Debug format emitted
/// by `sync_result_to_json` in `prism-sync-ffi/src/api.rs`.
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

/// Pure decision helper for the device_id self-check used by both
/// `_handleDeviceRevoked` and `_handleDeviceRevokedFromAuthFailure`.
///
/// Returns true if the revoke event should result in a credential wipe on
/// THIS device. Returns false only when the event explicitly carries a
/// non-empty device_id that differs from our own (sibling-revoke).
@visibleForTesting
bool shouldWipeForRevokeEvent({
  required String? revokedDeviceId,
  required String? currentDeviceId,
}) {
  if (revokedDeviceId == null || revokedDeviceId.isEmpty) {
    // Legacy / unknown — preserve existing behavior of wiping.
    return true;
  }
  if (currentDeviceId == null || currentDeviceId.isEmpty) {
    // We can't compare — assume self.
    return true;
  }
  return revokedDeviceId == currentDeviceId;
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

@visibleForTesting
SyncStatus syncStatusAfterCompleted({
  required SyncStatus previous,
  required String? rawResultError,
  required int pendingOps,
  required bool hasQuarantinedItems,
  DateTime? completedAt,
}) {
  final resultError = rawResultError != null && rawResultError.isNotEmpty
      ? rawResultError
      : null;
  return SyncStatus(
    isSyncing: false,
    lastSyncAt: resultError == null
        ? (completedAt ?? DateTime.now())
        : previous.lastSyncAt,
    pendingOps: pendingOps,
    hasQuarantinedItems: hasQuarantinedItems,
    lastError: resultError,
  );
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  Timer? _drainDebounce;

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
          final previous = state;
          // Re-query pending ops and quarantine state after sync completes.
          Future.wait([_queryPendingOps(), _queryQuarantine()]).then((results) {
            state = syncStatusAfterCompleted(
              previous: previous,
              rawResultError: structuredError?.userMessage ?? rawResultError,
              pendingOps: results[0] as int,
              hasQuarantinedItems: results[1] as bool,
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
          // Snapshot current pending ops count when sync begins so the UI
          // can show how many ops are waiting to be pushed.
          _queryPendingOps().then((count) {
            state = state.copyWith(isSyncing: true, pendingOps: count);
          });
        } else if (event.isError) {
          final structuredError =
              PrismSyncStructuredError.fromSyncEvent(event) ??
              PrismSyncStructuredError.tryParseMessage(
                event.data['message'] as String? ?? '',
              );
          final errorMessage = event.data['message'] as String? ?? '';
          state = state.copyWith(
            isSyncing: false,
            lastError: (structuredError?.userMessage ?? errorMessage).isNotEmpty
                ? (structuredError?.userMessage ?? errorMessage)
                : null,
          );
          if (structuredError?.isDeviceRevoked ?? false) {
            _handleDeviceRevokedFromAuthFailure(
              structuredError?.remoteWipe ?? false,
              revokedDeviceId: event.data['device_id'] as String?,
            );
          }
        } else if (event.isDeviceRevoked) {
          _handleDeviceRevoked(event);
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
      return await ref
          .read(syncQuarantineServiceProvider)
          .hasQuarantinedItems();
    } catch (_) {
      return false;
    }
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

    // Step 2 — determine whether this event targets us.
    String? currentDeviceId;
    try {
      final raw = await _storage.read(key: '${_secureStorePrefix}device_id');
      if (raw != null && raw.isNotEmpty) {
        try {
          currentDeviceId = utf8.decode(base64Decode(raw));
        } catch (_) {
          currentDeviceId = raw;
        }
      }
    } catch (_) {
      // If we can't read the device ID, assume we're the target.
    }

    if (revokedDeviceId != null &&
        currentDeviceId != null &&
        revokedDeviceId != currentDeviceId) {
      // Sibling revoke: our credentials are fine. The pending drain
      // was cancelled defensively by `_abortPendingDrainSafe`, but
      // `_credentialsRevoked` is NOT set and no re-cleanup was
      // scheduled, so new drains can still be scheduled normally and
      // THIS device's keychain stays intact.
      return;
    }

    // Step 3 — self-revoke (or device id unknown, assume self).
    // Escalate from safe-abort to the full revoke path: this sets the
    // suppression flag and schedules the post-revoke re-cleanup timer.
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

    // Step 2 — determine whether this event targets us. Mirror the same
    // device_id self-check that `_handleDeviceRevoked` performs. If the
    // event carries a device_id and it doesn't match our own, this is a
    // sibling-revoke and we leave THIS device's credentials alone.
    String? currentDeviceId;
    try {
      final raw = await _storage.read(key: '${_secureStorePrefix}device_id');
      if (raw != null && raw.isNotEmpty) {
        try {
          currentDeviceId = utf8.decode(base64Decode(raw));
        } catch (_) {
          currentDeviceId = raw;
        }
      }
    } catch (_) {
      // If we can't read the device ID, assume we're the target.
    }

    if (!shouldWipeForRevokeEvent(
      revokedDeviceId: revokedDeviceId,
      currentDeviceId: currentDeviceId,
    )) {
      debugPrint(
        '[SYNC] Auth-failure revoke targets sibling '
        '($revokedDeviceId != $currentDeviceId) — skipping wipe',
      );
      return;
    }

    // Step 3 — self-revoke (or device id unknown, assume self). Escalate
    // from safe-abort to the full revoke path.
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
  /// entry plus any dynamic `epoch_key_*` / `runtime_keys_*` entries.
  /// No state transitions, no provider invalidation, no UI side effects.
  /// Shared between `_clearSyncCredentials` (primary cleanup) and
  /// `_abortPendingDrainForRevoke`'s belt-and-suspenders post-revoke
  /// re-cleanup timer.
  Future<void> _wipeSyncKeychainEntries() async {
    for (final key in const [
      'wrapped_dek',
      'dek_salt',
      'device_secret',
      'device_id',
      'sync_id',
      'session_token',
      'epoch',
      'relay_url',
      'mnemonic',
      'setup_rollback_marker',
      'sharing_prekey_store',
      'sharing_id_cache',
      'min_signature_version_floor',
      'runtime_dek',
      'runtime_dek_wrapped_v1',
    ]) {
      try {
        await _storage.delete(key: '$_secureStorePrefix$key');
      } catch (_) {
        // Best effort — continue clearing remaining keys
      }
    }
    try {
      await _runtimeDekStore.deleteWrappingKey();
    } catch (_) {
      // Best effort — the wrapped blob was already deleted above.
    }
    // Dynamic-prefix scan — scan and delete any prefixed entries left
    // over from a previous pairing.
    try {
      final all = await _storage.readAll();
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_secureStorePrefix)) continue;
        final bare = entry.key.substring(_secureStorePrefix.length);
        if (_dynamicSecureStorePrefixes.any(bare.startsWith)) {
          try {
            await _storage.delete(key: entry.key);
          } catch (_) {}
        }
      }
    } catch (_) {
      // Non-fatal — the next reset will pick them up.
    }
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
  final value = await _storage.read(key: kSyncRelayUrlKey);
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
  final value = await _storage.read(key: kSyncIdKey);
  if (value == null || value.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(value));
  } catch (_) {
    return value; // Fallback: already plain text (legacy)
  }
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
