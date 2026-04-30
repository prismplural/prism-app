import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/services/biometric_service_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Re-export so tests in `test/features/settings/providers/` can import
/// `kProtectedFromReset` from this file (avoids a hand-copied list of
/// names in tests). Source of truth lives in `prism_sync_providers.dart`
/// alongside the other secure-store constants.
export 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show kProtectedFromReset;

abstract class ResetSecureStore {
  Future<String?> read(String key);
  Future<void> delete(String key);

  /// Read every key/value pair currently in the secure store. Used to
  /// scan for dynamic `prism_sync.epoch_key_*` / `prism_sync.runtime_keys_*`
  /// entries on reset/revoke cleanup.
  Future<Map<String, String>> readAll();

  /// Wipe every key in the store. Used by full reset only — never by sync-only
  /// reset, which must preserve `database_key` so the app DB stays openable.
  Future<void> deleteAll();
}

class _PlatformResetSecureStore implements ResetSecureStore {
  const _PlatformResetSecureStore();

  @override
  Future<String?> read(String key) => secureStorage.read(key: key);

  @override
  Future<void> delete(String key) => secureStorage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => secureStorage.readAll();

  @override
  Future<void> deleteAll() => secureStorage.deleteAll();
}

final resetSecureStoreProvider = Provider<ResetSecureStore>((ref) {
  return const _PlatformResetSecureStore();
});

