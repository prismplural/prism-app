import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart' as sync;
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:shared_preferences/shared_preferences.dart';

/// Every user-data table in the database. When a new table is added to the
/// Drift schema, add it here — the completeness guard test will fail if any
/// table is missing from the "All Data" reset.
const _allUserDataTables = [
  'members',
  'fronting_sessions',
  'conversations',
  'chat_messages',
  'system_settings',
  'polls',
  'poll_options',
  'poll_votes',
  'sleep_sessions',
  'plural_kit_sync_state',
  'habits',
  'habit_completions',
  'sync_quarantine',
  'member_groups',
  'member_group_entries',
  'pk_group_sync_aliases',
  'pk_group_entry_deferred_sync_ops',
  'custom_fields',
  'custom_field_values',
  'notes',
  'front_session_comments',
  'conversation_categories',
  'reminders',
  'friends',
  'sharing_requests',
  'media_attachments',
  'sp_sync_state',
  'sp_id_map',
  'pk_mapping_state',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub flutter_secure_storage platform channel for tests that trigger
  // clearDatabaseEncryptionState() during full reset.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall methodCall) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  // ── Completeness guard ──────────────────────────────────────────────
  // Fails when a new table is added to the schema but not to the reset
  // list or this test file. Forces the developer to handle it.

  test('_allUserDataTables covers every table in the Drift schema', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final schemaTableNames = db.allTables.map((t) => t.actualTableName).toSet();
    final coveredTableNames = _allUserDataTables.toSet();

    final missing = schemaTableNames.difference(coveredTableNames);
    final extra = coveredTableNames.difference(schemaTableNames);

    expect(
      missing,
      isEmpty,
      reason:
          'Tables in DB schema but not in _allUserDataTables '
          '(add them to the list AND to _resetAll): $missing',
    );
    expect(
      extra,
      isEmpty,
      reason:
          'Tables in _allUserDataTables but not in DB schema '
          '(remove stale entries): $extra',
    );
  });

  // ── Category resets ─────────────────────────────────────────────────

  group('ResetDataNotifier', () {
    test(
      'members reset clears members and related child data, preserves sessions as unknown',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        await harness.seedAllData();
        await harness.reset(ResetCategory.members);

        final reopened = await harness.reopenDatabase();
        addTearDown(reopened.close);

        expect(await _countRows(reopened, 'members'), 0);
        expect(await _countRows(reopened, 'poll_votes'), 0);
        expect(await _countRows(reopened, 'custom_field_values'), 0);
        expect(await _countRows(reopened, 'member_group_entries'), 0);
        expect(await _countRows(reopened, 'notes'), 0);
        expect(await _countRows(reopened, 'habit_completions'), 0);
        // Sessions preserved but member nulled.  Per-member shape: a
        // co-fronted seed expands to 2 normal rows + 1 sleep row = 3.
        expect(await _countRows(reopened, 'fronting_sessions'), 3);
        expect(await _countRows(reopened, 'chat_messages'), 1);
        // Groups and custom fields definitions remain
        expect(await _countRows(reopened, 'member_groups'), 1);
        expect(await _countRows(reopened, 'custom_fields'), 1);

        // Per-member shape (Phase 5): _resetMembers nulls member_id on the
        // remaining session rows.  co_fronter_ids still physically exists in
        // v7 (legacy/unread storage) but is no longer touched by the reset.
        final sessionRow = await reopened
            .customSelect(
              '''
        SELECT member_id
        FROM fronting_sessions
        WHERE id = ?
        ''',
              variables: [Variable.withString('session-1')],
            )
            .getSingle();
        expect(sessionRow.data['member_id'], isNull);
      },
    );

    test('fronting reset clears sessions and comments', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.fronting);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countFrontingRows(reopened), 0);
      expect(await _countRows(reopened, 'front_session_comments'), 1);
      expect(await _countSleepRows(reopened), 1);
      expect(await _countRows(reopened, 'members'), 2);
      expect(await _countRows(reopened, 'chat_messages'), 1);
    });

    test('chat reset clears conversations, messages, and categories', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.chat);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countRows(reopened, 'chat_messages'), 0);
      expect(await _countRows(reopened, 'conversations'), 0);
      expect(await _countRows(reopened, 'conversation_categories'), 0);
      expect(await _countRows(reopened, 'polls'), 1);
    });

    test('polls reset clears polls, options, and votes', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.polls);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countRows(reopened, 'poll_votes'), 0);
      expect(await _countRows(reopened, 'poll_options'), 0);
      expect(await _countRows(reopened, 'polls'), 0);
      expect(await _countRows(reopened, 'members'), 2);
    });

    test('habits reset clears habits and completions', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.habits);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countRows(reopened, 'habit_completions'), 0);
      expect(await _countRows(reopened, 'habits'), 0);
      expect(await _countSleepRows(reopened), 1);
    });

    test('sleep reset clears only sleep sessions', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sleep);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countSleepRows(reopened), 0);
      // Per-member shape: 2 normal rows (one per co-fronter) survive.
      expect(await _countRows(reopened, 'fronting_sessions'), 2);
      expect(await _countRows(reopened, 'front_session_comments'), 1);
      expect(await _countRows(reopened, 'habits'), 1);
      expect(await _countRows(reopened, 'members'), 2);
    });

    test('sync reset handles non-base64 keychain values gracefully', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      // Overwrite a sync key with a plain (non-base64) value to exercise the
      // _readDecodedSecureValue fallback path.
      harness.secureStore.seedSyncValue('prism_sync.sync_id', 'not-base64!');

      // Should complete without throwing.
      await harness.reset(ResetCategory.sync);

      expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
    });

    test('sync reset preserves app data but clears sync persistence', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sync);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countRows(reopened, 'members'), 2);
      expect(await _countRows(reopened, 'chat_messages'), 1);
      expect(await _countRows(reopened, 'sync_quarantine'), 0);

      expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
      expect(
        harness.secureStore.readSyncValue('prism_sync.session_token'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_pluralkit_token'),
        'pk-secret-token',
      );

      expect(await harness.syncDbFile.exists(), isFalse);
      expect(await harness.syncWalFile.exists(), isFalse);
      expect(await harness.syncShmFile.exists(), isFalse);
    });

    test('sync reset leaves sync state ready for fresh setup', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      harness.container
          .read(sync.syncHealthProvider.notifier)
          .setState(sync.SyncHealthState.disconnected);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sync);

      expect(
        harness.container.read(sync.syncHealthProvider),
        sync.SyncHealthState.unpaired,
      );
      final status = harness.container.read(sync.syncStatusProvider);
      expect(status.isSyncing, isFalse);
      expect(status.pendingOps, 0);
      expect(status.lastError, isNull);
      expect(status.hasQuarantinedItems, isFalse);
      expect(harness.container.read(sync.websocketConnectedProvider), isFalse);
    });

    test(
      'sync reset deletes dynamic epoch_key_* and runtime_keys_* entries',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        await harness.seedAllData();
        // Seed a mix of dynamic keys that would have been left behind by
        // the old reset path (which only deleted the static allow-list).
        harness.secureStore.seedSyncValue('prism_sync.epoch_key_1', 'AAAA');
        harness.secureStore.seedSyncValue('prism_sync.epoch_key_7', 'BBBB');
        harness.secureStore.seedSyncValue(
          'prism_sync.runtime_keys_default',
          'CCCC',
        );
        // Foreign-prefixed entry should NOT be touched.
        harness.secureStore.seedSyncValue('other_app.epoch_key_1', 'DDDD');

        await harness.reset(ResetCategory.sync);

        expect(
          harness.secureStore.readSyncValue('prism_sync.epoch_key_1'),
          isNull,
        );
        expect(
          harness.secureStore.readSyncValue('prism_sync.epoch_key_7'),
          isNull,
        );
        expect(
          harness.secureStore.readSyncValue('prism_sync.runtime_keys_default'),
          isNull,
        );
        expect(
          harness.secureStore.readSyncValue('other_app.epoch_key_1'),
          'DDDD',
        );
      },
    );

    test(
      'sync reset falls back to known credential keys when readAll fails',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        harness.secureStore
          ..seedSyncValue(
            'prism_sync.sync_id',
            base64Encode(utf8.encode('sync-abc')),
          )
          ..seedSyncValue('prism_sync.registration_token', 'WIPE_REGISTRATION')
          ..seedSyncValue('prism_sync.runtime_dek_wrapped_v1', 'WIPE_WRAPPED')
          ..seedSyncValue('prism_sync.database_key', 'KEEP_DATABASE');
        harness.secureStore.throwOnReadAll = true;

        await harness.reset(ResetCategory.sync);

        expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
        expect(
          harness.secureStore.readSyncValue('prism_sync.registration_token'),
          isNull,
        );
        expect(
          harness.secureStore.readSyncValue(
            'prism_sync.runtime_dek_wrapped_v1',
          ),
          isNull,
        );
        expect(
          harness.secureStore.readSyncValue('prism_sync.database_key'),
          'KEEP_DATABASE',
        );
      },
    );

    // ── Phase 1B / 2A / 2B-1 ────────────────────────────────────────
    // The reset hardening tests below cover:
    // sync-pairing-reset-hardening.md:
    //   1B — wipe-by-prefix (don't leave stale `bootstrap_*`/`pending_*`/
    //        `registration_token` entries behind because a static allow-list
    //        forgot them).
    //   2A — `setAutoSync(false)` runs as step 0 so the auto-sync driver
    //        and notification handler can't race the rest of teardown.
    //   2B-1 — handle.dispose() runs BEFORE the sync-DB file is deleted
    //          so we don't unlink a file out from under a live SQLite
    //          connection (Android WAL corruption risk).
    //   2B-2 — clearSyncState(sync_id, forceActive: true) runs before
    //          dispose/file-delete and is non-fatal if it fails.

    test('reset_wipes_all_prism_sync_namespace_keys', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      // Pre-populate fake secureStorage with a mix of:
      //  - transient pairing keys missed by the v1 allow-list
      //  - the four DB-encryption slots (must survive)
      //  - an unrelated app key (no `prism_sync.` prefix; must survive)
      harness.secureStore
        ..seedSyncValue('prism_sync.bootstrap_joiner_bundle', 'B1')
        ..seedSyncValue('prism_sync.pending_sync_id', 'P1')
        ..seedSyncValue('prism_sync.registration_token', 'R1')
        ..seedSyncValue('prism_sync.runtime_dek', 'D1')
        ..seedSyncValue('prism_sync.runtime_dek_wrapped_v1', 'W1')
        ..seedSyncValue('prism_sync.database_key', 'KEEP1')
        ..seedSyncValue('prism_sync.database_key_staging', 'KEEP2')
        ..seedSyncValue('prism_sync.sync_database_key', 'KEEP3')
        ..seedSyncValue('prism_sync.sync_database_key_staging', 'KEEP4')
        ..seedSyncValue('unrelated_app_key', 'OUTSIDE_NAMESPACE');

      await harness.reset(ResetCategory.sync);

      // All four DB-encryption keys must survive — assert via the
      // re-exported set so adding/removing a slot in
      // prism_sync_providers.dart automatically updates this assertion.
      for (final protectedKey in kProtectedFromReset) {
        expect(
          harness.secureStore.readSyncValue(protectedKey),
          isNotNull,
          reason: '$protectedKey is in kProtectedFromReset and must survive',
        );
      }

      // Out-of-namespace key untouched.
      expect(
        harness.secureStore.readSyncValue('unrelated_app_key'),
        'OUTSIDE_NAMESPACE',
      );

      // Every other prism_sync.* entry gone — including the four the v1
      // allow-list missed.
      final remaining = await harness.secureStore.readAll();
      for (final fullKey in remaining.keys) {
        if (!fullKey.startsWith('prism_sync.')) continue;
        expect(
          kProtectedFromReset,
          contains(fullKey),
          reason:
              '$fullKey should have been wiped by reset; only '
              'kProtectedFromReset slots may survive a sync reset',
        );
      }
      expect(
        harness.secureStore.readSyncValue('prism_sync.bootstrap_joiner_bundle'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.pending_sync_id'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.registration_token'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.runtime_dek'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.runtime_dek_wrapped_v1'),
        isNull,
      );
    });

    test('reset_preserves_database_keys', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      harness.secureStore
        ..seedSyncValue('prism_sync.database_key', 'KEEP_DATABASE')
        ..seedSyncValue(
          'prism_sync.database_key_staging',
          'KEEP_DATABASE_STAGING',
        )
        ..seedSyncValue('prism_sync.sync_database_key', 'KEEP_SYNC_DATABASE')
        ..seedSyncValue(
          'prism_sync.sync_database_key_staging',
          'KEEP_SYNC_DATABASE_STAGING',
        )
        ..seedSyncValue(
          'prism_sync.sync_id',
          base64Encode(utf8.encode('sync-abc')),
        )
        ..seedSyncValue('prism_sync.registration_token', 'WIPE_REGISTRATION')
        ..seedSyncValue('prism_sync.runtime_dek', 'WIPE_RUNTIME')
        ..seedSyncValue('prism_sync.runtime_dek_wrapped_v1', 'WIPE_WRAPPED');

      await harness.reset(ResetCategory.sync);

      expect(
        harness.secureStore.readSyncValue('prism_sync.database_key'),
        'KEEP_DATABASE',
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.database_key_staging'),
        'KEEP_DATABASE_STAGING',
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.sync_database_key'),
        'KEEP_SYNC_DATABASE',
      );
      expect(
        harness.secureStore.readSyncValue(
          'prism_sync.sync_database_key_staging',
        ),
        'KEEP_SYNC_DATABASE_STAGING',
      );
      expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
      expect(
        harness.secureStore.readSyncValue('prism_sync.registration_token'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.runtime_dek'),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue('prism_sync.runtime_dek_wrapped_v1'),
        isNull,
      );
    });

    test('reset_disables_auto_sync_first', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi();

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
      );
      addTearDown(harness.dispose);

      // Seed sync_id/device_id/session_token so the relay-deregister branch
      // actually runs — this is the path we're asserting setAutoSync precedes.
      harness.secureStore
        ..seedSyncValue(
          'prism_sync.sync_id',
          base64Encode(utf8.encode('sync-abc')),
        )
        ..seedSyncValue(
          'prism_sync.device_id',
          base64Encode(utf8.encode('device-abc')),
        )
        ..seedSyncValue(
          'prism_sync.session_token',
          base64Encode(utf8.encode('session-abc')),
        );

      await harness.reset(ResetCategory.sync);

      expect(
        recordingFfi.calls,
        isNotEmpty,
        reason: 'expected at least one FFI call during reset',
      );
      expect(
        recordingFfi.calls.first,
        'setAutoSync(enabled: false)',
        reason:
            'setAutoSync(false) must be the first FFI call so the auto-sync '
            'driver/notification handler does not race the rest of teardown',
      );
      // And it must precede deregisterDevice, which is the next FFI call.
      expect(recordingFfi.calls, contains('deregisterDevice'));
      expect(
        recordingFfi.calls.indexOf('setAutoSync(enabled: false)'),
        lessThan(recordingFfi.calls.indexOf('deregisterDevice')),
      );
    });

    test('reset_disposes_handle_before_deleting_db', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi();
      final orderLog = <String>[];

      // Wire the FFI dispose call into orderLog. The harness also passes a
      // file-delete observer that records when File.delete() runs against
      // the sync-DB path — together they let us assert the relative order.
      recordingFfi.onDispose = () => orderLog.add('dispose');

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
        deleteObserver: (path) => orderLog.add('delete:$path'),
      );
      addTearDown(harness.dispose);

      // Make sure the sync DB file exists so the delete branch runs
      // (`seedAllData` already does this, but this test doesn't seed full
      // app data — write the file directly).
      await harness.syncDbFile.writeAsString('sync-db');

      await harness.reset(ResetCategory.sync);

      expect(orderLog, contains('dispose'));
      final disposeIdx = orderLog.indexOf('dispose');
      final deleteIdx = orderLog.indexWhere((e) => e.startsWith('delete:'));
      expect(
        deleteIdx,
        greaterThanOrEqualTo(0),
        reason: 'expected the sync-DB file delete to be observed',
      );
      expect(
        disposeIdx,
        lessThan(deleteIdx),
        reason:
            'handle.dispose() must run before the sync-DB file is deleted '
            '(prevents Android WAL corruption / SQLITE_IOERR from a live '
            'connection writing to an unlinked file)',
      );

      // After the reset, the file is gone.
      expect(await harness.syncDbFile.exists(), isFalse);
      expect(fakeHandle.disposeCount, 1);
    });

    test('reset_calls_clear_sync_state_before_dispose_and_delete', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi();
      final orderLog = <String>[];

      recordingFfi.onClearSyncState = (syncId) {
        orderLog.add('clear:$syncId');
      };
      recordingFfi.onDispose = () => orderLog.add('dispose');

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
        deleteObserver: (path) => orderLog.add('delete:$path'),
      );
      addTearDown(harness.dispose);

      harness.secureStore
        ..seedSyncValue(
          'prism_sync.sync_id',
          base64Encode(utf8.encode('sync-abc')),
        )
        ..seedSyncValue(
          'prism_sync.device_id',
          base64Encode(utf8.encode('device-abc')),
        )
        ..seedSyncValue(
          'prism_sync.session_token',
          base64Encode(utf8.encode('session-abc')),
        );
      await harness.syncDbFile.writeAsString('sync-db');

      await harness.reset(ResetCategory.sync);

      expect(
        recordingFfi.calls,
        containsAllInOrder([
          'setAutoSync(enabled: false)',
          'deregisterDevice',
          'clearSyncState(syncId: sync-abc, forceActive: true)',
          'disposeHandle',
        ]),
      );

      final clearIdx = orderLog.indexOf('clear:sync-abc');
      final disposeIdx = orderLog.indexOf('dispose');
      final deleteIdx = orderLog.indexWhere((e) => e.startsWith('delete:'));
      expect(clearIdx, greaterThanOrEqualTo(0));
      expect(disposeIdx, greaterThan(clearIdx));
      expect(deleteIdx, greaterThan(disposeIdx));
    });

    test('reset_calls_clear_sync_state_when_db_delete_fails', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi();
      final orderLog = <String>[];

      recordingFfi.onClearSyncState = (syncId) {
        orderLog.add('clear:$syncId');
      };

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
        deleteObserver: (path) {
          orderLog.add('delete:$path');
          throw FileSystemException('delete failed', path);
        },
      );
      addTearDown(harness.dispose);

      harness.secureStore.seedSyncValue(
        'prism_sync.sync_id',
        base64Encode(utf8.encode('sync-abc')),
      );
      await harness.syncDbFile.writeAsString('sync-db');

      await harness.reset(ResetCategory.sync);

      expect(
        recordingFfi.calls,
        contains('clearSyncState(syncId: sync-abc, forceActive: true)'),
      );
      expect(orderLog, contains('clear:sync-abc'));
      expect(orderLog.any((e) => e.startsWith('delete:')), isTrue);
      expect(
        orderLog.indexOf('clear:sync-abc'),
        lessThan(orderLog.indexWhere((e) => e.startsWith('delete:'))),
      );
      expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
      expect(fakeHandle.disposeCount, 1);
    });

    test('reset_continues_when_clear_sync_state_fails', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi()
        ..throwOnClearSyncState = true;
      final orderLog = <String>[];
      recordingFfi.onDispose = () => orderLog.add('dispose');

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
        deleteObserver: (path) => orderLog.add('delete:$path'),
      );
      addTearDown(harness.dispose);

      harness.secureStore.seedSyncValue(
        'prism_sync.sync_id',
        base64Encode(utf8.encode('sync-abc')),
      );
      await harness.syncDbFile.writeAsString('sync-db');

      await harness.reset(ResetCategory.sync);

      expect(
        recordingFfi.calls,
        contains('clearSyncState(syncId: sync-abc, forceActive: true)'),
      );
      expect(orderLog, contains('dispose'));
      expect(orderLog.any((e) => e.startsWith('delete:')), isTrue);
      expect(await harness.syncDbFile.exists(), isFalse);
      expect(fakeHandle.disposeCount, 1);
    });

    test('sync reset clears sync one-time SharedPreferences flags', () async {
      SharedPreferences.setMockInitialValues({
        'sync.enum_fields_reemit_v1': true,
        PkGroupSyncV2CatchupService.flagKey: true,
        PkGroupRepairRunGate.checkedVersionKey:
            PkGroupRepairRunGate.currentVersion,
        PkGroupRepairRunGate.checkedAtKey: '2026-04-24T00:00:00.000',
        PkGroupRepairRunGate.dirtyKey: true,
        'unrelated_flag': true,
      });
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sync);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync.enum_fields_reemit_v1'), isNull);
      expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isNull);
      expect(prefs.getInt(PkGroupRepairRunGate.checkedVersionKey), isNull);
      expect(prefs.getString(PkGroupRepairRunGate.checkedAtKey), isNull);
      expect(prefs.getBool(PkGroupRepairRunGate.dirtyKey), isNull);
      expect(prefs.getBool('unrelated_flag'), isTrue);
    });

    // ── Full reset ──────────────────────────────────────────────────

    test(
      'full reset clears every table, recreates default settings, and removes external state',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        await harness.seedAllData();
        await harness.reset(ResetCategory.all);

        final reopened = await harness.reopenDatabase();
        addTearDown(reopened.close);

        // Every user-data table except system_settings must be empty.
        for (final table in _allUserDataTables) {
          if (table == 'system_settings') continue;
          expect(
            await _countRows(reopened, table),
            0,
            reason: '$table should be empty after full reset',
          );
        }

        // system_settings gets recreated with onboarding reset
        final settings = await reopened
            .select(reopened.systemSettingsTable)
            .get();
        expect(settings, hasLength(1));
        expect(settings.single.hasCompletedOnboarding, isFalse);
        expect(settings.single.systemName, isNull);

        expect(harness.secureStore.readSyncValue('prism_sync.sync_id'), isNull);
        expect(
          harness.secureStore.readSyncValue('prism_pluralkit_token'),
          isNull,
        );
        expect(await harness.syncDbFile.exists(), isFalse);
        expect(await harness.syncWalFile.exists(), isFalse);
        expect(await harness.syncShmFile.exists(), isFalse);
        expect(await harness.appDbFile.exists(), isTrue);
        expect(await harness.mediaCacheDir.exists(), isFalse);
      },
    );

    test('full reset empties every table that had seeded data', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();

      // Verify seed actually populated every table
      for (final table in _allUserDataTables) {
        expect(
          await _countRows(harness.db, table),
          greaterThan(0),
          reason: '$table should have seed data (update seedAllData if new)',
        );
      }

      await harness.reset(ResetCategory.all);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      for (final table in _allUserDataTables) {
        if (table == 'system_settings') continue;
        expect(
          await _countRows(reopened, table),
          0,
          reason: '$table should be empty after full reset',
        );
      }

      expect(await harness.mediaCacheDir.exists(), isFalse);
    });
  });
}

