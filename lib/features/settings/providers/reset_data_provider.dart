import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/biometric_service_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/reset/native_reset_keys.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/relay_cleanup.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_file_import_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:prism_plurality/features/migration/services/group_chat_visibility_sync_reemit_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Re-export so tests in `test/features/settings/providers/` can import
/// `kProtectedFromReset` from this file (avoids a hand-copied list of
/// names in tests). Source of truth lives in `prism_sync_providers.dart`
/// alongside the other secure-store constants.
export 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show kProtectedFromReset;

abstract class ResetSecureStore implements FullResetSecureStore {
  Future<String?> read(String key);
  @override
  Future<void> delete(String key);

  /// Read every key/value pair currently in the secure store. Used to
  /// scan for dynamic `prism_sync.epoch_key_*` / `prism_sync.runtime_keys_*`
  /// entries on reset/revoke cleanup.
  @override
  Future<Map<String, String>> readAll();

  /// Wipe every key in the store. Used by full reset only — never by sync-only
  /// reset, which must preserve `database_key` so the app DB stays openable.
  @override
  Future<void> deleteAll();
}

class _PlatformResetSecureStore implements ResetSecureStore {
  const _PlatformResetSecureStore();

  /// Each operation routes through the classified secure-storage wrappers
  /// so a PlatformException during reset (e.g. cipher failure on `readAll`)
  /// surfaces as null/empty rather than escaping into the reset flow's
  /// caller. The reset-path callers already treat read/delete failures as
  /// non-fatal (best-effort cleanup); this just makes the failure mode
  /// classified instead of raw.
  @override
  Future<String?> read(String key) async => (await safeSecureRead(key)).value;

  @override
  Future<void> delete(String key) async {
    await safeSecureDelete(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    final result = await safeSecureReadAll();
    return result.entries;
  }

  @override
  Future<void> deleteAll() async {
    await safeSecureDeleteAll();
  }
}

final resetSecureStoreProvider = Provider<ResetSecureStore>((ref) {
  return const _PlatformResetSecureStore();
});

final resetNativeKeysProvider = Provider<NativeResetKeys>((ref) {
  return const MethodChannelNativeResetKeys();
});

final resetIsAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);

final resetRequiresRestartAfterLocalPairingWipeProvider = Provider<bool>(
  (ref) => Platform.isIOS,
);

final resetDocumentsDirectoryProvider = FutureProvider<Directory>((ref) async {
  return getAppDataDir();
});

final resetTemporaryDirectoryProvider = FutureProvider<Directory>((ref) async {
  return getTemporaryDirectory();
});

final resetSyncHandleProvider = Provider<ffi.PrismSyncHandle?>((ref) {
  return ref.watch(prismSyncHandleProvider).value;
});

/// Thin FFI surface used by `_resetSyncSystem`.
///
/// Extracted so tests can inject a recording fake and assert call ordering
/// (e.g. `setAutoSync(false)` must run before any other side-effect, dispose
/// must run before the sync-DB file is deleted). Production code uses
/// [_DefaultResetSyncFfi] which forwards to the real prism_sync bindings.
abstract class ResetSyncFfi {
  Future<void> setAutoSync({
    required ffi.PrismSyncHandle handle,
    required bool enabled,
    required BigInt debounceMs,
    required BigInt retryDelayMs,
    required int maxRetries,
  });

  Future<void> deregisterDevice({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  });

  Future<void> deleteSyncGroup({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  });

  Future<void> clearSyncState({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required bool forceActive,
  });

  /// Calls `dispose()` on the handle. Wrapped so tests can observe ordering.
  void disposeHandle(ffi.PrismSyncHandle handle);
}

class _DefaultResetSyncFfi implements ResetSyncFfi {
  const _DefaultResetSyncFfi();

