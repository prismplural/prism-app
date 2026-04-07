import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';

const _prismSyncStructuredErrorPrefix = 'PRISM_SYNC_ERROR_JSON:';

class PrismSyncStructuredError {
  const PrismSyncStructuredError({
    required this.message,
    this.operation,
    this.errorType,
    this.relayKind,
    this.code,
    this.status,
    this.remoteWipe,
  });

  final String message;
  final String? operation;
  final String? errorType;
  final String? relayKind;
  final String? code;
  final int? status;
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
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
    final databaseKeyHex = await ensureLocalDatabaseKey();
    final databaseKey = await ffi.hexDecode(hexStr: databaseKeyHex);
    final handle = await ffi.createPrismSync(
      relayUrl: relayUrl,
      dbPath: dbPath,
      allowInsecure: false,
      schemaJson: prismSyncSchema,
      databaseKey: databaseKey,
    );

    // Seed Rust's in-memory SecureStore from platform keychain
    await _seedRustStore(handle);

    // Publish the handle before auto-configuring. Startup auto-sync can emit
    // RemoteChanges almost immediately after configureEngine/setAutoSync, and
    // those changes must not beat Dart's event-stream subscription.
    _handle = handle;
    state = AsyncData(handle);

    // Auto-configure sync engine if credentials already exist (app restart)
    final health = await _autoConfigureIfReady(handle);
    ref.read(syncHealthProvider.notifier).setState(health);

    // Persist any Rust state changes from configureEngine (prevents credential
    // loss if the app crashes before an explicit drain happens).
    if (health == SyncHealthState.healthy) {
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
    }

    return handle;
  }
}

// ---------------------------------------------------------------------------
// Auto-configure on restart
// ---------------------------------------------------------------------------