class _ResetHarness {
  _ResetHarness._({
    required this.tempDir,
    required this.appDbFile,
    required this.syncDbFile,
    required this.syncWalFile,
    required this.syncShmFile,
    required this.mediaCacheDir,
    required this.db,
    required this.container,
    required this.secureStore,
  });

  final Directory tempDir;
  final File appDbFile;
  final File syncDbFile;
  final File syncWalFile;
  final File syncShmFile;
  final Directory mediaCacheDir;
  final AppDatabase db;
  final ProviderContainer container;
  final _FakeResetSecureStore secureStore;

  bool _disposed = false;

  static Future<_ResetHarness> create({
    ffi.PrismSyncHandle? handleOverride,
    ResetSyncFfi? ffiOverride,
    ResetFileDeleteObserver? deleteObserver,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('prism-reset-test-');
    final appDbFile = File(p.join(tempDir.path, 'prism-test.db'));
    final syncDbFile = File(p.join(tempDir.path, 'prism_sync.db'));
    final syncWalFile = File('${syncDbFile.path}-wal');
    final syncShmFile = File('${syncDbFile.path}-shm');
    final mediaCacheDir = Directory(p.join(tempDir.path, 'prism_media'));

    final db = AppDatabase(NativeDatabase(appDbFile));
    final secureStore = _FakeResetSecureStore();
    final systemSettingsRepository = DriftSystemSettingsRepository(
      db.systemSettingsDao,
      null,
    );

    // DownloadManager is overridden with a cache dir inside tempDir so that
    // clearCache() doesn't hit getApplicationSupportDirectory() (which requires
    // a platform channel not available in unit tests).
    final downloadManager = DownloadManager(
      handle: null,
      encryption: MediaEncryptionService(),
      cacheDirOverride: mediaCacheDir,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        systemSettingsRepositoryProvider.overrideWithValue(
          systemSettingsRepository,
        ),
        resetSecureStoreProvider.overrideWithValue(secureStore),
        resetDocumentsDirectoryProvider.overrideWith((ref) async => tempDir),
        resetSyncHandleProvider.overrideWithValue(handleOverride),
        downloadManagerProvider.overrideWithValue(downloadManager),
        if (ffiOverride != null)
          resetSyncFfiProvider.overrideWithValue(ffiOverride),
        if (deleteObserver != null)
          resetFileDeleteObserverProvider.overrideWithValue(deleteObserver),
      ],
    );

    return _ResetHarness._(
      tempDir: tempDir,
      appDbFile: appDbFile,
      syncDbFile: syncDbFile,
      syncWalFile: syncWalFile,
      syncShmFile: syncShmFile,
      mediaCacheDir: mediaCacheDir,
      db: db,
      container: container,
      secureStore: secureStore,
    );
  }

