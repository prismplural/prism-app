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
import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/reset/native_reset_keys.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart' as sync;
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart'
    as sp_importer;
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';

/// Every user-data table in the database. When a new table is added to the
/// Drift schema, add it here — the completeness guard test will fail if any
/// table is missing from the "All Data" reset.
const _allUserDataTables = [
  'app_preference_values',
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
  'member_board_posts',
  'member_profile_preference_values',
  'sp_sync_state',
  'sp_id_map',
  'pk_mapping_state',
];

// ── Member-ID orphan-reference manifest ────────────────────────────────────
// Every table.column pair that holds a member-identity reference (scalar or
// JSON) must appear here or in [_memberRefAllowlist].
//
// Columns in [_memberRefAllowlist] are intentional deferred gaps — they still
// orphan member IDs after _resetMembers but are accepted for now.  Each entry
// carries a TODO so they don't rot silently.
//
// The schema-coverage test will fail if a new column is added to the Drift
// schema whose name matches the member-ID pattern without being listed here.

enum _RefType {
  /// Column is UPDATE'd to [unknownSentinelMemberId].
  reAttributedToSentinel,

  /// Column is UPDATE'd to NULL.
  nulled,

  /// The parent row is DELETE'd entirely.
  deleted,

  /// Row is either deleted or column is nulled — both are acceptable outcomes.
  scalarOrDeleted,
}

class _MemberRef {
  const _MemberRef(this.table, this.column, this.type);

  final String table;
  final String column;
  final _RefType type;
}

const _memberRefColumns = <_MemberRef>[
  // fronting_sessions: normal rows re-attributed to the Unknown sentinel so
  // fronting history is preserved.
  _MemberRef('fronting_sessions', 'member_id', _RefType.reAttributedToSentinel),

  // chat_messages: author_id and the denormalized reply-author snapshot both
  // nulled so message text survives without dangling refs.
  _MemberRef('chat_messages', 'author_id', _RefType.nulled),
  _MemberRef('chat_messages', 'reply_to_author_id', _RefType.nulled),

  // conversations: creator nulled; JSON list/map columns cleared separately.
  _MemberRef('conversations', 'creator_id', _RefType.nulled),

  // habits: assignment cleared; habit definition itself survives.
  _MemberRef('habits', 'assigned_member_id', _RefType.nulled),

  // pk_mapping_state: local member ref nulled; PluralKit-side state survives.
  _MemberRef('pk_mapping_state', 'local_member_id', _RefType.nulled),

  // reminders: target cleared; reminder definition survives.
  _MemberRef('reminders', 'target_member_id', _RefType.nulled),

  // Per-member child data: fully deleted on reset.
  _MemberRef(
    'member_profile_preference_values',
    'member_id',
    _RefType.scalarOrDeleted,
  ),
  _MemberRef('member_group_entries', 'member_id', _RefType.deleted),
  _MemberRef('custom_field_values', 'member_id', _RefType.deleted),
  _MemberRef('notes', 'member_id', _RefType.deleted),
  _MemberRef('poll_votes', 'member_id', _RefType.deleted),
  _MemberRef(
    'habit_completions',
    'completed_by_member_id',
    _RefType.deleted,
  ),
  _MemberRef('member_board_posts', 'target_member_id', _RefType.deleted),
  _MemberRef('member_board_posts', 'author_id', _RefType.deleted),

  // media_attachments: bio images are per-member child data (member_id set
  // on creation). Deleted on member reset; chat media (empty member_id) is
  // preserved and handled by the chat/media reset path.
  _MemberRef('media_attachments', 'member_id', _RefType.deleted),
];