/// Determine sync health and auto-configure if possible.
///
/// Returns [SyncHealthState.healthy] if sync is configured (or not paired).
/// Returns [SyncHealthState.needsPassword] if runtime_dek is missing but
/// other credentials exist (user must enter password once).
/// Returns [SyncHealthState.disconnected] if credentials are gone.
Future<SyncHealthState> _autoConfigureIfReady(
  ffi.PrismSyncHandle handle,
) async {
  // Check if we have the minimum credentials needed
  final syncId = await _storage.read(key: '${_secureStorePrefix}sync_id');
  final deviceId = await _storage.read(key: '${_secureStorePrefix}device_id');
  if (syncId == null || deviceId == null) {
    return SyncHealthState.healthy; // Not paired — not an error
  }

  // Try the fast path: restore runtime keys from cached DEK
  final isUnlocked = await ffi.isUnlocked(handle: handle);
  if (!isUnlocked) {
    final dekB64 = await _storage.read(key: kRuntimeDekKey);
    final deviceSecretB64 = await _storage.read(
      key: '${_secureStorePrefix}device_secret',
    );

    if (dekB64 != null && deviceSecretB64 != null) {
      try {
        await ffi.restoreRuntimeKeys(
          handle: handle,
          dek: base64Decode(dekB64),
          deviceSecret: base64Decode(deviceSecretB64),
        );
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'restoreRuntimeKeys failed: $e',
          severity: ErrorSeverity.error,
          stackTrace: st,
        );
        return SyncHealthState.disconnected;
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

    // Safety-net backfill: derive and cache the DB key from sync state if
    // the keychain slot is empty. With always-on encryption (Signal model),
    // ensureLocalDatabaseKey() populates this slot at first launch, so this
    // guard is normally a no-op. It remains as defense-in-depth for edge
    // cases (e.g. upgrade from a very old version).
    //
    // CROSS-FILE INVARIANT: The `existingDbKey == null` check is critical.
    // ensureLocalDatabaseKey() in database_encryption.dart may have already
    // written a local CSPRNG key. This guard must NOT overwrite it — doing
    // so would make the encrypted database unreadable.
    try {
      final existingDbKey = await readDatabaseKeyHex();
      if (existingDbKey == null) {
        final dbKeyBytes = await ffi.databaseKey(handle: handle);
        await cacheDatabaseKey(dbKeyBytes);
        debugPrint('[SYNC] Backfilled database encryption key');
      }
    } catch (e) {
      debugPrint('[SYNC] Failed to backfill database key (non-fatal): $e');
    }

    // Pull any batches that accumulated while this device was offline. This
    // is especially important on cold start because a reconnect alone only
    // restores the WebSocket; it does not guarantee a catch-up pull.
    try {
      await ffi.onResume(handle: handle);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Startup catch-up sync failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

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

/// Keys that prism-sync stores in SecureStore.
const _secureStoreKeys = [
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
];

/// Key for persisting the raw DEK in the platform keychain (Signal-style).
/// Stored after first unlock so subsequent launches bypass Argon2id.
const kRuntimeDekKey = '${_secureStorePrefix}runtime_dek';

const _storage = secureStorage;

/// Seed the Rust-side MemorySecureStore with values from platform keychain.
Future<void> _seedRustStore(ffi.PrismSyncHandle handle) async {
  final entries = <String, String>{};
  for (final key in _secureStoreKeys) {
    final value = await _storage.read(key: '$_secureStorePrefix$key');
    if (value != null) {
      entries[key] = value; // Already base64-encoded
    }
  }
  if (entries.isNotEmpty) {
    await ffi.seedSecureStore(handle: handle, entriesJson: jsonEncode(entries));
  }
}

/// Export the raw DEK from Rust and cache it in the platform keychain.
///
/// Call after `initialize()`, `unlock()`, or `joinFromUrl()` — any operation
/// that leaves the key hierarchy unlocked. On subsequent app launches,
/// `_autoConfigureIfReady` uses this cached DEK to restore the unlocked
/// state without re-deriving via Argon2id.
///
/// Also derives and caches the database encryption key so the next app
/// startup can open the database encrypted.
Future<void> cacheRuntimeKeys(ffi.PrismSyncHandle handle) async {
  final dekBytes = await ffi.exportDek(handle: handle);
  final dekB64 = base64Encode(dekBytes);
  await _storage.write(key: kRuntimeDekKey, value: dekB64);

  // Safety-net backfill: derive and cache the DB key from sync state if
  // the keychain slot is empty. With always-on encryption (Signal model),
  // ensureLocalDatabaseKey() populates this slot at first launch, so this
  // is normally a no-op.
  //
  // CROSS-FILE INVARIANT: The `existingKey == null` check must be preserved.
  // ensureLocalDatabaseKey() in database_encryption.dart writes a local
  // CSPRNG key at first launch. Overwriting it here would make the local
  // encrypted database unreadable.
  try {
    final existingKey = await readDatabaseKeyHex();
    if (existingKey == null) {
      final dbKeyBytes = await ffi.databaseKey(handle: handle);
      await cacheDatabaseKey(dbKeyBytes);
    }
  } catch (e) {
    // Non-fatal: database encryption will be attempted on next startup
    // when the DEK is available to re-derive the key.
    debugPrint('[SYNC] Failed to cache database key: $e');
  }
}

/// Drain the Rust-side MemorySecureStore back to platform keychain.
/// Call after state-changing operations (initialize, createSyncGroup, join, etc).
Future<void> drainRustStore(ffi.PrismSyncHandle handle) async {
  final json = await ffi.drainSecureStore(handle: handle);
  final entries = Map<String, String>.from(jsonDecode(json) as Map);
  for (final entry in entries.entries) {
    await _storage.write(
      key: '$_secureStorePrefix${entry.key}',
      value: entry.value,
    );
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
  return buildSyncAdapterWithCompletion(db, quarantine: quarantine);
});

// ---------------------------------------------------------------------------
// Sync event stream
// ---------------------------------------------------------------------------

final syncEventStreamProvider = StreamProvider<SyncEvent>((ref) {
  final handle = ref.watch(prismSyncHandleProvider).value;
  if (handle == null) return const Stream.empty();

  final syncAdapter = ref.watch(driftSyncAdapterProvider);
  final db = ref.watch(databaseProvider);

  return createSyncEventStream(handle).asyncMap((event) async {
    if (kDebugMode) {
      print(
        '[SYNC_STREAM] Event type=${event.type}, changes=${event.changes.length}',
      );
    }
    if (event.isRemoteChanges) {
      await _applyRemoteChanges(db, syncAdapter.adapter, event);
      await syncAdapter.completeSyncBatch();
      if (kDebugMode) {
        print('[SYNC_STREAM] Applied ${event.changes.length} remote changes');
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

Future<void> _applyRemoteChanges(
  AppDatabase db,
  DriftSyncAdapter adapter,
  SyncEvent event,
) async {
  // Apply changes in chunked transactions — each chunk of 20 changes runs
  // inside a single Drift transaction for fewer WAL commits, while per-row
  // try/catch keeps error handling granular (caught exceptions do NOT trigger
  // Drift transaction rollback).
  const chunkSize = 20;
  final changes = event.changes;

  for (var offset = 0; offset < changes.length; offset += chunkSize) {
    final end = min(offset + chunkSize, changes.length);
    final chunk = changes.sublist(offset, end);

    await db.transaction(() async {
      for (final change in chunk) {
        try {
          final table = change['table'] as String;
          final entityId = change['entity_id'] as String;
          final isDelete = change['is_delete'] as bool? ?? false;
          final fields = (change['fields'] as Map<String, dynamic>?) ?? {};

          if (kDebugMode) {
            print(
              '[SYNC_APPLY] table=$table id=$entityId delete=$isDelete fields=${fields.keys.toList()}',
            );
          }

          if (isDelete) {
            await adapter.hardDelete(table, entityId);
          } else {
            await adapter.applyFields(table, entityId, fields);
          }
        } catch (e, st) {
          final table = change['table'];
          final entityId = change['entity_id'];
          final fieldKeys = (change['fields'] as Map?)?.keys.toList() ?? [];
          ErrorReportingService.instance.report(
            'Sync apply failed for $table/$entityId: $e '
            '(fields: $fieldKeys)',
            severity: ErrorSeverity.warning,
            stackTrace: st,
          );
          // Continue processing remaining changes — skip bad rows, apply good ones
        }
      }
    });
  }
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
  /// Sync is configured and working (or not paired at all).
  healthy,

  /// runtime_dek is missing but wrapped_dek exists — user must enter password.
  needsPassword,

  /// Credentials are gone or device was revoked — must re-pair.
  disconnected,
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

  /// Attempt to unlock the key hierarchy with the user's password.
  ///
  /// Returns true on success (state transitions to healthy).
  /// Returns false on failure (wrong password or missing handle).
  Future<bool> attemptUnlock(String password) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return false;

    try {
      // Read mnemonic from keychain and decode
      final mnemonicB64 = await _storage.read(
        key: '${_secureStorePrefix}mnemonic',
      );
      if (mnemonicB64 == null) {
        state = SyncHealthState.disconnected;
        return false;
      }
      String mnemonic;
      try {
        mnemonic = utf8.decode(base64Decode(mnemonicB64));
      } catch (_) {
        mnemonic = mnemonicB64;
      }
      final secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);

      // Unlock the key hierarchy — throws on wrong password
      try {
        await ffi.unlock(
          handle: handle,
          password: password,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        // Wrong password — don't change state, let UI show error and retry
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
      await cacheRuntimeKeys(handle);

      state = SyncHealthState.healthy;
      return true;
    } catch (_) {
      // Unexpected error (keychain read, mnemonicToBytes, etc.)
      return false;
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
  @override
  SyncStatus build() {
    ref.listen(syncEventStreamProvider, (prev, next) {
      next.whenData((event) {
        if (event.isSyncCompleted) {
          final rawResultError =
              (event.data['result'] as Map<String, dynamic>?)?['error']
                  as String?;
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
          if (structuredError?.isDeviceRevoked ?? false) {
            _handleDeviceRevokedFromAuthFailure(
              structuredError?.remoteWipe ?? false,
            );
          }
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
            );
          }
        } else if (event.isDeviceRevoked) {
          _handleDeviceRevoked(event);
        }
      });
    });
    return const SyncStatus();
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

  /// Handle a DeviceRevoked event for the current device.
  ///
  /// Always clears sync credentials and stops auto-sync so the revoked device
  /// does not keep trying to sync in the background. If [remoteWipe] is true,
  /// also deletes the sync database file.
  Future<void> _handleDeviceRevoked(SyncEvent event) async {
    final revokedDeviceId = event.data['device_id'] as String?;
    final wipe = event.remoteWipe;

    // Read current device ID to check if this revocation targets us.
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
      // If we can't read the device ID, assume we're the target
    }

    // Only act if this device was revoked (or we can't determine)
    if (revokedDeviceId != null &&
        currentDeviceId != null &&
        revokedDeviceId != currentDeviceId) {
      // Another device was revoked, not us — just update state normally
      return;
    }

    // Stop auto-sync to prevent background retry loops
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

    // If remote wipe was requested, delete the sync database
    if (wipe) {
      await _wipeSyncDatabase();
    }

    // Clear sync credentials from keychain
    await _clearSyncCredentials();

    ref
        .read(syncHealthProvider.notifier)
        .setState(SyncHealthState.disconnected);
  }

  Future<void> _handleDeviceRevokedFromAuthFailure(bool remoteWipe) async {
    try {
      if (remoteWipe) {
        debugPrint('[SYNC] Device flagged for remote wipe — wiping sync data');
        await _wipeSyncDatabase();
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

  /// Delete the sync database file and its WAL/SHM companions.
  Future<void> _wipeSyncDatabase() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
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
  }

  /// Clear all sync credentials from the platform keychain.
  Future<void> _clearSyncCredentials() async {
    for (final key in [
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
      'runtime_dek',
    ]) {
      try {
        await _storage.delete(key: '$_secureStorePrefix$key');
      } catch (_) {
        // Best effort — continue clearing remaining keys
      }
    }
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
Future<void> triggerSync(ffi.PrismSyncHandle handle) async {
  // Best-effort WebSocket reconnect (non-fatal if it fails).
  try {
    await ffi.reconnectWebsocket(handle: handle);
  } catch (_) {}
  await ffi.syncNow(handle: handle);
}