final resetDocumentsDirectoryProvider = FutureProvider<Directory>((ref) async {
  return getApplicationDocumentsDirectory();
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
    'Sync System',
    'Clears sync keys, credentials, and history on this device while keeping app data.',
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
      await prefs.remove(PkGroupSyncV2CatchupService.flagKey);
      await prefs.remove(PkGroupRepairRunGate.checkedVersionKey);
      await prefs.remove(PkGroupRepairRunGate.checkedAtKey);
      await prefs.remove(PkGroupRepairRunGate.dirtyKey);
    } catch (e) {
      _log('SharedPreferences reset failed (non-fatal): $e');
    }
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

  /// Reset a specific category of data.
  Future<void> reset(ResetCategory category) async {
    state = await AsyncValue.guard(() async {
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
          await _resetSyncSystem();
        case ResetCategory.all:
          await _resetAll();
      }
    });
  }

  Future<void> _resetMembers() async {
    final db = ref.read(databaseProvider);
    _log('Resetting members');
    await db.transaction(() async {
      // Set fronting sessions to unknown (null member) instead of deleting.
      // Per-member shape (Phase 5): each row already represents a single
      // member, so nulling member_id orphans the row to "unknown" without
      // any co-fronter list to reset.  The v7 `co_fronter_ids` column is
      // legacy/unread storage and is not touched here.
      await db.customStatement('UPDATE fronting_sessions SET member_id = NULL');
      // Delete child data that references members
      await db.customStatement('DELETE FROM custom_field_values');
      await db.customStatement('DELETE FROM member_group_entries');
      await db.customStatement('DELETE FROM notes');
      await db.customStatement('DELETE FROM poll_votes');
      await db.customStatement('DELETE FROM habit_completions');
      // Delete members
      await db.customStatement('DELETE FROM members');
    });
    _notifyTableChanges([
      'fronting_sessions',
      'custom_field_values',
      'member_group_entries',
      'notes',
      'poll_votes',
      'habit_completions',
      'members',
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
    await db.transaction(() async {
      // FTS first — the chat_messages_fts_delete trigger does a full FTS
      // table scan per deleted row. Wiping FTS up front makes the trigger
      // a no-op and turns a minutes-long delete into milliseconds on large
      // chat histories.
      await db.customStatement('DELETE FROM chat_messages_fts');
      await db.customStatement('DELETE FROM chat_messages');
      await db.customStatement('DELETE FROM conversation_categories');
      await db.customStatement('DELETE FROM conversations');
    });
    _notifyTableChanges([
      'chat_messages',
      'conversation_categories',
      'conversations',
    ]);
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

  Future<void> _resetSyncSystem() async {
    _log('Resetting sync system');
    const prefix = 'prism_sync.';

    final handle = ref.read(resetSyncHandleProvider);
    final syncFfi = ref.read(resetSyncFfiProvider);

    // 0. Disable auto-sync FIRST — silences the debounce timer, the
    //    notification handler, and the WebSocket reconnect loop so they
    //    don't race the rest of the teardown (Phase 2A). Non-fatal: if
    //    setAutoSync throws (handle already torn down, FFI panic), keep
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

    // 1. Try to deregister from relay (best-effort — may fail if offline).
    //    If this is the last active device the relay rejects deregister with a
    //    403 and tells us to delete the sync group instead — fall through to
    //    deleteSyncGroup in that case so the relay drops all encrypted data.
    if (handle != null) {
      try {
        final syncId = await _readDecodedSecureValue('${prefix}sync_id');
        final deviceId = await _readDecodedSecureValue('${prefix}device_id');
        final sessionToken = await _readDecodedSecureValue(
          '${prefix}session_token',
        );
        if (syncId != null && deviceId != null && sessionToken != null) {
          bool deregistered = false;
          try {
            await syncFfi.deregisterDevice(
              handle: handle,
              syncId: syncId,
              deviceId: deviceId,
              sessionToken: sessionToken,
            );
            deregistered = true;
          } catch (e) {
            final msg = e.toString();
            if (msg.contains('last active device') || msg.contains('403')) {
              // Sole device — the relay requires deleting the full group.
              _log('Last device; attempting sync group deletion: $e');
            } else {
              _log('Relay deregister failed (non-fatal): $e');
            }
          }
          if (!deregistered) {
            try {
              await syncFfi.deleteSyncGroup(
                handle: handle,
                syncId: syncId,
                deviceId: deviceId,
                sessionToken: sessionToken,
              );
            } catch (e) {
              _log('Relay sync group delete failed (non-fatal): $e');
            }
          }
        }
      } catch (e) {
        _log('Relay cleanup failed (non-fatal): $e');
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

    // 5. Wipe the prism_sync.* keychain namespace by prefix, excluding the
    //    DB-encryption slots in `kProtectedFromReset`. Inclusion-by-prefix
    //    catches transient pairing keys (`bootstrap_joiner_bundle`,
    //    `pending_sync_id`, `registration_token`, etc.) that the old
    //    static allow-list missed. See `kProtectedFromReset` doc for why
    //    the `database_key*` slots survive a sync-only reset.
    final storage = ref.read(resetSecureStoreProvider);
    try {
      final all = await storage.readAll();
      for (final fullKey in all.keys) {
        if (!fullKey.startsWith(prefix)) continue;
        if (kProtectedFromReset.contains(fullKey)) continue;
        try {
          await storage.delete(fullKey);
        } catch (e) {
          _log('Keychain delete failed for $fullKey (non-fatal): $e');
        }
      }
    } catch (e) {
      _log('Keychain wipe-by-prefix failed (non-fatal): $e');
    }
    try {
      await const DeviceBoundRuntimeDekStore().deleteWrappingKey();
    } catch (e) {
      _log('Runtime DEK wrapping-key delete failed (non-fatal): $e');
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

    // 9. Reset providers so UI reverts to setup state
    ref.invalidate(prismSyncHandleProvider);
    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);
    ref.invalidate(syncStatusProvider);
    ref.read(syncHealthProvider.notifier).setState(SyncHealthState.healthy);
  }

  Future<void> _resetAll() async {
    final db = ref.read(databaseProvider);
    _log('Resetting all app data');

    // Full reset must sever sync before deleting app tables, otherwise a
    // relaunch can immediately restore stale remote state back into the app.
    await _resetSyncSystem();

    // Delete in dependency order (children first)
    await db.transaction(() async {
      await db.customStatement('DELETE FROM habit_completions');
      await db.customStatement('DELETE FROM habits');
      await db.customStatement('DELETE FROM poll_votes');
      await db.customStatement('DELETE FROM poll_options');
      await db.customStatement('DELETE FROM polls');
      // FTS first so the chat_messages_fts_delete trigger is a no-op. See
      // _resetChat for the full explanation.
      await db.customStatement('DELETE FROM chat_messages_fts');
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
      await db.customStatement('DELETE FROM pk_group_entry_deferred_sync_ops');
      await db.customStatement('DELETE FROM pk_group_sync_aliases');
      await db.customStatement('DELETE FROM notes');
      await db.customStatement('DELETE FROM reminders');
      await db.customStatement('DELETE FROM friends');
      await db.customStatement('DELETE FROM sharing_requests');
      await db.customStatement('DELETE FROM media_attachments');
      await db.customStatement('DELETE FROM members');
      await db.customStatement('DELETE FROM plural_kit_sync_state');
      await db.customStatement('DELETE FROM pk_mapping_state');
      await db.customStatement('DELETE FROM sp_sync_state');
      await db.customStatement('DELETE FROM sp_id_map');
      await db.customStatement('DELETE FROM sync_quarantine');
    });

    // Delete the encrypted media cache from disk. DB rows are already gone
    // above; the cache files are encrypted ciphertexts stored separately under
    // getApplicationSupportDirectory()/prism_media/. Without this they'd
    // become orphaned blobs with no decryption key.
    try {
      await ref.read(downloadManagerProvider).clearCache();
    } catch (e) {
      _log('Media cache clear failed (non-fatal): $e');
    }

    // Recreate default settings with onboarding reset. This must happen
    // BEFORE deleting DB files — deleting the WAL/SHM while the connection
    // is open makes SQLite read-only.
    final settingsRepo = ref.read(systemSettingsRepositoryProvider);
    await settingsRepo.updateSettings(
      const SystemSettings(hasCompletedOnboarding: false),
    );

    // Delete the encrypted database files FIRST, then clear the encryption
    // key. This ordering is critical: if file deletion fails but the key is
    // already cleared, next launch would have no key for an encrypted DB
    // (unrecoverable). With this order, a failed file delete still leaves
    // the key available to open the DB on next launch.
    try {
      final dir = await ref.read(resetDocumentsDirectoryProvider.future);
      final appDbPath = p.join(dir.path, 'prism.db');
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$appDbPath$suffix');
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      _log('App DB file delete after full reset failed (non-fatal): $e');
    }
    // Now safe to clear the key — the DB files are gone (or still openable
    // with the key if deletion failed above).
    await clearDatabaseEncryptionState();

    // Wipe the entire keychain namespace. Called after all DB files and
    // encryption keys are deleted so there's nothing left to protect.
    // This catches orphaned bare-named items from older app versions (e.g.
    // keys written before the `prism_sync.` prefix was adopted) that the
    // selective deletion above would otherwise miss. Also covers
    // prism_pluralkit_token and any future keys without an explicit listing.
    await ref.read(resetSecureStoreProvider).deleteAll();

    _notifyTableChanges([
      'habit_completions',
      'habits',
      'poll_votes',
      'poll_options',
      'polls',
      'chat_messages',
      'conversation_categories',
      'conversations',
      'front_session_comments',
      'fronting_sessions',
      'sleep_sessions',
      'custom_field_values',
      'custom_fields',
      'member_group_entries',
      'member_groups',
      'pk_group_entry_deferred_sync_ops',
      'pk_group_sync_aliases',
      'notes',
      'reminders',
      'friends',
      'members',
      'plural_kit_sync_state',
      'pk_mapping_state',
      'sp_sync_state',
      'sp_id_map',
      'sync_quarantine',
      'system_settings',
    ]);
    ref.invalidate(pluralKitSyncProvider);
    ref.invalidate(quarantinedItemsProvider);
    _log('Completed full app reset');
  }
}

final resetDataNotifierProvider =
    AsyncNotifierProvider<ResetDataNotifier, void>(ResetDataNotifier.new);
