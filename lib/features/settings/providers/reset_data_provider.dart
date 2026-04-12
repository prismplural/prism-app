import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';

abstract class ResetSecureStore {
  Future<String?> read(String key);
  Future<void> delete(String key);

  /// Read every key/value pair currently in the secure store. Used to
  /// scan for dynamic `prism_sync.epoch_key_*` / `prism_sync.runtime_keys_*`
  /// entries on reset/revoke cleanup.
  Future<Map<String, String>> readAll();
}

class _PlatformResetSecureStore implements ResetSecureStore {
  const _PlatformResetSecureStore();

  @override
  Future<String?> read(String key) => secureStorage.read(key: key);

  @override
  Future<void> delete(String key) => secureStorage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => secureStorage.readAll();
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

class ResetDataNotifier extends Notifier<void> {
  @override
  void build() {}

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
  }

  Future<void> _resetMembers() async {
    final db = ref.read(databaseProvider);
    _log('Resetting members');
    await db.transaction(() async {
      // Set fronting sessions to unknown (null member) instead of deleting
      await db.customStatement(
        'UPDATE fronting_sessions SET member_id = NULL, co_fronter_ids = \'[]\'',
      );
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

    // 1. Try to deregister from relay (best-effort — may fail if offline)
    final handle = ref.read(resetSyncHandleProvider);
    if (handle != null) {
      try {
        final syncId = await _readDecodedSecureValue('${prefix}sync_id');
        final deviceId = await _readDecodedSecureValue('${prefix}device_id');
        final sessionToken = await _readDecodedSecureValue(
          '${prefix}session_token',
        );
        if (syncId != null && deviceId != null && sessionToken != null) {
          await ffi.deregisterDevice(
            handle: handle,
            syncId: syncId,
            deviceId: deviceId,
            sessionToken: sessionToken,
          );
        }
      } catch (e) {
        _log('Relay deregister failed (non-fatal): $e');
      }
    }

    // 2. Clear sync credentials from platform keychain.
    // IMPORTANT: database_key is intentionally NOT listed here. It is a
    // local encryption key (Signal model) that must survive sync resets.
    // Only _resetAll() clears it (via clearDatabaseEncryptionState), and
    // only after deleting the DB files. Adding it here would make the
    // encrypted local database permanently unreadable.
    final storage = ref.read(resetSecureStoreProvider);
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
      'sharing_prekey_store',
      'sharing_id_cache',
      'min_signature_version_floor',
      'runtime_dek',
    ]) {
      await storage.delete('$prefix$key');
    }
    // Dynamic-prefix cleanup: any `prism_sync.epoch_key_*` or
    // `prism_sync.runtime_keys_*` entries left over from a previous
    // pairing must also be wiped, otherwise they'd seed into a fresh
    // handle after re-pairing and corrupt the new group's key hierarchy.
    try {
      final all = await storage.readAll();
      for (final fullKey in all.keys) {
        if (!fullKey.startsWith(prefix)) continue;
        final bare = fullKey.substring(prefix.length);
        if (bare.startsWith('epoch_key_') || bare.startsWith('runtime_keys_')) {
          await storage.delete(fullKey);
        }
      }
    } catch (e) {
      _log('Dynamic secure-store cleanup failed (non-fatal): $e');
    }

    // 3. Delete the Rust sync database
    try {
      final dir = await ref.read(resetDocumentsDirectoryProvider.future);
      final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      // Also delete WAL/SHM files
      final wal = File('$dbPath-wal');
      final shm = File('$dbPath-shm');
      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
    } catch (e) {
      _log('DB file delete failed (non-fatal): $e');
    }

    // 4. Clear sync diagnostics that live in the main app database.
    await ref.read(syncQuarantineServiceProvider).clearAll();
    ref.invalidate(quarantinedItemsProvider);

    // 5. Dispose the old FFI handle before invalidating the provider.
    //    dispose() eagerly drops the Rust-side Arc<Mutex<PrismSync>>,
    //    releasing SQLite connections and WebSocket handles immediately
    //    rather than waiting for Dart GC to collect the orphaned object.
    //    The ref.onDispose callback in PrismSyncHandleNotifier.build()
    //    also calls dispose(), but explicitly doing it here ensures the
    //    old handle's resources are freed before build() creates a new one.
    handle?.dispose();

    // 6. Reset providers so UI reverts to setup state
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

    // Clear third-party credentials that are stored outside the main DB.
    await ref.read(resetSecureStoreProvider).delete('prism_pluralkit_token');

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
      'notes',
      'reminders',
      'friends',
      'members',
      'plural_kit_sync_state',
      'sync_quarantine',
      'system_settings',
    ]);
    ref.invalidate(pluralKitSyncProvider);
    ref.invalidate(quarantinedItemsProvider);
    _log('Completed full app reset');
  }
}

final resetDataNotifierProvider = NotifierProvider<ResetDataNotifier, void>(
  ResetDataNotifier.new,
);