  @override
  Future<void> setAutoSync({
    required ffi.PrismSyncHandle handle,
    required bool enabled,
    required BigInt debounceMs,
    required BigInt retryDelayMs,
    required int maxRetries,
  }) {
    return ffi.setAutoSync(
      handle: handle,
      enabled: enabled,
      debounceMs: debounceMs,
      retryDelayMs: retryDelayMs,
      maxRetries: maxRetries,
    );
  }

  @override
  Future<void> deregisterDevice({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  }) {
    return ffi.deregisterDevice(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
    );
  }

  @override
  Future<void> deleteSyncGroup({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  }) {
    return ffi.deleteSyncGroup(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
    );
  }

  @override
  Future<void> clearSyncState({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required bool forceActive,
  }) {
    return ffi.clearSyncState(
      handle: handle,
      syncId: syncId,
      forceActive: forceActive,
    );
  }

  @override
  void disposeHandle(ffi.PrismSyncHandle handle) {
    handle.dispose();
  }
}

final resetSyncFfiProvider = Provider<ResetSyncFfi>((ref) {
  return const _DefaultResetSyncFfi();
});

/// Hook for tests to observe the moment `_resetSyncSystem` deletes the
/// Rust sync-DB file. Default is a no-op; tests override with a recorder
/// to assert dispose-before-delete ordering.
typedef ResetFileDeleteObserver = void Function(String path);

final resetFileDeleteObserverProvider = Provider<ResetFileDeleteObserver>((
  ref,
) {
  return (_) {};
});

final fullResetServiceProvider = Provider<FullResetService>((ref) {
  return FullResetService(
    secureStore: ref.watch(resetSecureStoreProvider),
    nativeResetKeys: ref.watch(resetNativeKeysProvider),
    appDataDirectory: () => ref.read(resetDocumentsDirectoryProvider.future),
    temporaryDirectory: () => ref.read(resetTemporaryDirectoryProvider.future),
    clearMediaCache: () => ref.read(downloadManagerProvider).clearCache(),
    fileObserver: ref.watch(resetFileDeleteObserverProvider),
    log: (message) {
      ErrorReportingService.instance.report(
        message,
        severity: ErrorSeverity.info,
      );
    },
  );
});

/// Enum for reset categories shown in the UI.
enum ResetCategory {
  members(
    'Members',
    'Removes all members. Fronting sessions will show as unknown.',
  ),
  fronting('Fronting Sessions', 'Deletes all fronting history.'),
  chat('Chat', 'Deletes all conversations and messages.'),
  polls('Polls', 'Deletes all polls, options, and votes.'),
  habits('Habits', 'Deletes all habits and completion records.'),
  sleep('Sleep Sessions', 'Deletes all sleep tracking data.'),
  sync(
    'Disconnect Sync',
    'Stops syncing on this device while keeping local Prism data.',
  ),
  all('All Data', 'Permanently deletes everything and resets the app.');

  const ResetCategory(this.label, this.description);
  final String label;
  final String description;
}

class ResetDataNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  void _log(String message) {
    ErrorReportingService.instance.report(
      message,
      severity: ErrorSeverity.info,
    );
  }

  void _notifyTableChanges(Iterable<String> tableNames) {
    final db = ref.read(databaseProvider);
    final updates = {
      for (final tableName in tableNames)
        if (tableName.isNotEmpty) TableUpdate(tableName),
    };
    if (updates.isEmpty) {
      return;
    }
    db.notifyUpdates(updates);
  }

  Future<void> _clearSyncOneTimeFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sync.enum_fields_reemit_v1');
      await prefs.remove(GroupChatVisibilitySyncReemitService.flagKey);
      await prefs.remove(PkGroupSyncV2CatchupService.flagKey);
      await prefs.remove(PkGroupRepairRunGate.checkedVersionKey);
      await prefs.remove(PkGroupRepairRunGate.checkedAtKey);
      await prefs.remove(PkGroupRepairRunGate.dirtyKey);
    } catch (e) {
      _log('SharedPreferences reset failed (non-fatal): $e');
    }
  }

  Future<void> _clearFullResetFlowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(spImportCompletedPreferenceKey);
    } catch (e) {
      _log('SharedPreferences full-reset cleanup failed (non-fatal): $e');
    }

    try {
      ref.read(importerProvider.notifier).reset();
    } catch (e) {
      _log('SP importer state reset failed (non-fatal): $e');
    }
    try {
      ref.read(pkFileImportProvider.notifier).reset();
    } catch (e) {
      _log('PK file import state reset failed (non-fatal): $e');
    }
    try {
      ref.read(onboardingPendingImportActionProvider.notifier).set(null);
    } catch (e) {
      _log('Onboarding pending import state reset failed (non-fatal): $e');
    }

    ref.invalidate(importerProvider);
    ref.invalidate(hasPreviousSpImportProvider);
    ref.invalidate(pkFileImportProvider);
    ref.invalidate(onboardingPendingImportActionProvider);
    ref.invalidate(onboardingProvider);
  }

  Future<String?> _readDecodedSecureValue(String key) async {
    final encoded = await ref.read(resetSecureStoreProvider).read(key);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return encoded;
    }
  }

  Future<_SyncIdentitySnapshot> _snapshotSyncIdentity(String prefix) async {
    return _SyncIdentitySnapshot(
      syncId: await _readDecodedSecureValue('${prefix}sync_id'),
      deviceId: await _readDecodedSecureValue('${prefix}device_id'),
      sessionToken: await _readDecodedSecureValue('${prefix}session_token'),
      relayUrl: await _readDecodedSecureValue('${prefix}relay_url'),
    );
  }

  /// Reset a specific category of data.
  Future<void> reset(ResetCategory category) async {
    final result = await AsyncValue.guard(() async {
      switch (category) {
        case ResetCategory.members:
          await _resetMembers();
        case ResetCategory.fronting:
          await _resetFronting();
        case ResetCategory.chat:
          await _resetChat();
        case ResetCategory.polls:
          await _resetPolls();
        case ResetCategory.habits:
          await _resetHabits();
        case ResetCategory.sleep:
          await _resetSleep();
        case ResetCategory.sync:
          await _resetSyncSystem(
            reason: SyncDisconnectReason.userDisconnect,
            cleanupPolicy: SyncRelayCleanupPolicy.conservative,
            localAppDataOutcome: LocalAppDataOutcome.preserved,
            nextSetupConstraint: SyncSetupConstraint.localOnly,
          );
        case ResetCategory.all:
          await _resetAll();
      }
    });
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> replaceLocalDataAndPrepareForPairing() async {
    final result = await AsyncValue.guard(() async {
      await _resetSyncSystem(
        reason: SyncDisconnectReason.replaceByPairing,
        cleanupPolicy: SyncRelayCleanupPolicy.conservative,
        localAppDataOutcome: LocalAppDataOutcome.preserved,
        nextSetupConstraint: SyncSetupConstraint.localOnly,
      );
      await _clearFullResetFlowState();
      await _wipeLocalDataAfterSyncTeardown(
        requireRestart: ref.read(
          resetRequiresRestartAfterLocalPairingWipeProvider,
        ),
        completionLog: 'Prepared device for sync pairing after local wipe',
      );
      await _markReplacePairingLocalWipeCompleted();
    });
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> _resetMembers() async {
    final db = ref.read(databaseProvider);
    _log('Resetting members');
    await db.transaction(() async {
      await db
          .into(db.members)
          .insert(
            MembersCompanion(
              id: Value(unknownSentinelMemberId),
              name: const Value('Unknown'),
              emoji: const Value('❔'),
              createdAt: Value(DateTime.now().toUtc()),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      // Preserve fronting history by attributing normal rows to the
      // system-managed Unknown sentinel. Normal fronting rows cannot use null
      // because the per-member schema enforces member_id for session_type = 0.
      await db.customStatement(
        'UPDATE fronting_sessions SET member_id = ? WHERE session_type = 0',
        [unknownSentinelMemberId],
      );
      // Scalar member references: null out so the rows survive (these features
      // don't require a member to be valid) but stop pointing at deleted ones.
      await db.customStatement(
        'UPDATE chat_messages SET author_id = NULL, reply_to_author_id = NULL',
      );
      await db.customStatement(
        'UPDATE conversations SET creator_id = NULL',
      );
      await db.customStatement(
        "UPDATE conversations SET participant_ids = '[]', "
        "archived_by_member_ids = '[]', muted_by_member_ids = '[]', "
        "last_read_timestamps = '{}'",
      );
      await db.customStatement('UPDATE habits SET assigned_member_id = NULL');
      await db.customStatement(
        'UPDATE pk_mapping_state SET local_member_id = NULL',
      );
      await db.customStatement(
        'UPDATE reminders SET target_member_id = NULL',
      );
      // JSON maps keyed by memberId — reset to defaults so stale keys don't
      // hang around. chat_badge_preferences defaults to '{}'; field_sync_config
      // is nullable.
      await db.customStatement(
        "UPDATE system_settings SET chat_badge_preferences = '{}'",
      );
      await db.customStatement(
        'UPDATE plural_kit_sync_state SET field_sync_config = NULL',
      );
      // Delete child data that references members
      await db.customStatement('DELETE FROM custom_field_values');
      await db.customStatement('DELETE FROM habit_completions');
      await db.customStatement('DELETE FROM member_board_posts');
      await db.customStatement('DELETE FROM member_group_entries');
      await db.customStatement(
        'DELETE FROM member_profile_preference_values',
      );
      await db.customStatement('DELETE FROM notes');
      await db.customStatement('DELETE FROM poll_votes');
      // Delete user members; keep the system-managed Unknown sentinel because
      // fronting history now points to it and member-management UI filters it.
      await db.customStatement('DELETE FROM members WHERE id <> ?', [
        unknownSentinelMemberId,
      ]);
    });
    _notifyTableChanges([
      'chat_messages',
      'conversations',
      'custom_field_values',
      'fronting_sessions',
      'habit_completions',
      'habits',
      'member_board_posts',
      'member_group_entries',
      'member_profile_preference_values',
      'members',
      'notes',
      'pk_mapping_state',
      'plural_kit_sync_state',
      'poll_votes',
      'reminders',
      'system_settings',
    ]);
  }

  Future<void> _resetFronting() async {
    final db = ref.read(databaseProvider);
    _log('Resetting fronting sessions');
    await db.transaction(() async {
      await db.customStatement('''
        DELETE FROM front_session_comments
        WHERE session_id IN (
          SELECT id FROM fronting_sessions WHERE session_type = 0
        )
      ''');
      await db.customStatement(
        'DELETE FROM fronting_sessions WHERE session_type = 0',
      );
    });
    _notifyTableChanges(['front_session_comments', 'fronting_sessions']);
  }

  Future<void> _resetChat() async {
    final db = ref.read(databaseProvider);
    _log('Resetting chat data');

    // Collect media_id values before the transaction so we can delete the
    // on-disk encrypted files after the DB rows are gone.
    final mediaIds = await db
        .customSelect('SELECT media_id FROM media_attachments')
        .get()
        .then((rows) => rows.map((r) => r.read<String>('media_id')).toList());

    await db.transaction(() async {
      // FTS first — the chat_messages_fts_delete trigger does a full FTS
      // table scan per deleted row. Wiping FTS up front makes the trigger
      // a no-op and turns a minutes-long delete into milliseconds on large
      // chat histories.
      await db.customStatement('DELETE FROM chat_messages_fts');
      await db.customStatement('DELETE FROM chat_messages');
      await db.customStatement('DELETE FROM conversation_categories');
      await db.customStatement('DELETE FROM conversations');
      await db.customStatement('DELETE FROM media_attachments');
    });
    _notifyTableChanges([
      'chat_messages',
      'conversation_categories',
      'conversations',
      'media_attachments',
    ]);

    // Delete orphaned on-disk encrypted media files. Best-effort: log failures,
    // never throw (matches _deleteFileIfExists posture in full_reset_service).
    if (mediaIds.isNotEmpty) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        final mediaDir = p.join(supportDir.path, 'prism_media');
        for (final mediaId in mediaIds) {
          if (mediaId.isEmpty) continue;
          final file = File(p.join(mediaDir, '$mediaId.enc'));
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            _log('Failed to delete orphaned media file $mediaId.enc: $e');
          }
        }
      } catch (e) {
        _log('Failed to resolve media directory during chat reset: $e');
      }
    }
  }

  Future<void> _resetPolls() async {
    final db = ref.read(databaseProvider);
    _log('Resetting poll data');
    await db.transaction(() async {
      await db.customStatement('DELETE FROM poll_votes');
      await db.customStatement('DELETE FROM poll_options');
      await db.customStatement('DELETE FROM polls');
    });
    _notifyTableChanges(['poll_votes', 'poll_options', 'polls']);
  }

  Future<void> _resetHabits() async {
    final db = ref.read(databaseProvider);
    _log('Resetting habit data');
    await db.transaction(() async {
      await db.customStatement('DELETE FROM habit_completions');
      await db.customStatement('DELETE FROM habits');
    });
    _notifyTableChanges(['habit_completions', 'habits']);
  }

  Future<void> _resetSleep() async {
    final db = ref.read(databaseProvider);
    _log('Resetting sleep sessions');
    await db.transaction(() async {
      await db.customStatement('DELETE FROM sleep_sessions');
      await db.customStatement('''
        DELETE FROM front_session_comments
        WHERE session_id IN (
          SELECT id FROM fronting_sessions WHERE session_type = 1
        )
      ''');
      await db.customStatement(
        'DELETE FROM fronting_sessions WHERE session_type = 1',
      );
    });
    _notifyTableChanges([
      'sleep_sessions',
      'front_session_comments',
      'fronting_sessions',
    ]);
  }

  Future<void> _resetSyncSystem({
    required SyncDisconnectReason reason,
    required SyncRelayCleanupPolicy cleanupPolicy,
    required LocalAppDataOutcome localAppDataOutcome,
    required SyncSetupConstraint nextSetupConstraint,
  }) async {
    _log('Resetting sync system');
    const prefix = 'prism_sync.';

    final handle = ref.read(resetSyncHandleProvider);
    final syncFfi = ref.read(resetSyncFfiProvider);
    final markerStore = ref.read(syncDisconnectMarkerStoreProvider);

    // Stop any queued event-driven keychain drain before deleting credentials.
    // Otherwise a SyncCompleted drain that was scheduled just before reset
    // could write old Rust MemorySecureStore entries back after this path
    // clears the platform keychain.
    try {
      ref.read(syncStatusProvider.notifier).prepareForCredentialReset();
    } catch (e) {
      _log('Failed to prepare sync-status reset barrier (non-fatal): $e');
    }

    // 0. Disable auto-sync as the first FFI call — silences the debounce
    //    timer, the notification handler, and the WebSocket reconnect loop
    //    so they don't race the rest of the teardown (Phase 2A). Non-fatal:
    //    if setAutoSync throws (handle already torn down, FFI panic), keep
    //    going — the dispose() in step 4 will stop everything anyway.
    if (handle != null) {
      try {
        await syncFfi.setAutoSync(
          handle: handle,
          enabled: false,
          debounceMs: BigInt.zero,
          retryDelayMs: BigInt.zero,
          maxRetries: 0,
        );
      } catch (e) {
        _log('Failed to disable auto-sync before reset (non-fatal): $e');
      }
    }

    final identity = await _snapshotSyncIdentity(prefix);
    SyncDisconnectMarker? marker;
    try {
      marker = await markerStore.writeInitial(
        reason: reason,
        previousSyncId: identity.syncId,
        previousDeviceId: identity.deviceId,
        relayUrl: identity.relayUrl,
        localAppDataOutcome: localAppDataOutcome,
        nextSetupConstraint: nextSetupConstraint,
      );
      ref.invalidate(syncDisconnectMarkerProvider);
    } catch (e) {
      _log('Sync disconnect marker write failed (non-fatal): $e');
    }

    var relayCleanupOutcome = handle == null
        ? RelayCleanupMarkerOutcome.skippedNoHandle
        : RelayCleanupMarkerOutcome.skippedMissingCredentials;

    // 1. Try to deregister from relay (best-effort — may fail if offline).
    //    If this is the last active device the relay rejects deregister with a
    //    403 and tells us to delete the sync group instead — fall through to
    //    `deleteSyncGroup` via the shared helper so the relay drops all
    //    encrypted data. User-facing disconnect keeps the conservative
    //    fallback policy; full app reset opts into the aggressive fallback.
    if (handle != null) {
      try {
        final syncId = identity.syncId;
        final deviceId = identity.deviceId;
        final sessionToken = identity.sessionToken;
        if (syncId != null && deviceId != null && sessionToken != null) {
          final outcome = await cleanupRelayRegistration(
            handle: handle,
            syncId: syncId,
            deviceId: deviceId,
            sessionToken: sessionToken,
            deregister: syncFfi.deregisterDevice,
            deleteSyncGroup: syncFfi.deleteSyncGroup,
            log: _log,
            fallbackOnAnyDeregisterFailure:
                cleanupPolicy == SyncRelayCleanupPolicy.aggressive,
          );
          relayCleanupOutcome = _markerOutcomeForRelayCleanup(outcome);
        }
      } catch (e) {
        _log('Relay cleanup failed (non-fatal): $e');
        relayCleanupOutcome = RelayCleanupMarkerOutcome.failed;
      }
    }

    // 2. Clear active sync-DB rows while the handle is still live. This is a
    //    belt-and-suspenders cleanup before file deletion: if the later unlink
    //    fails, rows for the abandoned sync_id are still gone. Non-fatal:
    //    file deletion remains the fallback cleanup path.
    if (handle != null) {
      try {
        final syncId = await _readDecodedSecureValue('${prefix}sync_id');
        if (syncId != null) {
          await syncFfi.clearSyncState(
            handle: handle,
            syncId: syncId,
            forceActive: true,
          );
        }
      } catch (e) {
        _log('clear_sync_state failed during reset (non-fatal): $e');
      }
    }

    // 3. Dispose the FFI handle BEFORE deleting the sync-DB file. Dropping
    //    the Arc<Mutex<PrismSync>> releases SQLite connections + WebSocket
    //    handles synchronously, so the subsequent unlink doesn't race a
    //    live writer (Phase 2B-1). The ref.onDispose callback in
    //    PrismSyncHandleNotifier.build() also calls dispose(), but doing it
    //    explicitly here orders it relative to the file delete instead of
    //    relative to GC.
    if (handle != null) {
      syncFfi.disposeHandle(handle);
    }

    // 4. Delete the Rust sync database files.
    try {
      final dir = await ref.read(resetDocumentsDirectoryProvider.future);
      final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
      final observer = ref.read(resetFileDeleteObserverProvider);
      final file = File(dbPath);
      if (await file.exists()) {
        observer(dbPath);
        await file.delete();
      }
      // Also delete WAL/SHM files
      final wal = File('$dbPath-wal');
      final shm = File('$dbPath-shm');
      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
    } catch (e) {
      _log('DB file delete failed (non-fatal): $e');
    }

    // 5. Wipe the prism_sync.* keychain namespace via the shared helper.
    //    `wipeSyncKeychainNamespace` runs the same prefix-scan-with-fallback
    //    cleanup used by pairing-failure recovery, plus the AndroidKeystore-
    //    backed runtime DEK wrapping key (reset only). Centralising this
    //    keeps reset and `_cleanupKeychainOnFailure` in lockstep so a new
    //    transient `prism_sync.*` key gets wiped by both paths automatically.
    //    See `kProtectedFromReset` for why the `database_key*` slots survive
    //    a sync-only reset.
    final storage = ref.read(resetSecureStoreProvider);
    try {
      await wipeSyncKeychainNamespace(
        readAll: storage.readAll,
        deleteKey: storage.delete,
        includeRuntimeDekWrappingKey: true,
        log: _log,
      );
    } catch (e) {
      _log('Keychain wipe-by-prefix failed (non-fatal): $e');
    }

    // 6. Clear the biometric-gated DEK copy. This is stored under a separate
    //    Secure Enclave ACL (iOS biometryCurrentSet / Android biometric
    //    Keystore) and is invisible to the standard readAll() scan above, so
    //    it must be cleared explicitly via BiometricService.
    try {
      await ref.read(biometricServiceProvider).clear();
    } catch (e) {
      _log('Biometric DEK clear failed (non-fatal): $e');
    }

    // 7. Clear sync diagnostics that live in the main app database.
    await ref.read(syncQuarantineServiceProvider).clearAll();
    ref.invalidate(quarantinedItemsProvider);

    // 8. Reset sync-group-scoped one-time flags so a fresh pairing can run the
    // catch-up/migration passes for the new group.
    await _clearSyncOneTimeFlags();

    try {
      if (marker != null) {
        await markerStore.write(
          marker.copyWith(
            relayCleanupOutcome: relayCleanupOutcome,
            completedAt: DateTime.now().toUtc(),
            localAppDataOutcome: localAppDataOutcome,
            nextSetupConstraint: nextSetupConstraint,
          ),
        );
        ref.invalidate(syncDisconnectMarkerProvider);
      }
    } catch (e) {
      _log('Sync disconnect marker update failed (non-fatal): $e');
    }

    // 9. Reset providers so UI reverts to setup state
    ref.invalidate(prismSyncHandleProvider);
    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);
    ref.invalidate(syncDeviceIdProvider);
    ref.invalidate(syncDeviceSecretPresentProvider);
    ref.invalidate(syncWrappedDekPresentProvider);
    ref.invalidate(syncEventStreamProvider);
    ref.invalidate(websocketConnectedProvider);
    ref.read(syncHealthProvider.notifier).setState(SyncHealthState.unpaired);
  }

  Future<void> _resetAll() async {
    _log('Resetting all app data');

    // Android's OS-level app-data clear is the most complete local wipe, but
    // it kills the process after acceptance. Do best-effort remote sync teardown
    // first so reset does not leave relay/device records behind.
    if (ref.read(resetIsAndroidProvider)) {
      await _resetSyncSystem(
        reason: SyncDisconnectReason.fullReset,
        cleanupPolicy: SyncRelayCleanupPolicy.aggressive,
        localAppDataOutcome: LocalAppDataOutcome.wiped,
        nextSetupConstraint: SyncSetupConstraint.freshSetupChoice,
      );
      await _deleteSyncDisconnectMarkerForFullReset();
      await _clearFullResetFlowState();
      final db = ref.read(databaseProvider);
      try {
        final result = await ref
            .read(fullResetServiceProvider)
            .startAndroidClearApplicationData(openDatabase: db);
        if (result ==
            AndroidApplicationDataClearResult.manualFallbackCompleted) {
          ref.invalidate(databaseProvider);
          ref.invalidate(systemSettingsRepositoryProvider);
          ref.invalidate(pluralKitSyncProvider);
          ref.invalidate(quarantinedItemsProvider);
          _log('Completed full app reset via Android local-wipe fallback');
        }
      } catch (e) {
        _log(
          'Android OS app-data clear was rejected; falling back to local full reset: $e',
        );
        await _wipeLocalDataAfterSyncTeardown();
      }
      return;
    }

    // Full reset must sever sync before deleting app tables, otherwise a
    // relaunch can immediately restore stale remote state back into the app.
    await _resetSyncSystem(
      reason: SyncDisconnectReason.fullReset,
      cleanupPolicy: SyncRelayCleanupPolicy.aggressive,
      localAppDataOutcome: LocalAppDataOutcome.wiped,
      nextSetupConstraint: SyncSetupConstraint.freshSetupChoice,
    );
    await _deleteSyncDisconnectMarkerForFullReset();
    await _clearFullResetFlowState();
    await _wipeLocalDataAfterSyncTeardown();
  }

  Future<void> _markReplacePairingLocalWipeCompleted() async {
    try {
      final markerStore = ref.read(syncDisconnectMarkerStoreProvider);
      final marker = await markerStore.readForCurrentInstall();
      if (marker == null ||
          marker.reason != SyncDisconnectReason.replaceByPairing) {
        return;
      }
      await markerStore.write(
        marker.copyWith(
          completedAt: DateTime.now().toUtc(),
          localAppDataOutcome: LocalAppDataOutcome.wiped,
          nextSetupConstraint: SyncSetupConstraint.joinOnlyReplaceLocalData,
        ),
      );
      ref.invalidate(syncDisconnectMarkerProvider);
    } catch (e) {
      _log('Replace-by-pairing marker promotion failed (non-fatal): $e');
    }
  }

  Future<void> _deleteSyncDisconnectMarkerForFullReset() async {
    try {
      await ref.read(syncDisconnectMarkerStoreProvider).delete();
      ref.invalidate(syncDisconnectMarkerProvider);
    } catch (e) {
      _log('Full reset marker cleanup failed (non-fatal): $e');
    }
  }

  Future<void> _wipeLocalDataAfterSyncTeardown({
    bool requireRestart = true,
    String completionLog = 'Completed full app reset',
  }) async {
    final db = ref.read(databaseProvider);
    try {
      await ref
          .read(fullResetServiceProvider)
          .wipeLocalData(openDatabase: db, requireRestart: requireRestart);
    } finally {
      ref.invalidate(databaseProvider);
      ref.invalidate(systemSettingsRepositoryProvider);
      ref.invalidate(systemSettingsProvider);
      ref.invalidate(hasCompletedOnboardingProvider);
    }
    ref.invalidate(pluralKitSyncProvider);
    ref.invalidate(quarantinedItemsProvider);
    _log(completionLog);
  }
}

final resetDataNotifierProvider =
    AsyncNotifierProvider<ResetDataNotifier, void>(ResetDataNotifier.new);

class _SyncIdentitySnapshot {
  const _SyncIdentitySnapshot({
    required this.syncId,
    required this.deviceId,
    required this.sessionToken,
    required this.relayUrl,
  });

  final String? syncId;
  final String? deviceId;
  final String? sessionToken;
  final String? relayUrl;
}

RelayCleanupMarkerOutcome _markerOutcomeForRelayCleanup(
  RelayCleanupOutcome outcome,
) {
  return switch (outcome) {
    RelayCleanupOutcome.deregistered => RelayCleanupMarkerOutcome.deregistered,
    RelayCleanupOutcome.groupDeleted => RelayCleanupMarkerOutcome.groupDeleted,
    RelayCleanupOutcome.fallbackFailed =>
      RelayCleanupMarkerOutcome.fallbackFailed,
    RelayCleanupOutcome.failed => RelayCleanupMarkerOutcome.failed,
  };
}