  /// Seeds at least one row into every user-data table.
  ///
  /// When you add a new table to the schema, add a seed row here — the
  /// 'full reset empties every table that had seeded data' test will fail
  /// if any table in [_allUserDataTables] has 0 rows after seeding.
  Future<void> seedAllData() async {
    final now = DateTime.utc(2026, 3, 18, 12);

    // ── Members ───────────────────────────────────────────────────────
    await db
        .into(db.members)
        .insert(
          MembersCompanion(
            id: const Value('member-1'),
            name: const Value('Alpha'),
            emoji: const Value('A'),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.members)
        .insert(
          MembersCompanion(
            id: const Value('member-2'),
            name: const Value('Beta'),
            emoji: const Value('B'),
            createdAt: Value(now),
          ),
        );

    // ── Fronting ──────────────────────────────────────────────────────
    await db
        .into(db.frontingSessions)
        .insert(
          FrontingSessionsCompanion(
            id: const Value('session-1'),
            startTime: Value(now.subtract(const Duration(hours: 1))),
            memberId: const Value('member-1'),
            // Per-member shape (Phase 5): no coFronterIds — co-fronting is
            // expressed as overlapping per-member rows.  The legacy column
            // still exists physically in v7, defaults to '[]'.
            sessionType: const Value(0),
          ),
        );
    // Co-fronter expressed as a second per-member row over the same range.
    await db
        .into(db.frontingSessions)
        .insert(
          FrontingSessionsCompanion(
            id: const Value('session-1-co'),
            startTime: Value(now.subtract(const Duration(hours: 1))),
            memberId: const Value('member-2'),
            sessionType: const Value(0),
          ),
        );
    await db
        .into(db.frontSessionComments)
        .insert(
          FrontSessionCommentsCompanion(
            id: const Value('comment-1'),
            sessionId: const Value('session-1'),
            body: const Value('felt good'),
            timestamp: Value(now),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.frontingSessions)
        .insert(
          FrontingSessionsCompanion(
            id: const Value('sleep-front-1'),
            startTime: Value(now.subtract(const Duration(hours: 8))),
            endTime: Value(now.subtract(const Duration(hours: 1))),
            memberId: const Value(null),
            sessionType: const Value(1),
          ),
        );
    await db
        .into(db.frontSessionComments)
        .insert(
          FrontSessionCommentsCompanion(
            id: const Value('comment-sleep-1'),
            sessionId: const Value('sleep-front-1'),
            body: const Value('slept well'),
            timestamp: Value(now),
            createdAt: Value(now),
          ),
        );

    // ── Chat ──────────────────────────────────────────────────────────
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion(
            id: const Value('conversation-1'),
            createdAt: Value(now),
            lastActivityAt: Value(now),
            title: const Value('General'),
            creatorId: const Value('member-1'),
            participantIds: const Value('["member-1","member-2"]'),
          ),
        );
    await db
        .into(db.chatMessages)
        .insert(
          ChatMessagesCompanion(
            id: const Value('message-1'),
            content: const Value('hello'),
            timestamp: Value(now),
            authorId: const Value('member-1'),
            conversationId: const Value('conversation-1'),
          ),
        );
    await db
        .into(db.conversationCategories)
        .insert(
          ConversationCategoriesCompanion(
            id: const Value('cat-1'),
            name: const Value('Important'),
            displayOrder: const Value(0),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

    // ── Polls ─────────────────────────────────────────────────────────
    await db
        .into(db.polls)
        .insert(
          PollsCompanion(
            id: const Value('poll-1'),
            question: const Value('Question?'),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.pollOptions)
        .insert(
          const PollOptionsCompanion(
            id: Value('option-1'),
            pollId: Value('poll-1'),
            optionText: Value('Yes'),
          ),
        );
    await db
        .into(db.pollVotes)
        .insert(
          PollVotesCompanion(
            id: const Value('vote-1'),
            pollOptionId: const Value('option-1'),
            memberId: const Value('member-1'),
            votedAt: Value(now),
          ),
        );

    // ── Sleep ─────────────────────────────────────────────────────────
    await db
        .into(db.sleepSessions)
        .insert(
          SleepSessionsCompanion(
            id: const Value('sleep-1'),
            startTime: Value(now.subtract(const Duration(hours: 8))),
            endTime: Value(now),
          ),
        );

    // ── Habits ────────────────────────────────────────────────────────
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion(
            id: const Value('habit-1'),
            name: const Value('Drink water'),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );
    await db
        .into(db.habitCompletions)
        .insert(
          HabitCompletionsCompanion(
            id: const Value('completion-1'),
            habitId: const Value('habit-1'),
            completedAt: Value(now),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

    // ── Member groups ─────────────────────────────────────────────────
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion(
            id: const Value('group-1'),
            name: const Value('Hosts'),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          const MemberGroupEntriesCompanion(
            id: Value('entry-1'),
            groupId: Value('group-1'),
            memberId: Value('member-1'),
          ),
        );
    await db
        .into(db.pkGroupSyncAliases)
        .insert(
          PkGroupSyncAliasesCompanion.insert(
            legacyEntityId: 'legacy-group-1',
            pkGroupUuid: 'pk-group-uuid-1',
            canonicalEntityId: 'pk-group:pk-group-uuid-1',
            createdAt: now,
          ),
        );
    await db
        .into(db.pkGroupEntryDeferredSyncOps)
        .insert(
          PkGroupEntryDeferredSyncOpsCompanion.insert(
            id: 'deferred-entry-1',
            entityType: 'member_group_entries',
            entityId: 'entry-1',
            fieldsJson: '{}',
            reason: 'missing_pk_refs',
            createdAt: now,
          ),
        );

    // ── Custom fields ─────────────────────────────────────────────────
    await db
        .into(db.customFields)
        .insert(
          CustomFieldsCompanion(
            id: const Value('field-1'),
            name: const Value('Age'),
            fieldType: const Value(0),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.customFieldValues)
        .insert(
          const CustomFieldValuesCompanion(
            id: Value('fval-1'),
            customFieldId: Value('field-1'),
            memberId: Value('member-1'),
            value: Value('25'),
          ),
        );

    // ── Notes ─────────────────────────────────────────────────────────
    await db
        .into(db.notes)
        .insert(
          NotesCompanion(
            id: const Value('note-1'),
            title: const Value('Hello'),
            body: const Value('World'),
            memberId: const Value('member-1'),
            date: Value(now),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

    // ── Reminders ─────────────────────────────────────────────────────
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion(
            id: const Value('reminder-1'),
            name: const Value('Check in'),
            message: const Value('How are you?'),
            trigger: const Value(0),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

    // ── Friends ───────────────────────────────────────────────────────
    await db
        .into(db.friends)
        .insert(
          FriendsCompanion(
            id: const Value('friend-1'),
            displayName: const Value('Ally'),
            publicKeyHex: const Value('aabbcc'),
            grantedScopes: const Value('[]'),
            createdAt: Value(now),
          ),
        );

    // ── Sharing requests ───────────────────────────────────────────────
    await db
        .into(db.sharingRequests)
        .insert(
          SharingRequestsCompanion(
            initId: const Value('req-1'),
            senderSharingId: const Value('sender-1'),
            displayName: const Value('Test Sender'),
            trustDecision: const Value('pending'),
            receivedAt: Value(now),
          ),
        );

    // ── Media attachments ─────────────────────────────────────────────
    await db
        .into(db.mediaAttachments)
        .insert(
          const MediaAttachmentsCompanion(
            id: Value('media-1'),
            messageId: Value('msg-1'),
            mediaType: Value('image'),
          ),
        );

    // ── System settings ───────────────────────────────────────────────
    await db
        .into(db.systemSettingsTable)
        .insert(
          const SystemSettingsTableCompanion(
            id: Value('singleton'),
            systemName: Value('Original System'),
            hasCompletedOnboarding: Value(true),
          ),
        );
    await db
        .into(db.pluralKitSyncState)
        .insert(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            systemId: const Value('pk-system'),
            isConnected: const Value(true),
            lastSyncDate: Value(now),
            lastManualSyncDate: Value(now),
          ),
        );
    await db
        .into(db.syncQuarantineTable)
        .insert(
          SyncQuarantineTableCompanion(
            id: const Value('quarantine-1'),
            entityType: const Value('members'),
            entityId: const Value('member-1'),
            expectedType: const Value('String'),
            receivedType: const Value('int'),
            createdAt: Value(now),
          ),
        );

    // ── SP sync state ─────────────────────────────────────────────────
    await db
        .into(db.spSyncStateTable)
        .insert(const SpSyncStateTableCompanion(id: Value('singleton')));
    await db
        .into(db.spIdMapTable)
        .insert(
          const SpIdMapTableCompanion(
            spId: Value('sp-member-1'),
            entityType: Value('member'),
            prismId: Value('member-1'),
          ),
        );

    // ── PK mapping state ──────────────────────────────────────────────
    await db
        .into(db.pkMappingState)
        .insert(
          PkMappingStateCompanion(
            id: const Value('link:pk-uuid-1'),
            decisionType: const Value('link'),
            pkMemberUuid: const Value('pk-uuid-1'),
            localMemberId: const Value('member-1'),
            status: const Value('pending'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // ── External state ────────────────────────────────────────────────
    // Seed a fake encrypted media cache file (mirrors what DownloadManager
    // writes at <appSupport>/prism_media/<mediaId>.enc).
    await mediaCacheDir.create(recursive: true);
    await File(
      p.join(mediaCacheDir.path, 'media-1.enc'),
    ).writeAsString('fake-ciphertext');

    await syncDbFile.writeAsString('sync-db');
    await syncWalFile.writeAsString('wal');
    await syncShmFile.writeAsString('shm');

    secureStore.seedSyncValue(
      'prism_sync.sync_id',
      base64Encode(utf8.encode('sync-123')),
    );
    secureStore.seedSyncValue(
      'prism_sync.device_id',
      base64Encode(utf8.encode('device-123')),
    );
    secureStore.seedSyncValue(
      'prism_sync.session_token',
      base64Encode(utf8.encode('session-123')),
    );
    secureStore.seedSyncValue(
      'prism_sync.runtime_dek',
      base64Encode(List<int>.generate(8, (index) => index)),
    );
    secureStore.seedSyncValue('prism_sync.runtime_dek_wrapped_v1', 'wrapped');
    secureStore.seedSyncValue('prism_pluralkit_token', 'pk-secret-token');
  }

  Future<void> reset(ResetCategory category) async {
    await container.read(resetDataNotifierProvider.notifier).reset(category);
  }

  Future<AppDatabase> reopenDatabase() async {
    await closePrimaryDb();
    return AppDatabase(NativeDatabase(appDbFile));
  }

  Future<void> closePrimaryDb() async {
    if (_disposed) return;
    container.dispose();
    await db.close();
    _disposed = true;
  }

  Future<void> dispose() async {
    if (!_disposed) {
      await closePrimaryDb();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _FakeResetSecureStore implements ResetSecureStore {
  final Map<String, String> _values = <String, String>{};
  bool throwOnReadAll = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    if (throwOnReadAll) {
      throw StateError('readAll failed');
    }
    return Map<String, String>.from(_values);
  }

  @override
  Future<void> deleteAll() async => _values.clear();

  void seedSyncValue(String key, String value) {
    _values[key] = value;
  }

  String? readSyncValue(String key) => _values[key];
}

Future<int> _countRows(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

Future<int> _countSleepRows(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM fronting_sessions WHERE session_type = 1',
      )
      .getSingle();
  return row.read<int>('c');
}

Future<int> _countFrontingRows(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM fronting_sessions WHERE session_type = 0',
      )
      .getSingle();
  return row.read<int>('c');
}

/// Minimal stand-in for the Rust `PrismSyncHandle` opaque type. The real
/// thing is a flutter_rust_bridge `RustOpaqueInterface` backed by an
/// `Arc<Mutex<PrismSync>>` — there's no way to construct one in pure-Dart
/// tests, so the reset path's FFI calls are routed through `ResetSyncFfi`
/// (see `_RecordingResetSyncFfi`) and the handle itself is just an opaque
/// token whose only job here is to be passed through and have `dispose()`
/// observed.
class _FakeSyncHandle implements ffi.PrismSyncHandle {
  bool _disposed = false;
  int disposeCount = 0;

  @override
  void dispose() {
    _disposed = true;
    disposeCount += 1;
  }

  @override
  bool get isDisposed => _disposed;
}

/// Records every FFI call the reset path makes, in order, so tests can
/// assert ordering invariants (e.g. setAutoSync(false) must be first).
class _RecordingResetSyncFfi implements ResetSyncFfi {
  final List<String> calls = <String>[];
  void Function()? onDispose;
  void Function(String syncId)? onClearSyncState;
  bool throwOnClearSyncState = false;

  @override
  Future<void> setAutoSync({
    required ffi.PrismSyncHandle handle,
    required bool enabled,
    required BigInt debounceMs,
    required BigInt retryDelayMs,
    required int maxRetries,
  }) async {
    calls.add('setAutoSync(enabled: $enabled)');
  }

  @override
  Future<void> deregisterDevice({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  }) async {
    calls.add('deregisterDevice');
  }

  @override
  Future<void> deleteSyncGroup({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required String deviceId,
    required String sessionToken,
  }) async {
    calls.add('deleteSyncGroup');
  }

  @override
  Future<void> clearSyncState({
    required ffi.PrismSyncHandle handle,
    required String syncId,
    required bool forceActive,
  }) async {
    calls.add('clearSyncState(syncId: $syncId, forceActive: $forceActive)');
    onClearSyncState?.call(syncId);
    if (throwOnClearSyncState) {
      throw StateError('clearSyncState failed');
    }
  }

  @override
  void disposeHandle(ffi.PrismSyncHandle handle) {
    calls.add('disposeHandle');
    handle.dispose();
    onDispose?.call();
  }
}