/// Columns whose name matches the member-ID pattern but which do not actually
/// reference local Prism member IDs. Excluded from the orphan check.
const _memberRefAllowlist = <(String, String)>{
  // PluralKit short IDs and UUIDs — reference PK entities, not local members.
  ('pk_mapping_state', 'pk_member_id'),
  ('pk_mapping_state', 'pk_member_uuid'),
  ('member_group_entries', 'pk_member_uuid'),
};

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

        expect(await _countRows(reopened, 'members'), 1);
        expect(await _countRows(reopened, 'poll_votes'), 0);
        expect(await _countRows(reopened, 'custom_field_values'), 0);
        expect(await _countRows(reopened, 'member_group_entries'), 0);
        expect(await _countRows(reopened, 'notes'), 0);
        expect(await _countRows(reopened, 'habit_completions'), 0);
        expect(await _countRows(reopened, 'member_board_posts'), 0);
        // Sessions preserved but member nulled.  Per-member shape: a
        // co-fronted seed expands to 2 normal rows + 1 sleep row = 3.
        expect(await _countRows(reopened, 'fronting_sessions'), 3);
        expect(await _countRows(reopened, 'chat_messages'), 1);
        // Groups and custom fields definitions remain
        expect(await _countRows(reopened, 'member_groups'), 1);
        expect(await _countRows(reopened, 'custom_fields'), 1);

        // Per-member shape: normal sessions remain valid by pointing at the
        // system-managed Unknown sentinel. Sleep rows still carry null.
        final normalRows = await reopened.customSelect('''
        SELECT member_id
        FROM fronting_sessions
        WHERE session_type = 0
        ''').get();
        expect(normalRows, hasLength(2));
        expect(
          normalRows.map((row) => row.data['member_id']),
          everyElement(unknownSentinelMemberId),
        );

        final sleepRow = await reopened
            .customSelect(
              '''
        SELECT member_id
        FROM fronting_sessions
        WHERE id = ?
        ''',
              variables: [Variable.withString('sleep-front-1')],
            )
            .getSingle();
        expect(sleepRow.data['member_id'], isNull);
      },
    );

    test(
      'members reset clears member_profile_preference_values',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        // Seed two preference rows: one for a regular member that will be
        // deleted, and one for the Unknown sentinel member. The sentinel is
        // inserted by _resetMembers itself (InsertOrIgnore), so we pre-insert
        // it here to simulate it having stale preferences.
        final db = harness.db;
        final now = DateTime.utc(2026, 3, 18, 12);
        await db
            .into(db.members)
            .insert(
              MembersCompanion(
                id: const Value('member-pref-1'),
                name: const Value('PrefMember'),
                emoji: const Value('P'),
                createdAt: Value(now),
              ),
            );
        await db
            .into(db.members)
            .insert(
              MembersCompanion(
                id: Value(unknownSentinelMemberId),
                name: const Value('Unknown'),
                emoji: const Value('❔'),
                createdAt: Value(now),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.memberProfilePreferenceValues)
            .insert(
              const MemberProfilePreferenceValuesCompanion(
                id: Value('mppv-regular'),
                memberId: Value('member-pref-1'),
                key: Value('profile.show_pronouns'),
                valueType: Value('bool'),
                valueJson: Value('true'),
              ),
            );
        await db
            .into(db.memberProfilePreferenceValues)
            .insert(
              MemberProfilePreferenceValuesCompanion(
                id: const Value('mppv-sentinel'),
                memberId: Value(unknownSentinelMemberId),
                key: const Value('profile.show_pronouns'),
                valueType: const Value('bool'),
                valueJson: const Value('false'),
              ),
            );

        await harness.reset(ResetCategory.members);

        final reopened = await harness.reopenDatabase();
        addTearDown(reopened.close);

        // Both rows are cleared — member_profile_preference_values has no FK
        // so a full DELETE FROM is the correct cleanup (no sentinel exemption).
        expect(
          await _countRows(reopened, 'member_profile_preference_values'),
          0,
          reason:
              'member_profile_preference_values must be emptied on members '
              'reset to prevent orphan rows when a member is re-created with '
              'the same ID',
        );
      },
    );

    test('members reset nulls out dangling member references', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      final db = harness.db;
      final now = DateTime.utc(2026, 3, 18, 12);

      // Seed members
      await db.into(db.members).insert(
        MembersCompanion(
          id: const Value('member-1'),
          name: const Value('Alpha'),
          emoji: const Value('A'),
          createdAt: Value(now),
        ),
      );
      await db.into(db.members).insert(
        MembersCompanion(
          id: const Value('member-2'),
          name: const Value('Beta'),
          emoji: const Value('B'),
          createdAt: Value(now),
        ),
      );

      // Seed a reminder with target_member_id
      await db.into(db.reminders).insert(
        RemindersCompanion(
          id: const Value('reminder-ref-1'),
          name: const Value('Switch reminder'),
          message: const Value('Hey'),
          trigger: const Value(0),
          targetMemberId: const Value('member-1'),
          createdAt: Value(now),
          modifiedAt: Value(now),
        ),
      );

      // Seed a habit with assigned_member_id
      await db.into(db.habits).insert(
        HabitsCompanion(
          id: const Value('habit-ref-1'),
          name: const Value('Drink water'),
          assignedMemberId: const Value('member-2'),
          createdAt: Value(now),
          modifiedAt: Value(now),
        ),
      );

      // Seed a conversation with creator_id and all JSON member-list columns
      await db.into(db.conversations).insert(
        ConversationsCompanion(
          id: const Value('conv-ref-1'),
          createdAt: Value(now),
          lastActivityAt: Value(now),
          creatorId: const Value('member-1'),
          participantIds: const Value('["member-1","member-2"]'),
          archivedByMemberIds: const Value('["member-1"]'),
          mutedByMemberIds: const Value('["member-2"]'),
          lastReadTimestamps: const Value('{"member-1":1000,"member-2":2000}'),
        ),
      );

      // Seed a chat message with author_id
      await db.into(db.chatMessages).insert(
        ChatMessagesCompanion(
          id: const Value('msg-ref-1'),
          content: const Value('hello'),
          timestamp: Value(now),
          authorId: const Value('member-1'),
          conversationId: const Value('conv-ref-1'),
        ),
      );

      await harness.reset(ResetCategory.members);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      // Scalar columns must be NULL
      final reminderRow = await reopened
          .customSelect(
            'SELECT target_member_id FROM reminders WHERE id = ?',
            variables: [Variable.withString('reminder-ref-1')],
          )
          .getSingle();
      expect(reminderRow.data['target_member_id'], isNull);

      final habitRow = await reopened
          .customSelect(
            'SELECT assigned_member_id FROM habits WHERE id = ?',
            variables: [Variable.withString('habit-ref-1')],
          )
          .getSingle();
      expect(habitRow.data['assigned_member_id'], isNull);

      final msgRow = await reopened
          .customSelect(
            'SELECT author_id FROM chat_messages WHERE id = ?',
            variables: [Variable.withString('msg-ref-1')],
          )
          .getSingle();
      expect(msgRow.data['author_id'], isNull);

      final convRow = await reopened
          .customSelect(
            'SELECT creator_id, participant_ids, archived_by_member_ids, '
            'muted_by_member_ids, last_read_timestamps '
            'FROM conversations WHERE id = ?',
            variables: [Variable.withString('conv-ref-1')],
          )
          .getSingle();
      expect(convRow.data['creator_id'], isNull);
      expect(convRow.data['participant_ids'], '[]');
      expect(convRow.data['archived_by_member_ids'], '[]');
      expect(convRow.data['muted_by_member_ids'], '[]');
      expect(convRow.data['last_read_timestamps'], '{}');

      // Rows themselves must still exist (UPDATE not DELETE)
      expect(await _countRows(reopened, 'reminders'), 1);
      expect(await _countRows(reopened, 'habits'), 1);
      expect(await _countRows(reopened, 'chat_messages'), 1);
      expect(await _countRows(reopened, 'conversations'), 1);
    });

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

    test('chat reset clears media_attachments + collects on-disk .enc files',
        () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      final db = harness.db;
      final now = DateTime.utc(2026, 3, 18, 12);

      // Seed a conversation + message so foreign-key-like references are
      // satisfied (no actual FK enforcement, but mirrors production shape).
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion(
              id: const Value('conv-media-1'),
              createdAt: Value(now),
              lastActivityAt: Value(now),
              title: const Value('Media Conv'),
              creatorId: const Value('member-media-1'),
              participantIds: const Value('[]'),
            ),
          );
      await db
          .into(db.chatMessages)
          .insert(
            ChatMessagesCompanion(
              id: const Value('msg-media-1'),
              content: const Value('has attachment'),
              timestamp: Value(now),
              authorId: const Value('member-media-1'),
              conversationId: const Value('conv-media-1'),
            ),
          );
      await db
          .into(db.mediaAttachments)
          .insert(
            const MediaAttachmentsCompanion(
              id: Value('att-1'),
              messageId: Value('msg-media-1'),
              mediaId: Value('media-file-abc'),
              mediaType: Value('image'),
            ),
          );

      // Seed the on-disk encrypted file that production code would have
      // written when the message was sent.
      await harness.mediaCacheDir.create(recursive: true);
      final encFile = File(
        p.join(harness.mediaCacheDir.path, 'media-file-abc.enc'),
      );
      await encFile.writeAsString('fake-ciphertext');
      expect(await encFile.exists(), isTrue);

      expect(await _countRows(db, 'media_attachments'), 1);

      await harness.reset(ResetCategory.chat);

      final reopened = await harness.reopenDatabase();
      addTearDown(reopened.close);

      expect(await _countRows(reopened, 'media_attachments'), 0,
          reason: 'chat reset must delete all media_attachments rows');
      expect(await _countRows(reopened, 'chat_messages'), 0);
      expect(await _countRows(reopened, 'conversations'), 0);
      expect(
        await encFile.exists(),
        isFalse,
        reason: 'chat reset must collect the on-disk .enc file for every '
            'media_attachments row it deletes',
      );
    });

    test(
      'chat reset captures media_ids inside the transaction '
      '(no SELECT-then-DELETE race window)',
      () async {
        // Regression for the chat-reset hygiene bug closed alongside the
        // 5cb9b6d9 custom-fields fix: the SELECT that captured media_ids ran
        // outside the transaction, so a sync-inbound `media_attachments` row
        // INSERTed between the SELECT and the bulk DELETE would be DB-deleted
        // (the DELETE is broad: `DELETE FROM media_attachments`) without its
        // `.enc` file ever being collected — permanent on-disk leak.
        //
        // Strategy: install a drift `QueryInterceptor` that records every
        // statement with a flag for whether it ran inside a transaction.
        // The structural invariant the fix guarantees is:
        //   the `SELECT media_id FROM media_attachments` MUST run inside
        //   the same transaction as the `DELETE FROM media_attachments`.
        // That single shared snapshot is what makes the .enc cleanup
        // race-free; verifying it directly is more robust than trying
        // to provoke an interleaved INSERT (the timing is fragile and
        // can be lock-serialized away in either direction).
        final tempDir = await Directory.systemTemp.createTemp(
          'prism-chat-reset-tx-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final appDbFile = File(p.join(tempDir.path, 'prism.db'));
        final mediaCacheDir = Directory(p.join(tempDir.path, 'prism_media'));

        final recorder = _RecordingTxInterceptor();
        final wrappedExecutor = NativeDatabase(appDbFile)
            .interceptWith(recorder);
        final db = AppDatabase(wrappedExecutor);
        addTearDown(db.close);

        final secureStore = _FakeResetSecureStore();
        final nativeResetKeys = _FakeNativeResetKeys();
        final downloadManager = DownloadManager(
          handle: null,
          encryption: MediaEncryptionService(),
          cacheDirOverride: mediaCacheDir,
        );

        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            systemSettingsRepositoryProvider.overrideWithValue(
              DriftSystemSettingsRepository(db.systemSettingsDao, null),
            ),
            resetSecureStoreProvider.overrideWithValue(secureStore),
            resetNativeKeysProvider.overrideWithValue(nativeResetKeys),
            resetDocumentsDirectoryProvider.overrideWith(
              (ref) async => tempDir,
            ),
            resetTemporaryDirectoryProvider.overrideWith(
              (ref) async => tempDir,
            ),
            resetMediaCacheDirectoryProvider.overrideWith(
              (ref) async => mediaCacheDir,
            ),
            resetSyncHandleProvider.overrideWithValue(null),
            downloadManagerProvider.overrideWithValue(downloadManager),
          ],
        );
        addTearDown(container.dispose);

        // Seed one media_attachments row + its .enc file so the file
        // cleanup loop has something to do (otherwise the post-reset
        // observable behavior is indistinguishable between fix and bug).
        final now = DateTime.utc(2026, 3, 18, 12);
        await db.into(db.conversations).insert(
              ConversationsCompanion(
                id: const Value('conv-tx'),
                createdAt: Value(now),
                lastActivityAt: Value(now),
                participantIds: const Value('[]'),
              ),
            );
        await db.into(db.chatMessages).insert(
              ChatMessagesCompanion(
                id: const Value('msg-tx-a'),
                content: const Value('a'),
                timestamp: Value(now),
                conversationId: const Value('conv-tx'),
              ),
            );
        await db.into(db.mediaAttachments).insert(
              const MediaAttachmentsCompanion(
                id: Value('att-tx-a'),
                messageId: Value('msg-tx-a'),
                mediaId: Value('media-tx-a'),
                mediaType: Value('image'),
              ),
            );
        await mediaCacheDir.create(recursive: true);
        await File(p.join(mediaCacheDir.path, 'media-tx-a.enc'))
            .writeAsString('cipher-a');

        // Clear recorder noise from seeding; only care about reset traffic.
        recorder.clear();

        await container.read(resetDataNotifierProvider.notifier).reset(
              ResetCategory.chat,
            );

        // Find every `SELECT media_id FROM media_attachments` statement
        // that ran during the reset, and confirm at least one ran inside a
        // transaction. Pre-fix, the only such SELECT runs at the top-level
        // executor (inTransaction == false), and this assertion fails.
        final mediaIdSelects = recorder.events
            .where((e) =>
                e.kind == _TxEventKind.runSelect &&
                e.sql.contains('SELECT media_id FROM media_attachments'))
            .toList();
        expect(
          mediaIdSelects,
          isNotEmpty,
          reason: 'chat reset should capture media_ids before deleting rows',
        );
        expect(
          mediaIdSelects.where((e) => e.inTransaction),
          isNotEmpty,
          reason: 'chat reset must run the media_id SELECT inside the same '
              'transaction as the bulk DELETE — otherwise a sync-inbound '
              'row INSERTed between SELECT and DELETE is DB-deleted but '
              'its .enc file is never collected (permanent on-disk leak). '
              'Recorded SELECTs: $mediaIdSelects',
        );

        // Sanity: the file-side effect (closing HIGH #6 end-to-end) — the
        // .enc file for the seeded row is gone after the reset.
        expect(
          await File(p.join(mediaCacheDir.path, 'media-tx-a.enc')).exists(),
          isFalse,
          reason: 'chat reset must collect the .enc file for every row '
              'it deletes from media_attachments',
        );
      },
    );

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

    test('custom fields reset tombstones all definitions and values', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await _seedCustomFields(harness.db, fieldCount: 3, valuesPerField: 2);
      await harness.reset(ResetCategory.customFields);

      expect(await _countRows(harness.db, 'custom_fields'), 3);
      expect(await _countRows(harness.db, 'custom_fields', activeOnly: true), 0);
      expect(
        await _countRows(harness.db, 'custom_field_values'),
        greaterThanOrEqualTo(5),
      );
      expect(
        await _countRows(harness.db, 'custom_field_values', activeOnly: true),
        0,
      );
    });

    test('custom fields reset is idempotent', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await _seedCustomFields(harness.db, fieldCount: 2, valuesPerField: 1);
      await harness.reset(ResetCategory.customFields);
      await harness.reset(ResetCategory.customFields);

      expect(
        await _countRows(harness.db, 'custom_fields', activeOnly: true),
        0,
      );
      expect(
        await _countRows(harness.db, 'custom_field_values', activeOnly: true),
        0,
      );
    });

    test('custom fields reset is a no-op when there are no fields', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.reset(ResetCategory.customFields);
      expect(
        harness.container.read(resetDataNotifierProvider),
        isA<AsyncData<void>>(),
      );
    });

    test(
      'custom fields reset after members reset does not crash on missing values',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        await _seedCustomFields(harness.db, fieldCount: 2, valuesPerField: 3);
        await harness.reset(ResetCategory.members);
        await harness.reset(ResetCategory.customFields);

        expect(
          await _countRows(harness.db, 'custom_fields', activeOnly: true),
          0,
        );
      },
    );

    test('custom fields reset notifies drift table updates', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await _seedCustomFields(harness.db, fieldCount: 1, valuesPerField: 1);
      final updates = <Set<String>>[];
      final sub = harness.db.tableUpdates().listen(
        (u) => updates.add(u.map((t) => t.table).toSet()),
      );
      await harness.reset(ResetCategory.customFields);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      final flat = updates.expand((s) => s).toSet();
      expect(flat, containsAll(['custom_fields', 'custom_field_values']));
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

    test(
      'sync reset clears stale unrecoverable startup probe for same-session setup',
      () async {
        final harness = await _ResetHarness.create(
          syncStartupReportOverride: const DbStartupReport(
            state: DbStartupState.unrecoverable,
            keyInMemory: null,
            usedRecoverySlot: null,
            diagnostic: null,
          ),
        );
        addTearDown(harness.dispose);

        expect(
          harness.container.read(sync.syncDatabaseStartupProvider).state,
          DbStartupState.unrecoverable,
        );

        await harness.reset(ResetCategory.sync);

        final report = harness.container.read(sync.syncDatabaseStartupProvider);
        expect(report.state, DbStartupState.ready);
        expect(report.keyInMemory, isNull);
        expect(report.usedRecoverySlot, 'fresh');
      },
    );

    test('sync reset records a local-only disconnect marker', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sync);

      final marker = await const SyncDisconnectMarkerStore()
          .readForCurrentInstall();
      expect(marker, isNotNull);
      expect(marker!.reason, SyncDisconnectReason.userDisconnect);
      expect(marker.previousSyncId, 'sync-123');
      expect(marker.previousDeviceId, 'device-123');
      expect(marker.localAppDataOutcome, LocalAppDataOutcome.preserved);
      expect(marker.nextSetupConstraint, SyncSetupConstraint.localOnly);
      expect(marker.setupMode, SyncSetupMode.localOnlyAfterDisconnect);
      expect(marker.completedAt, isNotNull);
      expect(
        marker.relayCleanupOutcome,
        RelayCleanupMarkerOutcome.skippedNoHandle,
      );
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

    test('sync reset invalidates cached device identity providers', () async {
      // Stateful platform-channel mock so the providers'
      // top-level `_storage` reads change between phases.
      final secureStorageState = <String, String?>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (MethodCall call) async {
              switch (call.method) {
                case 'read':
                  return secureStorageState[call.arguments['key'] as String];
                case 'write':
                  secureStorageState[call.arguments['key'] as String] =
                      call.arguments['value'] as String?;
                  return null;
                case 'delete':
                  secureStorageState.remove(call.arguments['key'] as String);
                  return null;
                case 'containsKey':
                  return secureStorageState.containsKey(
                    call.arguments['key'] as String,
                  );
                case 'readAll':
                  return Map<String, String>.from(
                    secureStorageState.map((k, v) => MapEntry(k, v ?? '')),
                  );
                case 'deleteAll':
                  secureStorageState.clear();
                  return null;
                default:
                  return null;
              }
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(
                'plugins.it_nomads.com/flutter_secure_storage',
              ),
              null,
            );
      });

      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      // Seed both the harness's reset-side store (so _resetSyncSystem has
      // something to wipe) and the platform channel (so the providers
      // themselves see "present" on first read).
      const seededDeviceId = 'device-cached';
      final encodedDeviceId = base64Encode(utf8.encode(seededDeviceId));
      harness.secureStore
        ..seedSyncValue('prism_sync.device_id', encodedDeviceId)
        ..seedSyncValue(
          'prism_sync.device_secret',
          base64Encode(utf8.encode('secret-cached')),
        )
        ..seedSyncValue('prism_sync.wrapped_dek', 'wrapped-cached');
      secureStorageState['prism_sync.device_id'] = encodedDeviceId;
      secureStorageState['prism_sync.device_secret'] = base64Encode(
        utf8.encode('secret-cached'),
      );
      secureStorageState['prism_sync.wrapped_dek'] = 'wrapped-cached';

      // Prime the FutureProviders so their cached values are "present".
      expect(
        await harness.container.read(sync.syncDeviceIdProvider.future),
        seededDeviceId,
      );
      expect(
        await harness.container.read(
          sync.syncDeviceSecretPresentProvider.future,
        ),
        isTrue,
      );
      expect(
        await harness.container.read(sync.syncWrappedDekPresentProvider.future),
        isTrue,
      );

      // Simulate keychain wipe at the platform layer (what reset would
      // produce if it actually ran against the platform plugin). The
      // harness's reset path operates on its own _FakeResetSecureStore,
      // so we mirror the wipe here to model the production effect.
      secureStorageState.remove('prism_sync.device_id');
      secureStorageState.remove('prism_sync.device_secret');
      secureStorageState.remove('prism_sync.wrapped_dek');

      // Run the reset. Without Block 1's invalidation, the providers
      // would still return their cached "present" values.
      await harness.reset(ResetCategory.sync);

      expect(
        await harness.container.read(sync.syncDeviceIdProvider.future),
        isNull,
        reason:
            'syncDeviceIdProvider must be invalidated by _resetSyncSystem '
            'so post-reset reads reflect the wiped keychain',
      );
      expect(
        await harness.container.read(
          sync.syncDeviceSecretPresentProvider.future,
        ),
        isFalse,
        reason:
            'syncDeviceSecretPresentProvider must be invalidated by '
            '_resetSyncSystem',
      );
      expect(
        await harness.container.read(sync.syncWrappedDekPresentProvider.future),
        isFalse,
        reason:
            'syncWrappedDekPresentProvider must be invalidated by '
            '_resetSyncSystem',
      );
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
          ..seedSyncValue(
            'prism_sync.runtime_dek_linux_wrap_key_v1',
            'WIPE_LINUX_WRAP_KEY',
          )
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
          harness.secureStore.readSyncValue(
            'prism_sync.runtime_dek_linux_wrap_key_v1',
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
        ..seedSyncValue('prism_sync.runtime_dek_linux_wrap_key_v1', 'L1')
        ..seedSyncValue('prism_sync.snapshot_apply_complete_v1', 'S1')
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
      expect(
        harness.secureStore.readSyncValue(
          'prism_sync.runtime_dek_linux_wrap_key_v1',
        ),
        isNull,
      );
      expect(
        harness.secureStore.readSyncValue(
          'prism_sync.snapshot_apply_complete_v1',
        ),
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
        ..seedSyncValue('prism_sync.runtime_dek_wrapped_v1', 'WIPE_WRAPPED')
        ..seedSyncValue(
          'prism_sync.runtime_dek_linux_wrap_key_v1',
          'WIPE_LINUX_WRAP_KEY',
        );

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
      expect(
        harness.secureStore.readSyncValue(
          'prism_sync.runtime_dek_linux_wrap_key_v1',
        ),
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

    test(
      'sync reset does not delete group after generic deregister failure',
      () async {
        // User-facing sync disconnect uses the conservative policy: only the
        // relay's last-active-device 403 should fall through to deleteSyncGroup.
        final fakeHandle = _FakeSyncHandle();
        final recordingFfi = _RecordingResetSyncFfi()
          ..throwOnDeregister = Exception('Network unreachable');

        final harness = await _ResetHarness.create(
          handleOverride: fakeHandle,
          ffiOverride: recordingFfi,
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

        await harness.reset(ResetCategory.sync);

        expect(
          recordingFfi.calls,
          contains('deregisterDevice'),
          reason: 'reset must always attempt deregister first',
        );
        expect(
          recordingFfi.calls,
          isNot(contains('deleteSyncGroup')),
          reason:
              'sync-only disconnect must not attempt deleteSyncGroup after a '
              'generic deregister failure',
        );
      },
    );

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

    test(
      'replace-by-pairing wipes local data and preserves a join-only marker',
      () async {
        final fakeHandle = _FakeSyncHandle();
        final recordingFfi = _RecordingResetSyncFfi()
          ..throwOnDeregister = Exception('Network unreachable');
        final harness = await _ResetHarness.create(
          handleOverride: fakeHandle,
          ffiOverride: recordingFfi,
          requiresRestartAfterPairingWipeOverride: false,
        );
        addTearDown(harness.dispose);

        await harness.seedAllData();
        await harness.replaceLocalDataAndPrepareForPairing();

        expect(recordingFfi.calls, contains('deregisterDevice'));
        expect(
          recordingFfi.calls,
          isNot(contains('deleteSyncGroup')),
          reason:
              'replace-by-pairing uses the same conservative relay cleanup as '
              'sync-only disconnect',
        );
        expect(await harness.appDbFile.exists(), isFalse);
        expect(await harness.syncDbFile.exists(), isFalse);
        expect(
          harness.secureStore.readSyncValue('prism_pluralkit_token'),
          isNull,
        );

        final marker = await const SyncDisconnectMarkerStore()
            .readForCurrentInstall();
        expect(marker, isNotNull);
        expect(marker!.reason, SyncDisconnectReason.replaceByPairing);
        expect(marker.previousSyncId, 'sync-123');
        expect(marker.localAppDataOutcome, LocalAppDataOutcome.wiped);
        expect(
          marker.nextSetupConstraint,
          SyncSetupConstraint.joinOnlyReplaceLocalData,
        );
        expect(marker.setupMode, SyncSetupMode.joinOnlyReplaceLocalData);
        expect(marker.completedAt, isNotNull);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
        expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
      },
    );

    test(
      'replace-by-pairing can require restart while preserving marker',
      () async {
        final harness = await _ResetHarness.create(
          requiresRestartAfterPairingWipeOverride: true,
        );
        addTearDown(harness.dispose);

        await harness.seedAllData();
        await harness.replaceLocalDataAndPrepareForPairing();

        final marker = await const SyncDisconnectMarkerStore()
            .readForCurrentInstall();
        expect(marker, isNotNull);
        expect(marker!.reason, SyncDisconnectReason.replaceByPairing);
        expect(
          marker.nextSetupConstraint,
          SyncSetupConstraint.joinOnlyReplaceLocalData,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
        expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
        expect(prefs.getString(kFullResetCompletedAtKey), isNotNull);
      },
    );

    test(
      'replace-by-pairing keeps a local-only marker if local wipe fails',
      () async {
        final harness = await _ResetHarness.create(
          deleteObserver: (path) {
            if (p.basename(path) == 'prism.db') {
              throw const FileSystemException('blocked by test');
            }
          },
          requiresRestartAfterPairingWipeOverride: false,
        );
        addTearDown(harness.dispose);

        await harness.seedAllData();

        await expectLater(
          harness.replaceLocalDataAndPrepareForPairing(),
          throwsA(isA<FullResetFailure>()),
        );

        final marker = await const SyncDisconnectMarkerStore()
            .readForCurrentInstall();
        expect(marker, isNotNull);
        expect(marker!.reason, SyncDisconnectReason.replaceByPairing);
        expect(marker.localAppDataOutcome, LocalAppDataOutcome.preserved);
        expect(marker.nextSetupConstraint, SyncSetupConstraint.localOnly);
        expect(marker.setupMode, SyncSetupMode.localOnlyAfterDisconnect);
      },
    );

    // ── Full reset ──────────────────────────────────────────────────

    test(
      'android full reset tears down sync before OS app-data clear',
      () async {
        final fakeHandle = _FakeSyncHandle();
        final recordingFfi = _RecordingResetSyncFfi();
        final orderLog = <String>[];
        recordingFfi.onDeregisterDevice = () => orderLog.add('deregister');
        recordingFfi.onDispose = () => orderLog.add('dispose');

        final harness = await _ResetHarness.create(
          handleOverride: fakeHandle,
          ffiOverride: recordingFfi,
          isAndroidOverride: true,
        );
        addTearDown(harness.dispose);
        harness.nativeResetKeys.onClearApplicationUserData = () {
          orderLog.add('clearApplicationUserData');
        };

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

        await harness.reset(ResetCategory.all);

        expect(recordingFfi.calls, contains('deregisterDevice'));
        expect(harness.nativeResetKeys.deleteKnownKeysCalls, 0);
        expect(harness.nativeResetKeys.clearApplicationUserDataCalls, 1);
        expect(
          orderLog.indexOf('deregister'),
          lessThan(orderLog.indexOf('clearApplicationUserData')),
          reason:
              'Android clearApplicationUserData kills the process after OS '
              'acceptance, so relay teardown must be attempted first',
        );
        expect(
          orderLog.indexOf('dispose'),
          lessThan(orderLog.indexOf('clearApplicationUserData')),
        );
      },
    );

    test('full reset keeps aggressive deleteSyncGroup fallback', () async {
      final fakeHandle = _FakeSyncHandle();
      final recordingFfi = _RecordingResetSyncFfi()
        ..throwOnDeregister = Exception('Network unreachable');

      final harness = await _ResetHarness.create(
        handleOverride: fakeHandle,
        ffiOverride: recordingFfi,
        isAndroidOverride: true,
      );
      addTearDown(harness.dispose);
      harness.nativeResetKeys.clearApplicationUserDataResult = false;

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

      await harness.reset(ResetCategory.all);

      expect(recordingFfi.calls, contains('deregisterDevice'));
      expect(
        recordingFfi.calls,
        contains('deleteSyncGroup'),
        reason:
            'full reset may use the aggressive cleanup fallback after a '
            'generic deregister failure',
      );
    });

    test(
      'full reset does not delete group when relay requires atomic revoke',
      () async {
        final fakeHandle = _FakeSyncHandle();
        final recordingFfi = _RecordingResetSyncFfi()
          ..throwOnDeregister = Exception(
            'HTTP 409: use_atomic_revoke; self-deregister with active peers '
            'requires atomic revoke',
          );

        final harness = await _ResetHarness.create(
          handleOverride: fakeHandle,
          ffiOverride: recordingFfi,
          isAndroidOverride: true,
        );
        addTearDown(harness.dispose);
        harness.nativeResetKeys.clearApplicationUserDataResult = false;

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

        await harness.reset(ResetCategory.all);

        expect(recordingFfi.calls, contains('deregisterDevice'));
        expect(
          recordingFfi.calls,
          isNot(contains('deleteSyncGroup')),
          reason:
              'atomic-revoke conflict means other devices still exist, so even '
              'full reset must not attempt destructive group deletion',
        );
      },
    );

    test('full reset removes any sync disconnect marker', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.reset(ResetCategory.sync);
      expect(
        await const SyncDisconnectMarkerStore().readForCurrentInstall(),
        isNotNull,
      );

      await harness.reset(ResetCategory.all);

      expect(
        await const SyncDisconnectMarkerStore().readForCurrentInstall(),
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kSyncDisconnectMarkerKey), isNull);
    });

    test(
      'android full reset falls back to local wipe when OS app-data clear is rejected',
      () async {
        final harness = await _ResetHarness.create(isAndroidOverride: true);
        addTearDown(harness.dispose);
        harness.nativeResetKeys.clearApplicationUserDataResult = false;

        await harness.seedAllData();
        await harness.reset(ResetCategory.all);

        expect(harness.nativeResetKeys.clearApplicationUserDataCalls, 1);
        expect(await harness.appDbFile.exists(), isFalse);
        expect(await harness.syncDbFile.exists(), isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
        expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
      },
    );

    test(
      'full reset clears every table, recreates default settings, and removes external state',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        await harness.seedAllData();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('prism.cache.theme_style', 'dreamy');
        await prefs.setBool('prism.pref.screen_privacy_enabled', true);
        await prefs.setBool('pk.auto_poll_enabled', true);
        await prefs.setInt('sync_pin.failed_attempts', 3);

        await harness.reset(ResetCategory.all);

        expect(await harness.appDbFile.exists(), isFalse);
        expect(harness.nativeResetKeys.deleteKnownKeysCalls, 1);
        expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
        expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
        expect(prefs.getString(kFullResetCompletedAtKey), isNotNull);
        expect(prefs.getString('prism.cache.theme_style'), 'dreamy');
        expect(prefs.getBool('prism.pref.screen_privacy_enabled'), isTrue);
        expect(prefs.getBool('pk.auto_poll_enabled'), isNull);
        expect(prefs.getInt('sync_pin.failed_attempts'), isNull);

        final reopened = await harness.reopenDatabase();
        addTearDown(reopened.close);
        await reopened.systemSettingsDao.getSettings();

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
      await reopened.systemSettingsDao.getSettings();

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

    test('full reset clears stale import and onboarding state', () async {
      SharedPreferences.setMockInitialValues({
        spImportCompletedPreferenceKey: true,
      });
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.container.read(importerProvider.notifier).verifyToken('');
      harness.container
          .read(onboardingProvider.notifier)
          .showImportedDataReady(const OnboardingDataCounts(members: 3));
      harness.container
          .read(onboardingPendingImportActionProvider.notifier)
          .set(() async {});

      expect(
        harness.container.read(importerProvider).step,
        sp_importer.ImportState.error,
      );
      expect(
        harness.container.read(onboardingProvider).currentStep,
        OnboardingStep.importedDataReady,
      );
      expect(
        harness.container.read(onboardingProvider).importedDataCounts?.members,
        3,
      );
      expect(
        harness.container.read(onboardingPendingImportActionProvider),
        isNotNull,
      );

      await harness.reset(ResetCategory.all);

      expect(
        harness.container.read(importerProvider).step,
        sp_importer.ImportState.idle,
      );
      expect(
        harness.container.read(onboardingProvider).currentStep,
        OnboardingStep.welcome,
      );
      expect(
        harness.container.read(onboardingProvider).importedDataCounts,
        isNull,
      );
      expect(harness.container.read(onboardingProvider).systemName, isEmpty);
      expect(
        harness.container.read(onboardingPendingImportActionProvider),
        isNull,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(spImportCompletedPreferenceKey), isNull);
    });

    test('full reset clears stale Simply Plural import state', () async {
      final harness = await _ResetHarness.create();
      addTearDown(harness.dispose);

      await harness.seedAllData();
      await harness.container.read(importerProvider.notifier).verifyToken('');
      harness.container
          .read(onboardingProvider.notifier)
          .setSystemName('Old import');
      harness.container
          .read(onboardingProvider.notifier)
          .setWasImportedFromSimplyPlural(
            true,
            conversationCount: 1,
            messageCount: 2,
          );
      harness.container
          .read(onboardingPendingImportActionProvider.notifier)
          .set(() async {});

      expect(
        harness.container.read(importerProvider).step,
        sp_importer.ImportState.error,
      );
      expect(
        harness.container.read(onboardingProvider).wasImportedFromSimplyPlural,
        isTrue,
      );
      expect(
        harness.container.read(onboardingPendingImportActionProvider),
        isNotNull,
      );

      await harness.reset(ResetCategory.all);

      expect(
        harness.container.read(importerProvider).step,
        sp_importer.ImportState.idle,
      );
      expect(
        harness.container.read(onboardingProvider).wasImportedFromSimplyPlural,
        isFalse,
      );
      expect(
        harness.container.read(onboardingPendingImportActionProvider),
        isNull,
      );
    });

    test(
      'full reset reopens production app database instead of leaving a deleted live handle',
      () async {
        final harness = await _ResetHarness.create(
          dynamicDatabaseProvider: true,
        );
        addTearDown(harness.dispose);

        await harness.seedAllData();
        await harness.reset(ResetCategory.all);

        final freshDb = harness.container.read(databaseProvider);
        await freshDb
            .into(freshDb.members)
            .insert(
              MembersCompanion(
                id: const Value('after-reset-member'),
                name: const Value('After Reset'),
                emoji: const Value('A'),
                createdAt: Value(DateTime.utc(2026, 5, 17)),
              ),
            );

        expect(await harness.appDbFile.exists(), isTrue);
        expect(await _countRows(freshDb, 'members'), 1);
      },
    );
  });

  // ── Member-ID orphan-reference invariants ───────────────────────────────
  // Two-part safety net:
  //   1. The schema-coverage test walks all Drift tables via introspection and
  //      fails if a column whose name matches a member-ID pattern is not listed
  //      in [_memberRefColumns] or [_memberRefAllowlist].  Add the column to
  //      the appropriate list — this forces every new member-ref column to be
  //      explicitly classified.
  //   2. The behaviour test seeds one row per entry in [_memberRefColumns],
  //      runs _resetMembers, and asserts that the column value was either
  //      deleted, nulled, or re-attributed to the Unknown sentinel.

  group('members reset orphan-reference invariants', () {
    test(
      'every member-ID column in the schema is covered by _memberRefColumns or _memberRefAllowlist',
      () {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        // Collect (table, column) pairs already listed in our manifest.
        final covered = {
          for (final ref in _memberRefColumns) (ref.table, ref.column),
        };

        // Pattern: column name that looks like a member-identity reference.
        // Exact names and suffix/regex patterns derived from the audit.
        const exactNames = {
          'member_id',
          'target_member_id',
          'assigned_member_id',
          'author_id',
          'creator_id',
          'completed_by_member_id',
          'local_member_id',
        };
        final memberSuffixRe = RegExp(
          r'^[a-z_]*member[_a-z]*id$',
          caseSensitive: false,
        );

        final uncovered = <String>[];
        for (final table in db.allTables) {
          final tableName = table.actualTableName;
          for (final col in table.$columns) {
            final colName = col.$name;
            final isMatch =
                exactNames.contains(colName) ||
                memberSuffixRe.hasMatch(colName);
            if (!isMatch) continue;
            if (_memberRefAllowlist.contains((tableName, colName))) continue;
            if (!covered.contains((tableName, colName))) {
              uncovered.add('$tableName.$colName');
            }
          }
        }

        expect(
          uncovered,
          isEmpty,
          reason:
              'The following member-ID columns are not listed in '
              '_memberRefColumns or _memberRefAllowlist.\n'
              'Add them to _memberRefColumns with the correct _RefType, OR '
              'to _memberRefAllowlist with a // TODO: comment explaining why '
              'they are deferred:\n'
              '${uncovered.join('\n')}',
        );
      },
    );

    test(
      'every column referencing members is wiped or nulled by _resetMembers',
      () async {
        final harness = await _ResetHarness.create();
        addTearDown(harness.dispose);

        final db = harness.db;
        final now = DateTime.utc(2026, 3, 18, 12);
        const victimId = 'member-victim';

        // Seed the victim member.
        await db.into(db.members).insert(
          MembersCompanion(
            id: const Value(victimId),
            name: const Value('Victim'),
            emoji: const Value('V'),
            createdAt: Value(now),
          ),
        );

        // Seed prerequisite rows needed to satisfy NOT NULL constraints for
        // some child tables.
        await db.into(db.conversations).insert(
          ConversationsCompanion(
            id: const Value('conv-orphan-1'),
            createdAt: Value(now),
            lastActivityAt: Value(now),
            participantIds: const Value('[]'),
          ),
        );
        await db.into(db.habits).insert(
          HabitsCompanion(
            id: const Value('habit-orphan-1'),
            name: const Value('Orphan habit'),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );
        await db.into(db.polls).insert(
          PollsCompanion(
            id: const Value('poll-orphan-1'),
            question: const Value('Q?'),
            createdAt: Value(now),
          ),
        );
        await db.into(db.pollOptions).insert(
          const PollOptionsCompanion(
            id: Value('opt-orphan-1'),
            pollId: Value('poll-orphan-1'),
            optionText: Value('Yes'),
          ),
        );
        await db.into(db.customFields).insert(
          CustomFieldsCompanion(
            id: const Value('field-orphan-1'),
            name: const Value('Field'),
            fieldType: const Value(0),
            createdAt: Value(now),
          ),
        );
        await db.into(db.memberGroups).insert(
          MemberGroupsCompanion(
            id: const Value('group-orphan-1'),
            name: const Value('Group'),
            createdAt: Value(now),
          ),
        );

        // Seed one row per _memberRefColumns entry.
        const rowId = 'orphan-row';

        // fronting_sessions.member_id
        await db.into(db.frontingSessions).insert(
          FrontingSessionsCompanion(
            id: const Value('$rowId-fronting'),
            startTime: Value(now),
            memberId: const Value(victimId),
            sessionType: const Value(0),
          ),
        );

        // chat_messages.author_id + reply_to_author_id (both nulled on reset).
        await db.into(db.chatMessages).insert(
          ChatMessagesCompanion(
            id: const Value('$rowId-chat-msg'),
            content: const Value('hello'),
            timestamp: Value(now),
            authorId: const Value(victimId),
            replyToAuthorId: const Value(victimId),
            conversationId: const Value('conv-orphan-1'),
          ),
        );

        // conversations.creator_id
        await db.into(db.conversations).insert(
          ConversationsCompanion(
            id: const Value('$rowId-conv'),
            createdAt: Value(now),
            lastActivityAt: Value(now),
            creatorId: const Value(victimId),
            participantIds: const Value('[]'),
          ),
        );

        // habits.assigned_member_id
        await db.into(db.habits).insert(
          HabitsCompanion(
            id: const Value('$rowId-habit'),
            name: const Value('Orphan habit 2'),
            assignedMemberId: const Value(victimId),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

        // reminders.target_member_id
        await db.into(db.reminders).insert(
          RemindersCompanion(
            id: const Value('$rowId-reminder'),
            name: const Value('Orphan reminder'),
            message: const Value('msg'),
            trigger: const Value(0),
            targetMemberId: const Value(victimId),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

        // pk_mapping_state.local_member_id
        await db.into(db.pkMappingState).insert(
          PkMappingStateCompanion(
            id: const Value('$rowId-pk-mapping'),
            decisionType: const Value('link'),
            localMemberId: const Value(victimId),
            pkMemberUuid: const Value('00000000-0000-0000-0000-000000000001'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        // JSON maps keyed by memberId — system_settings (singleton) and
        // plural_kit_sync_state are seeded with member-keyed JSON so the
        // post-reset assertions below can verify both are cleared.
        await db.into(db.systemSettingsTable).insert(
          const SystemSettingsTableCompanion(
            id: Value('singleton'),
            chatBadgePreferences: Value(
              '{"$victimId": "mentions_only"}',
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
        await db.into(db.pluralKitSyncState).insert(
          const PluralKitSyncStateCompanion(
            id: Value('pk_config'),
            fieldSyncConfig: Value(
              '{"$victimId": {"name": "push"}}',
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );

        // member_profile_preference_values.member_id
        await db.into(db.memberProfilePreferenceValues).insert(
          const MemberProfilePreferenceValuesCompanion(
            id: Value('$rowId-mppv'),
            memberId: Value(victimId),
            key: Value('profile.show_pronouns'),
            valueType: Value('bool'),
            valueJson: Value('true'),
          ),
        );

        // member_group_entries.member_id
        await db.into(db.memberGroupEntries).insert(
          const MemberGroupEntriesCompanion(
            id: Value('$rowId-group-entry'),
            groupId: Value('group-orphan-1'),
            memberId: Value(victimId),
          ),
        );

        // custom_field_values.member_id
        await db.into(db.customFieldValues).insert(
          const CustomFieldValuesCompanion(
            id: Value('$rowId-cfv'),
            customFieldId: Value('field-orphan-1'),
            memberId: Value(victimId),
            value: Value('42'),
          ),
        );

        // notes.member_id
        await db.into(db.notes).insert(
          NotesCompanion(
            id: const Value('$rowId-note'),
            title: const Value('Orphan note'),
            body: const Value('body'),
            memberId: const Value(victimId),
            date: Value(now),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

        // poll_votes.member_id
        await db.into(db.pollVotes).insert(
          PollVotesCompanion(
            id: const Value('$rowId-vote'),
            pollOptionId: const Value('opt-orphan-1'),
            memberId: const Value(victimId),
            votedAt: Value(now),
          ),
        );

        // habit_completions.completed_by_member_id
        await db.into(db.habitCompletions).insert(
          HabitCompletionsCompanion(
            id: const Value('$rowId-completion'),
            habitId: const Value('habit-orphan-1'),
            completedAt: Value(now),
            completedByMemberId: const Value(victimId),
            createdAt: Value(now),
            modifiedAt: Value(now),
          ),
        );

        // media_attachments.member_id (bio image attached to a member)
        await db.into(db.mediaAttachments).insert(
          const MediaAttachmentsCompanion(
            id: Value('$rowId-media_attachments'),
            mediaId: Value('$rowId-media-file'),
            mediaType: Value('image'),
            memberId: Value(victimId),
          ),
        );

        // member_board_posts.target_member_id
        // member_board_posts.author_id (seed both on one row)
        await db.into(db.memberBoardPosts).insert(
          MemberBoardPostsCompanion(
            id: const Value('$rowId-board-post'),
            targetMemberId: const Value(victimId),
            authorId: const Value(victimId),
            audience: const Value('public'),
            body: const Value('post body'),
            createdAt: Value(now),
            writtenAt: Value(now),
          ),
        );

        // Run _resetMembers via the public reset path.
        await harness.reset(ResetCategory.members);

        final reopened = await harness.reopenDatabase();
        addTearDown(reopened.close);

        // Helper: query a single nullable text column on a given table.
        Future<String?> colValue(String table, String col, String id) async {
          final rows = await reopened
              .customSelect(
                'SELECT $col FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .get();
          if (rows.isEmpty) return null; // row deleted — counts as "handled"
          return rows.single.data[col] as String?;
        }

        // Check each entry in _memberRefColumns.
        for (final ref in _memberRefColumns) {
          switch (ref.type) {
            case _RefType.reAttributedToSentinel:
              // Row must survive; column re-attributed to Unknown sentinel.
              final val = await colValue(
                ref.table,
                ref.column,
                '$rowId-${ref.table == 'fronting_sessions' ? 'fronting' : ref.table}',
              );
              expect(
                val,
                unknownSentinelMemberId,
                reason:
                    '${ref.table}.${ref.column} must be re-attributed to '
                    'the Unknown sentinel after members reset',
              );

            case _RefType.nulled:
              // Row must survive; column must be NULL.
              final String rowSuffix;
              if (ref.table == 'chat_messages') {
                rowSuffix = 'chat-msg';
              } else if (ref.table == 'conversations') {
                rowSuffix = 'conv';
              } else if (ref.table == 'habits') {
                rowSuffix = 'habit';
              } else if (ref.table == 'pk_mapping_state') {
                rowSuffix = 'pk-mapping';
              } else if (ref.table == 'reminders') {
                rowSuffix = 'reminder';
              } else {
                rowSuffix = ref.table;
              }
              final val = await colValue(ref.table, ref.column, '$rowId-$rowSuffix');
              expect(
                val,
                isNull,
                reason:
                    '${ref.table}.${ref.column} must be nulled after members reset',
              );

            case _RefType.deleted:
            case _RefType.scalarOrDeleted:
              // Row must be gone.
              final String rowSuffix;
              if (ref.table == 'member_profile_preference_values') {
                rowSuffix = 'mppv';
              } else if (ref.table == 'member_group_entries') {
                rowSuffix = 'group-entry';
              } else if (ref.table == 'custom_field_values') {
                rowSuffix = 'cfv';
              } else if (ref.table == 'poll_votes') {
                rowSuffix = 'vote';
              } else if (ref.table == 'habit_completions') {
                rowSuffix = 'completion';
              } else if (ref.table == 'notes') {
                rowSuffix = 'note';
              } else if (ref.table == 'member_board_posts') {
                rowSuffix = 'board-post';
              } else {
                rowSuffix = ref.table;
              }
              final rowCount = await reopened
                  .customSelect(
                    'SELECT COUNT(*) AS c FROM ${ref.table} WHERE id = ?',
                    variables: [Variable.withString('$rowId-$rowSuffix')],
                  )
                  .getSingle();
              expect(
                rowCount.data['c'],
                0,
                reason:
                    '${ref.table}.${ref.column}: row must be deleted after members reset',
              );
          }
        }

        // JSON list/map columns on conversations must be cleared.
        final convRow = await reopened
            .customSelect(
              'SELECT participant_ids, archived_by_member_ids, '
              'muted_by_member_ids, last_read_timestamps '
              'FROM conversations WHERE id = ?',
              variables: [Variable.withString('$rowId-conv')],
            )
            .getSingle();
        expect(
          convRow.data['participant_ids'],
          '[]',
          reason: 'conversations.participant_ids must be cleared',
        );
        expect(
          convRow.data['archived_by_member_ids'],
          '[]',
          reason: 'conversations.archived_by_member_ids must be cleared',
        );
        expect(
          convRow.data['muted_by_member_ids'],
          '[]',
          reason: 'conversations.muted_by_member_ids must be cleared',
        );
        expect(
          convRow.data['last_read_timestamps'],
          '{}',
          reason: 'conversations.last_read_timestamps must be cleared',
        );

        // JSON maps keyed by memberId — must no longer reference the victim.
        final settingsRow = await reopened
            .customSelect(
              'SELECT chat_badge_preferences FROM system_settings '
              'WHERE id = ?',
              variables: [Variable.withString('singleton')],
            )
            .getSingle();
        expect(
          settingsRow.data['chat_badge_preferences'],
          '{}',
          reason: 'system_settings.chat_badge_preferences must be cleared',
        );
        final pkSyncRow = await reopened
            .customSelect(
              'SELECT field_sync_config FROM plural_kit_sync_state '
              'WHERE id = ?',
              variables: [Variable.withString('pk_config')],
            )
            .getSingle();
        expect(
          pkSyncRow.data['field_sync_config'],
          isNull,
          reason: 'plural_kit_sync_state.field_sync_config must be cleared',
        );
      },
    );
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
    required this.nativeResetKeys,
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
  final _FakeNativeResetKeys nativeResetKeys;

  bool _disposed = false;

  static Future<_ResetHarness> create({
    ffi.PrismSyncHandle? handleOverride,
    ResetSyncFfi? ffiOverride,
    ResetFileDeleteObserver? deleteObserver,
    DbStartupReport? syncStartupReportOverride,
    bool dynamicDatabaseProvider = false,
    bool? isAndroidOverride,
    bool? requiresRestartAfterPairingWipeOverride,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('prism-reset-test-');
    final appDbFile = File(p.join(tempDir.path, 'prism.db'));
    final syncDbFile = File(p.join(tempDir.path, 'prism_sync.db'));
    final syncWalFile = File('${syncDbFile.path}-wal');
    final syncShmFile = File('${syncDbFile.path}-shm');
    final mediaCacheDir = Directory(p.join(tempDir.path, 'prism_media'));

    final secureStore = _FakeResetSecureStore();
    final nativeResetKeys = _FakeNativeResetKeys();
    final db = dynamicDatabaseProvider
        ? null
        : AppDatabase(NativeDatabase(appDbFile));
    final systemSettingsRepository = db == null
        ? null
        : DriftSystemSettingsRepository(db.systemSettingsDao, null);

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
        if (dynamicDatabaseProvider)
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase(appDbFile));
            ref.onDispose(db.close);
            return db;
          })
        else
          databaseProvider.overrideWithValue(db!),
        if (systemSettingsRepository != null)
          systemSettingsRepositoryProvider.overrideWithValue(
            systemSettingsRepository,
          ),
        resetSecureStoreProvider.overrideWithValue(secureStore),
        resetNativeKeysProvider.overrideWithValue(nativeResetKeys),
        resetDocumentsDirectoryProvider.overrideWith((ref) async => tempDir),
        resetTemporaryDirectoryProvider.overrideWith((ref) async => tempDir),
        resetMediaCacheDirectoryProvider.overrideWith(
          (ref) async => mediaCacheDir,
        ),
        resetSyncHandleProvider.overrideWithValue(handleOverride),
        if (syncStartupReportOverride != null)
          sync.syncDatabaseStartupReportStateProvider.overrideWith(
            () => sync.SyncDatabaseStartupReportNotifier(
              syncStartupReportOverride,
            ),
          ),
        if (isAndroidOverride != null)
          resetIsAndroidProvider.overrideWithValue(isAndroidOverride),
        if (requiresRestartAfterPairingWipeOverride != null)
          resetRequiresRestartAfterLocalPairingWipeProvider.overrideWithValue(
            requiresRestartAfterPairingWipeOverride,
          ),
        downloadManagerProvider.overrideWithValue(downloadManager),
        if (ffiOverride != null)
          resetSyncFfiProvider.overrideWithValue(ffiOverride),
        if (deleteObserver != null)
          resetFileDeleteObserverProvider.overrideWithValue(deleteObserver),
      ],
    );
    final AppDatabase resolvedDb = db ?? container.read(databaseProvider);

    return _ResetHarness._(
      tempDir: tempDir,
      appDbFile: appDbFile,
      syncDbFile: syncDbFile,
      syncWalFile: syncWalFile,
      syncShmFile: syncShmFile,
      mediaCacheDir: mediaCacheDir,
      db: resolvedDb,
      container: container,
      secureStore: secureStore,
      nativeResetKeys: nativeResetKeys,
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

    // ── Member board posts ────────────────────────────────────────────
    await db
        .into(db.memberBoardPosts)
        .insert(
          MemberBoardPostsCompanion(
            id: const Value('board-post-1'),
            targetMemberId: const Value('member-1'),
            authorId: const Value('member-2'),
            audience: const Value('public'),
            body: const Value('seed body'),
            createdAt: Value(now),
            writtenAt: Value(now),
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

    // ── Member profile preference values ──────────────────────────────
    await db
        .into(db.memberProfilePreferenceValues)
        .insert(
          const MemberProfilePreferenceValuesCompanion(
            id: Value('mppv-1'),
            memberId: Value('member-1'),
            key: Value('profile.show_pronouns'),
            valueType: Value('bool'),
            valueJson: Value('true'),
          ),
        );

    // ── App preference values ─────────────────────────────────────────
    await db
        .into(db.appPreferenceValues)
        .insert(
          const AppPreferenceValuesCompanion(
            key: Value('theme.accent'),
            valueType: Value('string'),
            valueJson: Value('"violet"'),
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
    secureStore.seedSyncValue(
      'prism_sync.runtime_dek_linux_wrap_key_v1',
      'linux-wrap-key',
    );
    secureStore.seedSyncValue('prism_pluralkit_token', 'pk-secret-token');
  }

  Future<void> reset(ResetCategory category) async {
    await container.read(resetDataNotifierProvider.notifier).reset(category);
    final resetState = container.read(resetDataNotifierProvider);
    if (resetState.hasError) {
      Error.throwWithStackTrace(resetState.error!, resetState.stackTrace!);
    }
  }

  Future<void> replaceLocalDataAndPrepareForPairing() async {
    await container
        .read(resetDataNotifierProvider.notifier)
        .replaceLocalDataAndPrepareForPairing();
    final resetState = container.read(resetDataNotifierProvider);
    if (resetState.hasError) {
      Error.throwWithStackTrace(resetState.error!, resetState.stackTrace!);
    }
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

class _FakeNativeResetKeys implements NativeResetKeys {
  int deleteKnownKeysCalls = 0;
  int clearApplicationUserDataCalls = 0;
  bool hasKeys = false;
  bool clearApplicationUserDataResult = true;
  void Function()? onDeleteKnownKeys;
  void Function()? onClearApplicationUserData;

  @override
  Future<void> deleteKnownKeys({bool force = false}) async {
    deleteKnownKeysCalls += 1;
    onDeleteKnownKeys?.call();
    hasKeys = false;
  }

  @override
  Future<bool> hasKnownNativeKeys() async => hasKeys;

  @override
  Future<bool> clearApplicationUserData() async {
    clearApplicationUserDataCalls += 1;
    onClearApplicationUserData?.call();
    return clearApplicationUserDataResult;
  }
}

Future<int> _countRows(
  AppDatabase db,
  String table, {
  bool activeOnly = false,
}) async {
  final where = activeOnly ? ' WHERE is_deleted = 0' : '';
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table$where')
      .getSingle();
  return row.read<int>('c');
}

Future<void> _seedCustomFields(
  AppDatabase db, {
  required int fieldCount,
  required int valuesPerField,
}) async {
  final now = DateTime.utc(2026, 3, 18, 12);
  for (var i = 0; i < fieldCount; i++) {
    final fieldId = 'cf-$i';
    await db.into(db.customFields).insert(
      CustomFieldsCompanion(
        id: Value(fieldId),
        name: Value('field-$i'),
        fieldType: const Value(0),
        createdAt: Value(now),
      ),
    );
    for (var j = 0; j < valuesPerField; j++) {
      await db.into(db.customFieldValues).insert(
        CustomFieldValuesCompanion(
          id: Value('cfv-$i-$j'),
          customFieldId: Value(fieldId),
          memberId: Value('member-$i-$j'),
          value: Value('v-$i-$j'),
        ),
      );
    }
  }
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
  void Function()? onDeregisterDevice;
  void Function()? onDispose;
  void Function(String syncId)? onClearSyncState;
  bool throwOnClearSyncState = false;
  Object? throwOnDeregister;

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
    onDeregisterDevice?.call();
    if (throwOnDeregister != null) {
      throw throwOnDeregister!;
    }
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

enum _TxEventKind { runSelect, runCustom, beginTx, commitTx, rollbackTx }

class _TxEvent {
  _TxEvent({
    required this.kind,
    required this.sql,
    required this.inTransaction,
  });

  final _TxEventKind kind;
  final String sql;
  final bool inTransaction;

  @override
  String toString() =>
      '_TxEvent(kind=$kind, inTx=$inTransaction, sql=${sql.substring(0, sql.length.clamp(0, 80))})';
}

/// Records every drift operation with a flag for whether it ran inside a
/// transaction. Used by the chat-reset regression test to assert the
/// `SELECT media_id FROM media_attachments` is bracketed by a `BEGIN`/
/// `COMMIT` pair — the snapshot invariant that closes the
/// SELECT-then-DELETE race.
class _RecordingTxInterceptor extends QueryInterceptor {
  final List<_TxEvent> events = <_TxEvent>[];
  int _depth = 0;

  void clear() => events.clear();

  bool get _inTx => _depth > 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _depth += 1;
    events.add(
      _TxEvent(kind: _TxEventKind.beginTx, sql: 'BEGIN', inTransaction: _inTx),
    );
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    events.add(
      _TxEvent(
        kind: _TxEventKind.commitTx,
        sql: 'COMMIT',
        inTransaction: _inTx,
      ),
    );
    _depth -= 1;
    return super.commitTransaction(inner);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    events.add(
      _TxEvent(
        kind: _TxEventKind.rollbackTx,
        sql: 'ROLLBACK',
        inTransaction: _inTx,
      ),
    );
    _depth -= 1;
    return super.rollbackTransaction(inner);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    events.add(
      _TxEvent(
        kind: _TxEventKind.runSelect,
        sql: statement,
        inTransaction: _inTx,
      ),
    );
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    events.add(
      _TxEvent(
        kind: _TxEventKind.runCustom,
        sql: statement,
        inTransaction: _inTx,
      ),
    );
    return super.runCustom(executor, statement, args);
  }
}
