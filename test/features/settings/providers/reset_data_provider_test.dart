import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';

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
        // Sessions preserved but member nulled
        expect(await _countRows(reopened, 'fronting_sessions'), 2);
        expect(await _countRows(reopened, 'chat_messages'), 1);
        // Groups and custom fields definitions remain
        expect(await _countRows(reopened, 'member_groups'), 1);
        expect(await _countRows(reopened, 'custom_fields'), 1);

        final sessionRow = await reopened
            .customSelect(
              '''
        SELECT member_id, co_fronter_ids
        FROM fronting_sessions
        WHERE id = ?
        ''',
              variables: [Variable.withString('session-1')],
            )
            .getSingle();
        expect(sessionRow.data['member_id'], isNull);
        expect(sessionRow.read<String>('co_fronter_ids'), '[]');
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
      expect(await _countRows(reopened, 'fronting_sessions'), 1);
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

    test('sync reset deletes dynamic epoch_key_* and runtime_keys_* entries',
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

  static Future<_ResetHarness> create() async {
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
        resetSyncHandleProvider.overrideWithValue(null),
        downloadManagerProvider.overrideWithValue(downloadManager),
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
            coFronterIds: const Value('["member-2"]'),
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
            coFronterIds: const Value('[]'),
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
        .insert(
          const SpSyncStateTableCompanion(
            id: Value('singleton'),
          ),
        );
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
    await db.into(db.pkMappingState).insert(
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
    await File(p.join(mediaCacheDir.path, 'media-1.enc')).writeAsString(
      'fake-ciphertext',
    );

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

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(_values);

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
