/// Phase 5B migration service tests.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §4.1 + §4.2.
///
/// Pin every documented branch:
///   - Solo upgradeAndKeep with mixed PK/SP/native single/native multi/orphan.
///   - Solo startFresh (everything wiped, no sentinel created).
///   - Comments preserved on SP/native parents, deleted on PK parents,
///     anchored at the LEGACY `timestamp` (not createdAt).
///   - Corrupt co_fronter_ids JSON falls back to single-member migration.
///   - Secondary mode skips per-row work and truncates fronting tables.
///   - Failure mid-transaction rolls back; settings stays at notStarted;
///     PRISM1 file from step 2 survives on disk.
///   - Native multi-member fan-out: deterministic v5 ids match the
///     migration namespace, primary keeps the legacy id.
///   - Sentinel idempotency: rerunning migration doesn't duplicate.
///   - Sync state reset: Rust FFI is invoked exactly once.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Member, FrontingSession;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/utils/time_range.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart' show Member;
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Directory _tempCacheDir() =>
    Directory.systemTemp.createTempSync('prism-mig-test-');

DataExportService _makeExportService(AppDatabase db, Directory cacheDir) {
  return DataExportService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    conversationRepository: DriftConversationRepository(
      db.conversationsDao,
      null,
    ),
    chatMessageRepository: DriftChatMessageRepository(db.chatMessagesDao, null),
    pollRepository: DriftPollRepository(
      db.pollsDao,
      db.pollOptionsDao,
      db.pollVotesDao,
      null,
    ),
    systemSettingsRepository: DriftSystemSettingsRepository(
      db.systemSettingsDao,
      null,
    ),
    habitRepository: DriftHabitRepository(db.habitsDao, null),
    pluralKitSyncDao: db.pluralKitSyncDao,
    memberGroupsRepository: DriftMemberGroupsRepository(
      db.memberGroupsDao,
      null,
    ),
    customFieldsRepository: DriftCustomFieldsRepository(
      db.customFieldsDao,
      null,
    ),
    notesRepository: DriftNotesRepository(db.notesDao, null),
    frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
      db.frontSessionCommentsDao,
      null,
    ),
    conversationCategoriesRepository: DriftConversationCategoriesRepository(
      db.conversationCategoriesDao,
      null,
    ),
    remindersRepository: DriftRemindersRepository(db.remindersDao, null),
    friendsRepository: DriftFriendsRepository(db.friendsDao, null),
    mediaAttachmentsDao: db.mediaAttachmentsDao,
    cacheDirectoryProvider: () async => cacheDir,
    appSupportDirectoryProvider: () async => cacheDir,
  );
}

/// Builds a service wired to in-memory Drift + a mock resetSyncState.
///
/// The Rust FFI handle is null by default - the service skips the real
/// reset call when [syncHandle] is null.  The mock callback also runs
/// in that mode so tests can record whether the FFI branch *would*
/// have run; tests that need to assert "FFI invoked" pass an explicit
/// `_FakePrismSyncHandle` when constructing the service.
FrontingMigrationService _makeService(
  AppDatabase db,
  DataExportService exportService, {
  List<ffi.PrismSyncHandle>? resetCalls,
  Directory? backupDirectory,
}) {
  // Avoid the platform-channel hop into getApplicationDocumentsDirectory
  // in unit tests by defaulting the backup dir to a temp dir.
  final dir =
      backupDirectory ??
      Directory.systemTemp.createTempSync('prism-mig-backup-');
  return FrontingMigrationService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
      db.frontSessionCommentsDao,
      null,
    ),
    dataExportService: exportService,
    syncHandle: null,
    resetSyncState: (h) async {
      resetCalls?.add(h);
    },
    backupDirectoryProvider: () async => dir,
  );
}

Future<Uri?> _noopShare(File f) async => Uri.file(f.path);

Future<void> _seedSession(
  AppDatabase db, {
  required String id,
  required DateTime startTime,
  DateTime? endTime,
  String? memberId,
  String coFronterIds = '[]',
  String? pluralkitUuid,
  int sessionType = 0,
}) async {
  await db
      .into(db.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: id,
          startTime: startTime,
          endTime: drift.Value(endTime),
          memberId: drift.Value(memberId),
          coFronterIds: drift.Value(coFronterIds),
          pluralkitUuid: drift.Value(pluralkitUuid),
          sessionType: drift.Value(sessionType),
        ),
      );
}

Future<void> _seedComment(
  AppDatabase db, {
  required String id,
  required String sessionId,
  required String body,
  required DateTime timestamp,
}) async {
  await db
      .into(db.frontSessionComments)
      .insert(
        FrontSessionCommentsCompanion.insert(
          id: id,
          sessionId: sessionId,
          body: body,
          timestamp: timestamp,
          createdAt: timestamp,
        ),
      );
}

Future<void> _seedSpMapping(
  AppDatabase db,
  String prismId, {
  String spId = 'sp-source-id',
}) async {
  await db.spImportDao.upsertMapping(
    SpIdMapTableCompanion.insert(
      spId: spId,
      entityType: 'session',
      prismId: prismId,
    ),
  );
}

Future<void> _seedMember(AppDatabase db, String id, {String name = 'M'}) async {
  final repo = DriftMemberRepository(db.membersDao, null);
  await repo.createMember(
    Member(
      id: id,
      name: name,
      emoji: 'M',
      createdAt: DateTime(2026, 1, 1).toUtc(),
    ),
  );
}

PluralKitSyncService _makePkImportService(
  AppDatabase db,
  PluralKitClient client,
) {
  final memberRepo = DriftMemberRepository(
    db.membersDao,
    null,
    pkSyncDao: db.pluralKitSyncDao,
  );
  return PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
      pkSyncDao: db.pluralKitSyncDao,
    ),
    syncDao: db.pluralKitSyncDao,
    tokenOverride: 'test-token',
    clientFactory: (_) => client,
    groupsImporter: PkGroupsImporter(db: db, memberRepository: memberRepo),
  );
}

class _PkMigrationFakeClient implements PluralKitClient {
  _PkMigrationFakeClient({
    required this.members,
    required this.switchesNewestFirst,
  });

  final List<PKMember> members;
  final List<PKSwitch> switchesNewestFirst;

  int getSystemCallCount = 0;
  int getMembersCallCount = 0;
  int getSwitchesCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<PKSystem> getSystem() async {
    getSystemCallCount++;
    return const PKSystem(id: 'pk-system', name: 'PK Fixture System');
  }

  @override
  Future<List<PKMember>> getMembers() async {
    getMembersCallCount++;
    return members;
  }

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    getSwitchesCallCount++;
    return before == null ? switchesNewestFirst : const <PKSwitch>[];
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async =>
      const <PKGroup>[];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async =>
      const <String>[];

  @override
  Future<List<int>> downloadBytes(String url) async => const <int>[];

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  void dispose() {
    disposeCallCount++;
  }
}

void main() {
  group('FrontingMigrationService', () {
    late AppDatabase db;
    late Directory cacheDir;
    late DataExportService exportService;

    setUp(() {
      db = _makeDb();
      cacheDir = _tempCacheDir();
      exportService = _makeExportService(db, cacheDir);
    });

    tearDown(() async {
      await db.close();
      try {
        await cacheDir.delete(recursive: true);
      } catch (_) {}
    });

    // -------------------------------------------------------------------
    // PRISM1 export wiring - DataExportService must receive `db`
    // (Regression: #1 regression).
    //
    // The migration calls dataExportService.exportEncryptedData with
    // includeLegacyFields: true. Without `db` wired the legacy column
    // reads silently no-op and the resulting PRISM1 file omits every
    // co_fronter_ids / pk_member_ids_json / session_id field - making
    // the rescue file unable to reconstruct the per-member fan-out on
    // re-import. The fix made `db` a required constructor argument so
    // the broken provider path won't compile.
    // -------------------------------------------------------------------
    test('PRISM1 migration export carries legacy fields end-to-end '
        '(co_fronter_ids, pk_member_ids_json, comment session_id)', () async {
      // Seed a multi-member native row with co-fronters in the v7
      // legacy column, and a comment with a session_id pointing at it.
      await _seedMember(db, 'primary');
      await _seedMember(db, 'co-1');
      await _seedSession(
        db,
        id: 'native-multi',
        startTime: DateTime.utc(2026, 4, 1, 9),
        endTime: DateTime.utc(2026, 4, 1, 11),
        memberId: 'primary',
        coFronterIds: jsonEncode(['co-1']),
      );
      await _seedComment(
        db,
        id: 'c-1',
        sessionId: 'native-multi',
        body: 'still good',
        timestamp: DateTime.utc(2026, 4, 1, 10),
      );

      // Build the export through the same code path the migration
      // service uses. The legacy fields MUST be present in the JSON.
      final export = await exportService.buildExport(includeLegacyFields: true);
      final json =
          jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>;

      final sessions = json['frontSessions'] as List<dynamic>;
      final session =
          sessions.firstWhere(
                (s) => (s as Map<String, dynamic>)['id'] == 'native-multi',
              )
              as Map<String, dynamic>;
      expect(
        session['coFronterIds'],
        ['co-1'],
        reason: 'co_fronter_ids must round-trip through the export',
      );

      final comments = json['frontSessionComments'] as List<dynamic>;
      final comment =
          comments.firstWhere((c) => (c as Map<String, dynamic>)['id'] == 'c-1')
              as Map<String, dynamic>;
      expect(
        comment['sessionId'],
        'native-multi',
        reason: 'comment.session_id must round-trip through the export',
      );
    });

    // -------------------------------------------------------------------
    // prepareBackup writes to the injected directory
    //
    // The split between prepareBackup + runMigrationDestructive lets the
    // upgrade modal gate the destructive phase on the user actually
    // saving the rescue file. Here we just pin that prepareBackup
    // produces a non-null File in the directory we provided, so the
    // upgrade modal can hand that path to the share / save-as actions.
    // -------------------------------------------------------------------
    test('prepareBackup writes the PRISM1 file to the injected backup '
        'directory and returns a non-null File', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      final backupDir = Directory.systemTemp.createTempSync(
        'prism-mig-backup-prep-',
      );
      final svc = _makeService(db, exportService, backupDirectory: backupDir);

      final file = await svc.prepareBackup(
        mode: MigrationMode.upgradeAndKeep,
        password: 'a-strong-password-12',
      );

      expect(await file.exists(), isTrue);
      expect(file.path, startsWith(backupDir.path));
      // Migration mode untouched - prepareBackup is non-destructive.
      // Default initial value depends on migration onUpgrade; we just
      // assert it's not the in-progress sentinel.
      final mode = await db.systemSettingsDao
          .readPendingFrontingMigrationMode();
      expect(mode, isNot(FrontingMigrationService.modeInProgress));

      try {
        await backupDir.delete(recursive: true);
      } catch (_) {}
    });

    // -------------------------------------------------------------------
    // Solo upgradeAndKeep - mixed data
    // -------------------------------------------------------------------
    test(
      'solo upgradeAndKeep with mixed PK/SP/native rows: PK deleted, SP/'
      'native preserved with v2 ops, multi-member fanned out, orphan gets sentinel',
      () async {
        const primaryId = 'primary-m';
        const coId = 'co-m';
        const spMemberId = 'sp-m';
        const pkMemberId = 'pk-m';
        for (final id in [primaryId, coId, spMemberId, pkMemberId]) {
          await _seedMember(db, id, name: id);
        }

        // PK row (will be deleted)
        await _seedSession(
          db,
          id: 'pk-1',
          startTime: DateTime(2026, 4, 1, 9).toUtc(),
          endTime: DateTime(2026, 4, 1, 10).toUtc(),
          memberId: pkMemberId,
          pluralkitUuid: '11111111-1111-4111-8111-111111111111',
        );
        // SP row (migrated in place)
        await _seedSession(
          db,
          id: 'sp-1',
          startTime: DateTime(2026, 4, 1, 11).toUtc(),
          endTime: DateTime(2026, 4, 1, 12).toUtc(),
          memberId: spMemberId,
        );
        await _seedSpMapping(db, 'sp-1', spId: 'sp-source-1');
        // Native single-member row (migrated in place)
        await _seedSession(
          db,
          id: 'native-1',
          startTime: DateTime(2026, 4, 1, 13).toUtc(),
          endTime: DateTime(2026, 4, 1, 14).toUtc(),
          memberId: primaryId,
        );
        // Native multi-member row (primary keeps id; co-fronter gets v5)
        await _seedSession(
          db,
          id: 'native-multi',
          startTime: DateTime(2026, 4, 1, 15).toUtc(),
          endTime: DateTime(2026, 4, 1, 16).toUtc(),
          memberId: primaryId,
          coFronterIds: jsonEncode([coId]),
        );
        // Native orphan row (no member_id) - gets Unknown sentinel
        await _seedSession(
          db,
          id: 'orphan-1',
          startTime: DateTime(2026, 4, 1, 17).toUtc(),
          endTime: DateTime(2026, 4, 1, 18).toUtc(),
        );

        final resetCalls = <ffi.PrismSyncHandle>[];
        final svc = _makeService(db, exportService, resetCalls: resetCalls);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.spRowsMigrated, 1);
        // native-1 + native-multi (primary) + (orphan handled in step 7,
        // not nativeRowsMigrated)
        expect(result.nativeRowsMigrated, 2);
        expect(result.nativeRowsExpanded, 1);
        expect(result.pkRowsDeleted, 1);
        expect(result.orphanRowsAssignedToSentinel, 1);
        expect(result.unknownSentinelCreated, isTrue);
        expect(result.corruptCoFronterRowIds, isEmpty);
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'complete',
        );

        // Per-row assertions.
        final rows = await db.frontingSessionsDao.getAllSessions();
        final byId = {for (final r in rows) r.id: r};
        // PK row tombstoned (not in active set).
        expect(byId.containsKey('pk-1'), isFalse);
        // SP / native single-member / native primary still here.
        expect(byId.containsKey('sp-1'), isTrue);
        expect(byId.containsKey('native-1'), isTrue);
        expect(byId.containsKey('native-multi'), isTrue);
        expect(byId['native-multi']!.memberId, primaryId);
        // Co-fronter fan-out row at the deterministic v5 id.
        const uuid = Uuid();
        final coRowId = uuid.v5(
          migrationFrontingNamespace,
          'native-multi:$coId',
        );
        expect(byId.containsKey(coRowId), isTrue);
        expect(byId[coRowId]!.memberId, coId);
        // Orphan row reassigned to sentinel.
        final sentinelId = uuid.v5(
          spFrontingNamespace,
          'unknown-member-sentinel',
        );
        expect(byId['orphan-1']!.memberId, sentinelId);
        // Sentinel member exists.
        final sentinel = await DriftMemberRepository(
          db.membersDao,
          null,
        ).getMemberById(sentinelId);
        expect(sentinel, isNotNull);
        expect(sentinel!.name, 'Unknown');

        // Sync FFI not called because handle was null in this run.
        expect(resetCalls, isEmpty);
        // Quarantine cleared.
        expect(await db.syncQuarantineDao.count(), 0);
      },
    );

    test('phase 2 harness: real SP fixture plus native rows survives '
        'upgradeAndKeep without duplicate or orphaned fronting rows', () async {
      final fixture = File('test/fixtures/sp_export.json');
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'Phase 2 harness depends on the checked-in SP fixture',
      );

      final importer = SpImporter();
      final exportData = importer.parseFile(fixture.path);
      expect(exportData.frontHistory, isNotEmpty);

      final importResult = await importer.executeImport(
        db: db,
        data: exportData,
        memberRepo: DriftMemberRepository(db.membersDao, null),
        sessionRepo: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        conversationRepo: DriftConversationRepository(
          db.conversationsDao,
          null,
        ),
        messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
        pollRepo: DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        ),
        notesRepo: DriftNotesRepository(db.notesDao, null),
        commentsRepo: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        customFieldsRepo: DriftCustomFieldsRepository(db.customFieldsDao, null),
        groupsRepo: DriftMemberGroupsRepository(db.memberGroupsDao, null),
        remindersRepo: DriftRemindersRepository(db.remindersDao, null),
        settingsRepo: DriftSystemSettingsRepository(db.systemSettingsDao, null),
        categoriesRepo: DriftConversationCategoriesRepository(
          db.conversationCategoriesDao,
          null,
        ),
        spImportDao: db.spImportDao,
        downloadAvatars: false,
      );

      expect(importResult.sessionsImported, greaterThan(0));

      final beforeRows = await db.frontingSessionsDao.getAllSessions();
      expect(beforeRows, hasLength(importResult.sessionsImported));

      final beforeMappings = await db.spImportDao.getAllMappings();
      final beforeSessionMappings = beforeMappings
          .where((m) => m.entityType == 'session')
          .toList(growable: false);
      expect(beforeSessionMappings, hasLength(importResult.sessionsImported));
      final beforeSessionIdBySourceId = {
        for (final mapping in beforeSessionMappings)
          mapping.spId: mapping.prismId,
      };

      const nativePrimary = 'phase2-native-primary';
      const nativeCo1 = 'phase2-native-co-1';
      const nativeCo2 = 'phase2-native-co-2';
      const nativeSingle = 'phase2-native-single';
      const nativeMulti = 'phase2-native-multi';
      const nativeUnknown = 'phase2-native-unknown';
      const nativeComment = 'phase2-native-comment';
      final nativeCommentTime = DateTime.utc(2026, 4, 2, 9, 30);

      await _seedMember(db, nativePrimary);
      await _seedMember(db, nativeCo1);
      await _seedMember(db, nativeCo2);
      await _seedSession(
        db,
        id: nativeSingle,
        startTime: DateTime.utc(2026, 4, 2, 8),
        endTime: DateTime.utc(2026, 4, 2, 8, 50),
        memberId: nativePrimary,
      );
      await _seedSession(
        db,
        id: nativeMulti,
        startTime: DateTime.utc(2026, 4, 2, 9),
        endTime: DateTime.utc(2026, 4, 2, 10),
        memberId: nativePrimary,
        coFronterIds: jsonEncode([nativeCo1, nativeCo2]),
      );
      await _seedSession(
        db,
        id: nativeUnknown,
        startTime: DateTime.utc(2026, 4, 2, 10, 10),
        endTime: DateTime.utc(2026, 4, 2, 11),
      );
      await _seedComment(
        db,
        id: nativeComment,
        sessionId: nativeMulti,
        body: 'native comment survives',
        timestamp: nativeCommentTime,
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.spRowsMigrated, importResult.sessionsImported);
      expect(result.nativeRowsMigrated, 2);
      expect(result.nativeRowsExpanded, 2);
      expect(result.orphanRowsAssignedToSentinel, 1);
      expect(result.unknownSentinelCreated, isTrue);
      expect(result.pkRowsDeleted, 0);
      expect(result.corruptCoFronterRowIds, isEmpty);

      final afterRows = await db.frontingSessionsDao.getAllSessions();
      final afterById = {for (final row in afterRows) row.id: row};

      for (final entry in beforeSessionIdBySourceId.entries) {
        expect(
          afterById,
          contains(entry.value),
          reason: 'SP session ${entry.key} should survive by Prism id',
        );
      }

      expect(afterById[nativeSingle]?.memberId, nativePrimary);
      expect(afterById[nativeMulti]?.memberId, nativePrimary);

      const uuid = Uuid();
      final co1RowId = uuid.v5(
        migrationFrontingNamespace,
        '$nativeMulti:$nativeCo1',
      );
      final co2RowId = uuid.v5(
        migrationFrontingNamespace,
        '$nativeMulti:$nativeCo2',
      );
      expect(afterById[co1RowId]?.memberId, nativeCo1);
      expect(afterById[co2RowId]?.memberId, nativeCo2);

      final sentinelId = uuid.v5(
        spFrontingNamespace,
        'unknown-member-sentinel',
      );
      expect(afterById[nativeUnknown]?.memberId, sentinelId);

      final afterMappings = await db.spImportDao.getAllMappings();
      final afterSessionIdBySourceId = {
        for (final mapping in afterMappings.where(
          (m) => m.entityType == 'session',
        ))
          mapping.spId: mapping.prismId,
      };
      expect(afterSessionIdBySourceId, beforeSessionIdBySourceId);

      final activeRowsWithNullMember = afterRows.where(
        (row) => row.sessionType == 0 && row.memberId == null,
      );
      expect(activeRowsWithNullMember, isEmpty);

      final activeIds = afterRows.map((row) => row.id).toList();
      expect(activeIds.toSet(), hasLength(activeIds.length));

      final comments = await db.frontSessionCommentsDao.getAllComments();
      final comment = comments.singleWhere((c) => c.id == nativeComment);
      expect(comment.sessionId, '');
      expect(comment.targetTime?.toUtc(), nativeCommentTime);
      expect(comment.authorMemberId, nativePrimary);
      expect(comment.body, 'native comment survives');
      expect(comment.isDeleted, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('phase 2 harness: PK full import rows are rebuilt after '
        'upgradeAndKeep clears them', () async {
      const pkAliceShortId = 'aaaaa';
      const pkBobShortId = 'bbbbb';
      const pkAliceUuid = '11111111-1111-4111-8111-111111111111';
      const pkBobUuid = '22222222-2222-4222-8222-222222222222';
      const sw1Id = 'pk-switch-1';
      const sw2Id = 'pk-switch-2';
      const sw3Id = 'pk-switch-3';
      const sw4Id = 'pk-switch-4';
      final sw1Time = DateTime.utc(2026, 4, 3, 8);
      final sw2Time = DateTime.utc(2026, 4, 3, 9);
      final sw3Time = DateTime.utc(2026, 4, 3, 10);
      final sw4Time = DateTime.utc(2026, 4, 3, 11);
      const pkMembers = [
        PKMember(id: pkAliceShortId, uuid: pkAliceUuid, name: 'PK Alice'),
        PKMember(id: pkBobShortId, uuid: pkBobUuid, name: 'PK Bob'),
      ];
      final pkSwitchesNewestFirst = [
        PKSwitch(id: sw4Id, timestamp: sw4Time, members: const []),
        PKSwitch(id: sw3Id, timestamp: sw3Time, members: const [pkBobShortId]),
        PKSwitch(
          id: sw2Id,
          timestamp: sw2Time,
          members: const [pkAliceShortId, pkBobShortId],
        ),
        PKSwitch(
          id: sw1Id,
          timestamp: sw1Time,
          members: const [pkAliceShortId],
        ),
      ];

      final firstClient = _PkMigrationFakeClient(
        members: pkMembers,
        switchesNewestFirst: pkSwitchesNewestFirst,
      );
      await _makePkImportService(db, firstClient).performFullImport();

      final members = await db.membersDao.getAllMembers();
      final aliceLocalId = members
          .singleWhere((m) => m.pluralkitUuid == pkAliceUuid)
          .id;
      final bobLocalId = members
          .singleWhere((m) => m.pluralkitUuid == pkBobUuid)
          .id;

      final aliceRowId = derivePkSessionId(sw1Id, pkAliceUuid);
      final bobRowId = derivePkSessionId(sw2Id, pkBobUuid);
      final nonEntrantAliceAtSw2 = derivePkSessionId(sw2Id, pkAliceUuid);

      final importedRows = await db.frontingSessionsDao.getAllSessions();
      final importedById = {for (final row in importedRows) row.id: row};
      expect(importedById[aliceRowId]?.memberId, aliceLocalId);
      expect(importedById[aliceRowId]?.startTime.toUtc(), sw1Time);
      expect(importedById[aliceRowId]?.endTime?.toUtc(), sw3Time);
      expect(importedById[bobRowId]?.memberId, bobLocalId);
      expect(importedById[bobRowId]?.startTime.toUtc(), sw2Time);
      expect(importedById[bobRowId]?.endTime?.toUtc(), sw4Time);
      expect(importedById, isNot(contains(nonEntrantAliceAtSw2)));

      const nativeMember = 'phase2-pk-native-member';
      const nativeSession = 'phase2-pk-native-session';
      await _seedMember(db, nativeMember);
      await _seedSession(
        db,
        id: nativeSession,
        startTime: DateTime.utc(2026, 4, 4, 8),
        endTime: DateTime.utc(2026, 4, 4, 9),
        memberId: nativeMember,
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.pkRowsDeleted, 2);
      expect(result.nativeRowsMigrated, 1);
      expect(result.spRowsMigrated, 0);
      expect(result.orphanRowsAssignedToSentinel, 0);

      final afterMigrationRows = await db.frontingSessionsDao.getAllSessions();
      final afterMigrationById = {
        for (final row in afterMigrationRows) row.id: row,
      };
      expect(afterMigrationById[nativeSession]?.memberId, nativeMember);
      expect(
        afterMigrationRows.where((row) => row.pluralkitUuid != null),
        isEmpty,
      );

      final secondClient = _PkMigrationFakeClient(
        members: pkMembers,
        switchesNewestFirst: pkSwitchesNewestFirst,
      );
      await _makePkImportService(db, secondClient).performFullImport();

      final rebuiltRows = await db.frontingSessionsDao.getAllSessions();
      final rebuiltById = {for (final row in rebuiltRows) row.id: row};
      expect(rebuiltById[nativeSession]?.memberId, nativeMember);
      expect(rebuiltById[aliceRowId]?.memberId, aliceLocalId);
      expect(rebuiltById[aliceRowId]?.isDeleted, isFalse);
      expect(rebuiltById[aliceRowId]?.startTime.toUtc(), sw1Time);
      expect(rebuiltById[aliceRowId]?.endTime?.toUtc(), sw3Time);
      expect(rebuiltById[bobRowId]?.memberId, bobLocalId);
      expect(rebuiltById[bobRowId]?.isDeleted, isFalse);
      expect(rebuiltById[bobRowId]?.startTime.toUtc(), sw2Time);
      expect(rebuiltById[bobRowId]?.endTime?.toUtc(), sw4Time);
      expect(rebuiltById, isNot(contains(nonEntrantAliceAtSw2)));

      final rebuiltPkRows = rebuiltRows
          .where((row) => row.pluralkitUuid != null)
          .toList();
      expect(rebuiltPkRows, hasLength(2));
      final activeRowsWithNullMember = rebuiltRows.where(
        (row) => row.sessionType == 0 && row.memberId == null,
      );
      expect(activeRowsWithNullMember, isEmpty);

      final allRows = await db.frontingSessionsDao
          .getAllSessionsIncludingDeleted();
      final allIds = allRows.map((row) => row.id).toList();
      expect(allIds.toSet(), hasLength(allIds.length));
      expect(allRows.where((row) => row.id == aliceRowId), hasLength(1));
      expect(allRows.where((row) => row.id == bobRowId), hasLength(1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    // -------------------------------------------------------------------
    // startFresh - wipes everything, no sentinel
    // -------------------------------------------------------------------
    test(
      'solo startFresh wipes every fronting row and creates no sentinel',
      () async {
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime(2026, 4, 1, 9).toUtc(),
          memberId: 'm1',
        );
        await _seedSession(
          db,
          id: 's2',
          startTime: DateTime(2026, 4, 1, 10).toUtc(),
          memberId: 'm1',
          pluralkitUuid: '22222222-2222-4222-8222-222222222222',
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.startFresh,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.unknownSentinelCreated, isFalse);
        expect(result.orphanRowsAssignedToSentinel, 0);
        // Both rows tombstoned (excluded from getAllSessions).
        final active = await db.frontingSessionsDao.getAllSessions();
        expect(active, isEmpty);
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'complete',
        );
      },
    );

    // -------------------------------------------------------------------
    // Comments preserve / delete + target_time anchored at timestamp
    // -------------------------------------------------------------------
    test('primary upgradeAndKeep: comments on PK parents deleted; comments on '
        'SP/native parents migrated to new shape with target_time = legacy '
        'timestamp and author_member_id from parent', () async {
      const memberA = 'mem-a';
      const memberB = 'mem-b';
      for (final id in [memberA, memberB]) {
        await _seedMember(db, id);
      }
      // PK parent (its comment will be deleted).
      await _seedSession(
        db,
        id: 'pk-parent',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        endTime: DateTime(2026, 4, 1, 10).toUtc(),
        memberId: memberA,
        pluralkitUuid: '33333333-3333-4333-8333-333333333333',
      );
      // Native parent (its comment is migrated).
      await _seedSession(
        db,
        id: 'native-parent',
        startTime: DateTime(2026, 4, 1, 11).toUtc(),
        endTime: DateTime(2026, 4, 1, 12).toUtc(),
        memberId: memberB,
      );
      // Comment timestamps differ from createdAt to verify the
      // anchor truly comes from `timestamp` (per spec warning).
      final cmt1Time = DateTime(2026, 4, 1, 9, 30).toUtc();
      final cmt2Time = DateTime(2026, 4, 1, 11, 30).toUtc();
      await _seedComment(
        db,
        id: 'cmt-pk',
        sessionId: 'pk-parent',
        body: 'pk note',
        timestamp: cmt1Time,
      );
      await _seedComment(
        db,
        id: 'cmt-native',
        sessionId: 'native-parent',
        body: 'native note',
        timestamp: cmt2Time,
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.primary,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.commentsMigrated, 1);
      expect(result.commentsDeleted, 1);

      // Native comment migrated in place: target_time set, author set,
      // body intact, row id stable.
      final nativeRow = await db
          .customSelect(
            'SELECT target_time, author_member_id, body, is_deleted '
            'FROM front_session_comments WHERE id = ?',
            variables: [drift.Variable.withString('cmt-native')],
          )
          .getSingle();
      expect(nativeRow.read<DateTime?>('target_time')?.toUtc(), cmt2Time);
      expect(nativeRow.read<String?>('author_member_id'), memberB);
      expect(nativeRow.read<String>('body'), 'native note');
      expect(nativeRow.read<int>('is_deleted'), 0);

      // PK comment soft-deleted.
      final pkRow = await db
          .customSelect(
            'SELECT is_deleted FROM front_session_comments WHERE id = ?',
            variables: [drift.Variable.withString('cmt-pk')],
          )
          .getSingle();
      expect(pkRow.read<int>('is_deleted'), 1);
    });

    // -------------------------------------------------------------------
    // Corrupt co_fronter_ids JSON
    // -------------------------------------------------------------------
    test('corrupt co_fronter_ids JSON falls back to single-member migration '
        'and surfaces the row id (spec §6 edge case)', () async {
      const primaryId = 'p-corrupt';
      await _seedMember(db, primaryId);
      await _seedSession(
        db,
        id: 'corrupt-row',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        endTime: DateTime(2026, 4, 1, 10).toUtc(),
        memberId: primaryId,
        coFronterIds: '{not valid json',
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.nativeRowsMigrated, 1);
      expect(result.nativeRowsExpanded, 0);
      expect(result.corruptCoFronterRowIds, contains('corrupt-row'));
      final rows = await db.frontingSessionsDao.getAllSessions();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'corrupt-row');
      expect(rows.single.memberId, primaryId);
    });

    // -------------------------------------------------------------------
    // Secondary mode
    // -------------------------------------------------------------------
    test(
      'secondary mode skips per-row migration and truncates fronting tables',
      () async {
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime(2026, 4, 1, 9).toUtc(),
          memberId: 'm1',
        );
        await _seedComment(
          db,
          id: 'c1',
          sessionId: 's1',
          body: 'b',
          timestamp: DateTime(2026, 4, 1, 9).toUtc(),
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.secondary,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        // Tables fully truncated (DELETE, not soft-delete).
        final sessions = await db
            .customSelect('SELECT COUNT(*) AS c FROM fronting_sessions')
            .getSingle();
        expect(sessions.read<int>('c'), 0);
        final comments = await db
            .customSelect('SELECT COUNT(*) AS c FROM front_session_comments')
            .getSingle();
        expect(comments.read<int>('c'), 0);
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'complete',
        );
      },
    );

    // -------------------------------------------------------------------
    // Failure inside the transaction rolls back
    // -------------------------------------------------------------------
    test('failure inside Drift transaction rolls back; settings stays at '
        'notStarted; PRISM1 file from step 2 is preserved on disk', () async {
      // Force a failing reset_sync_state via a non-null mock handle
      // backed by a thrower.  But the transaction is what we want to
      // fail.  Easier path: poison a row so step 4's writeSession
      // throws.  We achieve that by seeding a row with a member_id
      // referencing a member that exists, then rigging the
      // memberRepository to throw on update.  Instead, simulate by
      // throwing from shareFile AFTER export but BEFORE transaction  -
      // that's a different failure surface (the exportFile is still
      // preserved, but no transaction work runs).
      //
      // To genuinely test rollback, we bracket a poison: drop the
      // fronting_sessions table mid-transaction by injecting a
      // resetSyncState that throws synchronously.  But that runs
      // OUTSIDE the transaction.  So instead we pre-seed an invalid
      // configuration that the transaction's writes will trip on:
      // a row whose `pluralkit_uuid` collides with a tombstone (the
      // composite unique index) so the syncRecordUpdate fails.
      //
      // Simplest: use a synthetic failing repo via a custom service.
      // Build a service whose memberRepository throws on createMember
      // (the orphan-sentinel path will trigger it).
      // Mirror the post-v7-onUpgrade state: settings starts at
      // notStarted (only fresh installs default to complete).
      await db.systemSettingsDao.writePendingFrontingMigrationMode(
        'notStarted',
      );
      await _seedSession(
        db,
        id: 'orphan-only',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
      );

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: _ThrowingMemberRepository(
          DriftMemberRepository(db.membersDao, null),
        ),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: null,
        resetSyncState: (_) async {},
        backupDirectoryProvider: () async => cacheDir,
      );

      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.failed);
      expect(result.errorMessage, contains('Migration transaction failed'));
      // PRISM1 export survived even though the transaction rolled back.
      expect(result.exportFile, isNotNull);
      expect(await result.exportFile!.exists(), isTrue);
      // Settings rolled back to default.
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'notStarted',
      );
      // Orphan row still untouched.
      final rows = await db.frontingSessionsDao.getAllSessions();
      expect(rows.single.id, 'orphan-only');
      expect(rows.single.memberId, isNull);
    });

    // -------------------------------------------------------------------
    // Sentinel idempotency
    // -------------------------------------------------------------------
    test('rerunning migration with an existing Unknown sentinel does not '
        'duplicate the member (deterministic id)', () async {
      const uuid = Uuid();
      final sentinelId = uuid.v5(
        spFrontingNamespace,
        'unknown-member-sentinel',
      );
      // Pre-create the sentinel as if a prior failed attempt left it
      // behind.
      await DriftMemberRepository(db.membersDao, null).createMember(
        Member(
          id: sentinelId,
          name: 'Unknown',
          emoji: '❔',
          createdAt: DateTime(2026, 4, 1).toUtc(),
        ),
      );
      await _seedSession(
        db,
        id: 'orphan-1',
        startTime: DateTime(2026, 4, 2, 9).toUtc(),
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(
        result.unknownSentinelCreated,
        isFalse,
        reason: 'sentinel already existed, no recreate',
      );
      expect(result.orphanRowsAssignedToSentinel, 1);
      final allSentinels = await DriftMemberRepository(
        db.membersDao,
        null,
      ).getAllMembers();
      expect(
        allSentinels.where((m) => m.id == sentinelId).toList(),
        hasLength(1),
      );
    });

    // -------------------------------------------------------------------
    // Sync state reset (Rust FFI mock)
    // -------------------------------------------------------------------
    test('sync state reset: when a handle is provided, the FFI '
        'reset_sync_state is invoked exactly once after the Drift '
        'transaction commits', () async {
      final resetCalls = <ffi.PrismSyncHandle>[];
      // Use an opaque sentinel handle - service treats it as opaque.
      // We can't construct a real PrismSyncHandle in unit tests
      // without spinning up the Rust runtime, so we construct via
      // the mock-only constructor pattern: cast a fake.  The
      // service's only interaction with the handle is to pass it
      // through to the resetSyncState callback.
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      final fakeHandle = _FakePrismSyncHandle();
      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: fakeHandle,
        resetSyncState: (h) async {
          resetCalls.add(h);
        },
        backupDirectoryProvider: () async => cacheDir,
      );

      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(resetCalls, hasLength(1));
      expect(identical(resetCalls.single, fakeHandle), isTrue);
    });

    // -------------------------------------------------------------------
    // Multi-member fan-out: deterministic v5 ids
    // -------------------------------------------------------------------
    test('native multi-member fan-out: primary keeps legacy id, co-fronters '
        'get migrationFrontingNamespace v5 ids matching 5D', () async {
      const primaryId = 'primary';
      const coId1 = 'co1';
      const coId2 = 'co2';
      for (final id in [primaryId, coId1, coId2]) {
        await _seedMember(db, id);
      }
      await _seedSession(
        db,
        id: 'multi',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        endTime: DateTime(2026, 4, 1, 10).toUtc(),
        memberId: primaryId,
        coFronterIds: jsonEncode([coId1, coId2]),
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.nativeRowsMigrated, 1);
      expect(result.nativeRowsExpanded, 2);

      const uuid = Uuid();
      final co1Id = uuid.v5(migrationFrontingNamespace, 'multi:$coId1');
      final co2Id = uuid.v5(migrationFrontingNamespace, 'multi:$coId2');
      final rows = await db.frontingSessionsDao.getAllSessions();
      final byId = {for (final r in rows) r.id: r};
      expect(
        byId.keys,
        containsAll(
          [
            ['multi'],
            [co1Id],
            [co2Id],
          ].expand((e) => e),
        ),
      );
      expect(byId['multi']!.memberId, primaryId);
      expect(byId[co1Id]!.memberId, coId1);
      expect(byId[co2Id]!.memberId, coId2);
    });

    // -------------------------------------------------------------------
    // Regression: suppression flag is cleared after migration.
    //
    // This test only proves the post-migration invariant (suppression flag
    // is back to false). The "suppression actually wraps every write"
    // invariant is asserted by the next test, which uses asserting
    // fake repositories that fail loudly on any unsuppressed write
    // during the migration body.
    // -------------------------------------------------------------------
    test(
      'suppression flag is cleared after migration (post-invariant only)',
      () async {
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime(2026, 4, 1, 9).toUtc(),
          memberId: 'm1',
        );

        // Pre + post invariants.
        expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'pre-migration');

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(
          SyncRecordMixin.isSuppressed,
          isFalse,
          reason: 'suppression must clear by the end of runMigration',
        );
      },
    );

    // -------------------------------------------------------------------
    // Regression: suppression is active during the migration body.
    //
    // Wraps every repository the migration writes through with an
    // asserting decorator that fails fast if `SyncRecordMixin.isSuppressed`
    // is false at the moment of a write. Exercises the full happy-path
    // upgradeAndKeep solo body so every documented write site (session
    // create / update / delete, comment update / delete, member sentinel
    // ensure) is covered. Without `SyncRecordMixin.suppress` wrapping
    // the Drift transaction, this test would fail on the first migrated
    // row.
    // -------------------------------------------------------------------
    test('every repository write inside the migration body runs while '
        'SyncRecordMixin.isSuppressed is true', () async {
      // Seed a mix of rows that exercises every documented write
      // path. (The body ends up calling all of: session update,
      // session create - for fan-out, session delete - for PK rows,
      // comment update, comment delete, member ensure-sentinel for
      // orphans.)
      const primaryId = 'primary-m';
      const coId = 'co-m';
      const spMemberId = 'sp-m';
      const pkMemberId = 'pk-m';
      for (final id in [primaryId, coId, spMemberId, pkMemberId]) {
        await _seedMember(db, id, name: id);
      }
      // PK row → deleteSession + comment deleteComment via PK parent.
      await _seedSession(
        db,
        id: 'pk-1',
        startTime: DateTime.utc(2026, 4, 1, 9),
        endTime: DateTime.utc(2026, 4, 1, 10),
        memberId: pkMemberId,
        pluralkitUuid: '11111111-1111-4111-8111-111111111111',
      );
      await _seedComment(
        db,
        id: 'cmt-pk',
        sessionId: 'pk-1',
        body: 'will be deleted (parent is PK)',
        timestamp: DateTime.utc(2026, 4, 1, 9, 30),
      );
      // SP row → updateSession.
      await _seedSession(
        db,
        id: 'sp-1',
        startTime: DateTime.utc(2026, 4, 2, 9),
        memberId: spMemberId,
      );
      await _seedSpMapping(db, 'sp-1');
      // Native multi-member row → updateSession + createSession (fan-out).
      await _seedSession(
        db,
        id: 'native-multi',
        startTime: DateTime.utc(2026, 4, 3, 9),
        memberId: primaryId,
        coFronterIds: jsonEncode([coId]),
      );
      await _seedComment(
        db,
        id: 'cmt-native',
        sessionId: 'native-multi',
        body: 'will be migrated (parent kept)',
        timestamp: DateTime.utc(2026, 4, 3, 10),
      );
      // Orphan row (member_id NULL) → triggers ensureUnknownSentinelMember.
      await _seedSession(
        db,
        id: 'orphan-1',
        startTime: DateTime.utc(2026, 4, 4, 9),
      );

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final commentsRepo = DriftFrontSessionCommentsRepository(
        db.frontSessionCommentsDao,
        null,
      );

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: _SuppressionAssertingMemberRepository(memberRepo),
        frontingSessionRepository:
            _SuppressionAssertingFrontingSessionRepository(sessionRepo),
        frontSessionCommentsRepository:
            _SuppressionAssertingFrontSessionCommentsRepository(commentsRepo),
        dataExportService: exportService,
        syncHandle: null,
        backupDirectoryProvider: () async => cacheDir,
      );

      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(
        result.outcome,
        MigrationOutcome.success,
        reason:
            'migration must succeed; '
            'failure here means an unsuppressed write was attempted '
            '(see asserting decorator messages)',
      );
      // Sanity: the body did exercise the paths we care about.
      expect(result.pkRowsDeleted, greaterThan(0));
      expect(result.spRowsMigrated, greaterThan(0));
      expect(result.nativeRowsMigrated, greaterThan(0));
      expect(result.nativeRowsExpanded, greaterThan(0));
      expect(result.commentsMigrated, greaterThan(0));
      expect(result.commentsDeleted, greaterThan(0));
      expect(result.orphanRowsAssignedToSentinel, greaterThan(0));
    });

    // -------------------------------------------------------------------
    // Regression: engine-reset failure leaves the inProgress marker.
    // -------------------------------------------------------------------
    test('engine reset failure: settings stays at inProgress; '
        'resumeCleanup() then succeeds and writes complete', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      // First attempt: reset throws; settings should land at inProgress.
      // Second attempt (resume) uses clear_sync_state instead of
      // reset_sync_state.
      var resetCalls = 0;
      Future<void> failingReset(ffi.PrismSyncHandle h) async {
        resetCalls++;
        throw StateError('Simulated FFI reset failure');
      }

      var clearCalls = 0;
      Future<void> okClear(ffi.PrismSyncHandle handle, String syncId) async {
        clearCalls++;
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: _FakePrismSyncHandle(),
        resetSyncState: failingReset,
        clearSyncState: okClear,
        readSyncId: () async => 'sync-abc',
        backupDirectoryProvider: () async => cacheDir,
      );

      final firstResult = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(firstResult.outcome, MigrationOutcome.failed);
      expect(firstResult.errorMessage, contains('Engine reset failed'));
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'inProgress',
        reason:
            'Drift tx committed but post-tx step failed: marker must be inProgress',
      );

      // Now resume - clear_sync_state succeeds, finishes the
      // remaining post-tx steps and lands at `complete`.
      final resumeResult = await svc.resumeCleanup();
      expect(resumeResult.outcome, MigrationOutcome.success);
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'complete',
      );
      expect(resetCalls, 1, reason: 'reset attempted once on first run');
      expect(
        clearCalls,
        1,
        reason: 'resume path uses clear_sync_state, not reset_sync_state',
      );
    });

    test('sync_quarantine clear failure: settings stays at inProgress; '
        'resumeCleanup recovers', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );
      // Inject a failing keychain wipe on first call only.
      var wipeCalls = 0;
      var firstWipe = true;
      Future<void> failingThenOkWipe() async {
        wipeCalls++;
        if (firstWipe) {
          firstWipe = false;
          throw StateError('Simulated keychain wipe failure');
        }
      }

      // Also count reset calls so the test
      // proves the substate-based skip behavior: the first attempt
      // succeeds at reset and writes substate=resetDone, then the
      // keychain wipe fails. On resume, reset MUST NOT be called
      // again (the substate already proves it succeeded).
      var resetCalls = 0;
      Future<void> countingReset(ffi.PrismSyncHandle _) async {
        resetCalls++;
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: _FakePrismSyncHandle(),
        resetSyncState: countingReset,
        wipeSyncKeychain: failingThenOkWipe,
        backupDirectoryProvider: () async => cacheDir,
      );

      final firstResult = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );
      expect(firstResult.outcome, MigrationOutcome.failed);
      expect(firstResult.errorMessage, contains('keychain wipe failed'));
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'inProgress',
      );
      // Substate must be 'resetDone' since the FFI reset DID succeed
      // - only the keychain wipe failed.
      expect(
        await db.systemSettingsDao
            .readPendingFrontingMigrationCleanupSubstate(),
        FrontingMigrationService.substateResetDone,
        reason:
            'Regression: substate must record that reset '
            'succeeded so resumeCleanup can skip it on retry',
      );
      expect(resetCalls, 1, reason: 'reset succeeded on first attempt');

      final resumeResult = await svc.resumeCleanup();
      expect(resumeResult.outcome, MigrationOutcome.success);
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'complete',
      );
      expect(wipeCalls, 2);
      expect(
        resetCalls,
        1,
        reason:
            'Regression: resumeCleanup must NOT re-run reset '
            'when substate already says resetDone - re-running against '
            'an unconfigured handle would have masked the "sync_id not '
            'set" error as success',
      );
      // After successful complete, substate should be reset to inert.
      expect(
        await db.systemSettingsDao
            .readPendingFrontingMigrationCleanupSubstate(),
        FrontingMigrationService.substateInert,
      );
    });

    // Regression: substate stays inert when first-attempt reset fails;
    // resumeCleanup re-attempts using clear_sync_state(sync_id) instead
    // of the configure-briefly-then-reset_sync_state path.
    test('engine reset failure: substate stays inert; resumeCleanup runs '
        'clear_sync_state(sync_id) before completing', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      var resetCalls = 0;
      Future<void> alwaysFailingReset(ffi.PrismSyncHandle _) async {
        resetCalls++;
        throw StateError('Simulated FFI reset failure');
      }

      var clearCalls = 0;
      String? clearedSyncId;
      Future<void> countingClear(ffi.PrismSyncHandle _, String syncId) async {
        clearCalls++;
        clearedSyncId = syncId;
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: _FakePrismSyncHandle(),
        resetSyncState: alwaysFailingReset,
        clearSyncState: countingClear,
        readSyncId: () async => 'sync-123',
        backupDirectoryProvider: () async => cacheDir,
      );

      final firstResult = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );
      expect(firstResult.outcome, MigrationOutcome.failed);
      // First attempt did NOT reach substate write - it failed
      // before the post-reset write site.
      expect(
        await db.systemSettingsDao
            .readPendingFrontingMigrationCleanupSubstate(),
        FrontingMigrationService.substateInert,
        reason:
            'Reset failure must leave substate inert so resume re-runs '
            'the wipe (the bug fix prevents re-running being '
            'misclassified as success)',
      );
      expect(
        clearCalls,
        0,
        reason:
            'first attempt is not the resume path; runMigrationDestructive '
            'uses reset_sync_state, never clear_sync_state',
      );
      expect(resetCalls, 1);

      final resumeResult = await svc.resumeCleanup();
      expect(resumeResult.outcome, MigrationOutcome.success);
      expect(
        resetCalls,
        1,
        reason:
            'resume path must NOT call reset_sync_state - published '
            'handle is unconfigured on inProgress, so reset would '
            'fail with sync_id not set; use clear_sync_state instead',
      );
      expect(
        clearCalls,
        1,
        reason: 'resume path must wipe storage via clear_sync_state(sync_id)',
      );
      expect(clearedSyncId, 'sync-123');
    });

    // Regression: a Rust error from the first-attempt reset must not be
    // silently swallowed as "already reset." Substate is the source of truth;
    // if it's inert, the error is real.
    test('engine reset failure on first attempt is treated as a real failure '
        '(not silently treated as success)', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      Future<void> alwaysFailing(ffi.PrismSyncHandle _) async {
        throw StateError('Simulated reset failure');
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: _FakePrismSyncHandle(),
        resetSyncState: alwaysFailing,
        backupDirectoryProvider: () async => cacheDir,
      );

      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      // Previously this was incorrectly classified as success via
      // the _isAlreadyResetError heuristic. With substate as the
      // source of truth, the error surfaces as a failure and
      // settings stay at inProgress so the user can retry.
      expect(result.outcome, MigrationOutcome.failed);
      expect(result.errorMessage, contains('Engine reset failed'));
      expect(
        await db.systemSettingsDao.readPendingFrontingMigrationMode(),
        'inProgress',
      );
      expect(
        await db.systemSettingsDao
            .readPendingFrontingMigrationCleanupSubstate(),
        FrontingMigrationService.substateInert,
      );
    });

    // Regression: resume path with no sync_id in keychain (already wiped
    // or solo-device case) advances substate without calling
    // clear_sync_state, so the remaining cleanup steps run.
    test('resumeCleanup with no sync_id available skips clear_sync_state '
        'and advances substate', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime(2026, 4, 1, 9).toUtc(),
        memberId: 'm1',
      );

      Future<void> alwaysFailingReset(ffi.PrismSyncHandle _) async {
        throw StateError('Simulated FFI reset failure');
      }

      var clearCalls = 0;
      Future<void> countingClear(
        ffi.PrismSyncHandle handle,
        String syncId,
      ) async {
        clearCalls++;
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: _FakePrismSyncHandle(),
        resetSyncState: alwaysFailingReset,
        clearSyncState: countingClear,
        readSyncId: () async => null,
        backupDirectoryProvider: () async => cacheDir,
      );

      // First attempt fails, leaving us at inProgress / inert.
      final firstResult = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );
      expect(firstResult.outcome, MigrationOutcome.failed);

      final resumeResult = await svc.resumeCleanup();
      expect(resumeResult.outcome, MigrationOutcome.success);
      expect(clearCalls, 0, reason: 'no sync_id → nothing to clear in storage');
    });

    test(
      'resumeCleanup() refuses to run when mode is not inProgress',
      () async {
        await db.systemSettingsDao.writePendingFrontingMigrationMode(
          'notStarted',
        );
        final svc = _makeService(db, exportService);
        final result = await svc.resumeCleanup();
        expect(result.outcome, MigrationOutcome.failed);
        expect(result.errorMessage, contains('expected inProgress'));
      },
    );

    // -------------------------------------------------------------------
    // Adjacent-merge pass (spec §2.1) - fan-out preserves boundaries
    // that existed in the old shape only because a co-fronter joined
    // or left. Under the per-member abstraction those boundaries are
    // arbitrary cosmetic artifacts. Collapse them post-fan-out.
    // -------------------------------------------------------------------
    test('continuous-host scenario: Zari fronts 6:42–8:50 then Aimee joins '
        '8:50–9:07 → 1 Zari row 6:42–9:07 + 1 Aimee row 8:50–9:07', () async {
      const zari = 'zari';
      const aimee = 'aimee';
      for (final id in [zari, aimee]) {
        await _seedMember(db, id, name: id);
      }
      // Old session A: Zari alone, 6:42 → 8:50.
      await _seedSession(
        db,
        id: 'sess-a',
        startTime: DateTime.utc(2026, 4, 1, 6, 42),
        endTime: DateTime.utc(2026, 4, 1, 8, 50),
        memberId: zari,
      );
      // Old session B: Zari + Aimee, 8:50 → 9:07 (Aimee joined).
      await _seedSession(
        db,
        id: 'sess-b',
        startTime: DateTime.utc(2026, 4, 1, 8, 50),
        endTime: DateTime.utc(2026, 4, 1, 9, 7),
        memberId: zari,
        coFronterIds: jsonEncode([aimee]),
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.adjacentMergesPerformed, 1);

      final rows = await db.frontingSessionsDao.getAllSessions();
      // 1 Zari row + 1 Aimee row = 2 rows total.
      expect(rows, hasLength(2));
      final zariRows = rows.where((r) => r.memberId == zari).toList();
      expect(zariRows, hasLength(1));
      expect(
        zariRows.single.startTime.toUtc(),
        DateTime.utc(2026, 4, 1, 6, 42),
      );
      expect(zariRows.single.endTime?.toUtc(), DateTime.utc(2026, 4, 1, 9, 7));
      // Surviving row keeps the earlier id ('sess-a').
      expect(zariRows.single.id, 'sess-a');

      final aimeeRows = rows.where((r) => r.memberId == aimee).toList();
      expect(aimeeRows, hasLength(1));
      expect(
        aimeeRows.single.startTime.toUtc(),
        DateTime.utc(2026, 4, 1, 8, 50),
      );
      expect(aimeeRows.single.endTime?.toUtc(), DateTime.utc(2026, 4, 1, 9, 7));
    });

    test(
      'three-row cascade: A→B→C all adjacent same-member collapse to 1 row',
      () async {
        const host = 'host';
        await _seedMember(db, host);
        await _seedSession(
          db,
          id: 'a',
          startTime: DateTime.utc(2026, 4, 1, 6, 42),
          endTime: DateTime.utc(2026, 4, 1, 8, 50),
          memberId: host,
        );
        await _seedSession(
          db,
          id: 'b',
          startTime: DateTime.utc(2026, 4, 1, 8, 50),
          endTime: DateTime.utc(2026, 4, 1, 9, 7),
          memberId: host,
        );
        await _seedSession(
          db,
          id: 'c',
          startTime: DateTime.utc(2026, 4, 1, 9, 7),
          endTime: DateTime.utc(2026, 4, 1, 9, 30),
          memberId: host,
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.adjacentMergesPerformed, 2);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.startTime.toUtc(), DateTime.utc(2026, 4, 1, 6, 42));
        expect(rows.single.endTime?.toUtc(), DateTime.utc(2026, 4, 1, 9, 30));
        expect(rows.single.id, 'a');
      },
    );

    test(
      'gap preserves separation: 5-minute gap between rows → no merge',
      () async {
        const host = 'host-gap';
        await _seedMember(db, host);
        await _seedSession(
          db,
          id: 'a',
          startTime: DateTime.utc(2026, 4, 1, 6, 42),
          endTime: DateTime.utc(2026, 4, 1, 8, 50),
          memberId: host,
        );
        await _seedSession(
          db,
          id: 'b',
          startTime: DateTime.utc(2026, 4, 1, 8, 55),
          endTime: DateTime.utc(2026, 4, 1, 9, 7),
          memberId: host,
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.adjacentMergesPerformed, 0);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(2));
      },
    );

    test(
      'notes concatenate when both sides are non-null after merge',
      () async {
        const host = 'host-notes';
        await _seedMember(db, host);
        // Use the customStatement path to get notes onto a row (the
        // _seedSession helper doesn't expose a notes parameter).
        await _seedSession(
          db,
          id: 'a',
          startTime: DateTime.utc(2026, 4, 1, 6, 42),
          endTime: DateTime.utc(2026, 4, 1, 8, 50),
          memberId: host,
        );
        await _seedSession(
          db,
          id: 'b',
          startTime: DateTime.utc(2026, 4, 1, 8, 50),
          endTime: DateTime.utc(2026, 4, 1, 9, 7),
          memberId: host,
        );
        await db.customStatement(
          "UPDATE fronting_sessions SET notes = 'morning' WHERE id = 'a'",
        );
        await db.customStatement(
          "UPDATE fronting_sessions SET notes = 'post-meeting' WHERE id = 'b'",
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.adjacentMergesPerformed, 1);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.notes, 'morning\n\npost-meeting');
      },
    );

    test('open-ended merge: B is currently fronting (end_time NULL) → '
        'merged row stays open-ended', () async {
      const host = 'host-open';
      await _seedMember(db, host);
      await _seedSession(
        db,
        id: 'a',
        startTime: DateTime.utc(2026, 4, 1, 6, 42),
        endTime: DateTime.utc(2026, 4, 1, 8, 50),
        memberId: host,
      );
      await _seedSession(
        db,
        id: 'b',
        startTime: DateTime.utc(2026, 4, 1, 8, 50),
        endTime: null,
        memberId: host,
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      expect(result.adjacentMergesPerformed, 1);
      final rows = await db.frontingSessionsDao.getAllSessions();
      expect(rows, hasLength(1));
      expect(rows.single.endTime, isNull);
      expect(rows.single.startTime.toUtc(), DateTime.utc(2026, 4, 1, 6, 42));
    });

    test(
      'sleep rows are not merged into normal rows even when boundaries touch',
      () async {
        const host = 'host-sleep';
        await _seedMember(db, host);
        // Normal row 6:42 → 8:50.
        await _seedSession(
          db,
          id: 'normal',
          startTime: DateTime.utc(2026, 4, 1, 6, 42),
          endTime: DateTime.utc(2026, 4, 1, 8, 50),
          memberId: host,
        );
        // Sleep row 8:50 → 9:07 - adjacent to normal but session_type = 1.
        await _seedSession(
          db,
          id: 'sleep',
          startTime: DateTime.utc(2026, 4, 1, 8, 50),
          endTime: DateTime.utc(2026, 4, 1, 9, 7),
          memberId: host,
          sessionType: 1,
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(result.adjacentMergesPerformed, 0);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(2));
      },
    );

    test('multi-member sanity: only same-member adjacent rows merge; the '
        'other member\'s separate row stays untouched', () async {
      const zari = 'z';
      const aimee = 'a';
      for (final id in [zari, aimee]) {
        await _seedMember(db, id, name: id);
      }
      // Two old rows that fan out into Zari×2 + Aimee×1.
      await _seedSession(
        db,
        id: 'sess-a',
        startTime: DateTime.utc(2026, 4, 1, 6, 42),
        endTime: DateTime.utc(2026, 4, 1, 8, 50),
        memberId: zari,
      );
      await _seedSession(
        db,
        id: 'sess-b',
        startTime: DateTime.utc(2026, 4, 1, 8, 50),
        endTime: DateTime.utc(2026, 4, 1, 9, 7),
        memberId: zari,
        coFronterIds: jsonEncode([aimee]),
      );
      // A separate non-adjacent Aimee row much later: must stay as-is.
      await _seedSession(
        db,
        id: 'aimee-later',
        startTime: DateTime.utc(2026, 4, 1, 14),
        endTime: DateTime.utc(2026, 4, 1, 15),
        memberId: aimee,
      );

      final svc = _makeService(db, exportService);
      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: _noopShare,
      );

      expect(result.outcome, MigrationOutcome.success);
      // Only Zari's rows merge.
      expect(result.adjacentMergesPerformed, 1);
      final rows = await db.frontingSessionsDao.getAllSessions();
      // 1 Zari + 1 Aimee fan-out + 1 Aimee later = 3 rows.
      expect(rows, hasLength(3));
      final aimeeRows = rows.where((r) => r.memberId == aimee).toList();
      expect(aimeeRows, hasLength(2));
      expect(rows.where((r) => r.memberId == zari), hasLength(1));
    });

    // -------------------------------------------------------------------
    // WS1 step 1 + 2: atomic mode-marker + failpoints.
    //
    // The destructive Drift transaction stamps `inProgress` as its
    // FIRST statement. Throwing inside the transaction must roll back
    // both the marker and the destructive writes; throwing AFTER the
    // commit must leave `inProgress` durable so the modal's resume
    // path can finish cleanup.
    // -------------------------------------------------------------------
    test(
      'transaction failpoint: marker and destructive writes roll back together '
      '(mode reverts; rows untouched)',
      () async {
        await db.systemSettingsDao.writePendingFrontingMigrationMode(
          'notStarted',
        );
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime.utc(2026, 4, 1, 9),
          memberId: 'm1',
        );

        final svc = FrontingMigrationService(
          db: db,
          memberRepository: DriftMemberRepository(db.membersDao, null),
          frontingSessionRepository: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          ),
          frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          dataExportService: exportService,
          syncHandle: null,
          backupDirectoryProvider: () async => cacheDir,
          midTransactionFailpoint: () async {
            throw StateError('synthetic mid-tx failure');
          },
        );

        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.failed);
        expect(result.errorMessage, contains('Migration transaction failed'));
        // Marker must NOT be inProgress: the Drift rollback rolled it
        // back along with the destructive writes.
        final mode = await db.systemSettingsDao
            .readPendingFrontingMigrationMode();
        expect(mode, 'notStarted');
        // Sessions table is unchanged.
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, 's1');
      },
    );

    test(
      'post-commit failpoint: leaves marker at inProgress; resumeCleanup '
      'recovers; the destructive writes survived the original commit',
      () async {
        await db.systemSettingsDao.writePendingFrontingMigrationMode(
          'notStarted',
        );
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime.utc(2026, 4, 1, 9),
          memberId: 'm1',
        );

        var hookCalls = 0;
        Future<void> postHook() async {
          hookCalls++;
          throw StateError('synthetic post-commit failure');
        }

        final svc = FrontingMigrationService(
          db: db,
          memberRepository: DriftMemberRepository(db.membersDao, null),
          frontingSessionRepository: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          ),
          frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          dataExportService: exportService,
          syncHandle: null,
          backupDirectoryProvider: () async => cacheDir,
          postTransactionFailpoint: postHook,
        );

        final firstResult = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(firstResult.outcome, MigrationOutcome.failed);
        expect(hookCalls, 1);
        expect(
          firstResult.errorMessage,
          contains('Post-transaction failpoint'),
        );
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'inProgress',
          reason:
              'Drift transaction committed with the marker stamped; the '
              'post-commit failure must NOT roll the marker back.',
        );

        // Build a service with no failpoint so resumeCleanup completes.
        final svcResume = FrontingMigrationService(
          db: db,
          memberRepository: DriftMemberRepository(db.membersDao, null),
          frontingSessionRepository: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          ),
          frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          dataExportService: exportService,
          syncHandle: null,
          backupDirectoryProvider: () async => cacheDir,
        );

        final resumeResult = await svcResume.resumeCleanup();
        expect(resumeResult.outcome, MigrationOutcome.success);
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'complete',
        );
      },
    );

    // -------------------------------------------------------------------
    // WS1 step 3: shareFile cancellation aborts before destructive work.
    // -------------------------------------------------------------------
    test('runMigration honors shareFile null (user cancelled): no destructive '
        'writes; mode stays at notStarted; export file preserved', () async {
      await db.systemSettingsDao.writePendingFrontingMigrationMode(
        'notStarted',
      );
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime.utc(2026, 4, 1, 9),
        memberId: 'm1',
      );

      final svc = _makeService(db, exportService);

      final result = await svc.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: (_) async => null, // cancel
      );

      expect(result.outcome, MigrationOutcome.failed);
      expect(result.exportFile, isNotNull);
      expect(await result.exportFile!.exists(), isTrue);
      expect(
        result.errorMessage,
        contains('cancelled'),
        reason: 'cancellation surfaces as a typed failure',
      );
      // The destructive phase did not run: data and mode are untouched.
      final mode = await db.systemSettingsDao
          .readPendingFrontingMigrationMode();
      expect(mode, 'notStarted');
      final rows = await db.frontingSessionsDao.getAllSessions();
      expect(rows.single.id, 's1');
    });

    // -------------------------------------------------------------------
    // WS1 step 6: same-day backup retry produces a distinct filename
    // and refuses to overwrite an existing rescue file.
    // -------------------------------------------------------------------
    test('prepareBackup mints unique filenames on same-day retries '
        '(timestamped + nonced)', () async {
      await _seedMember(db, 'm1');
      await _seedSession(
        db,
        id: 's1',
        startTime: DateTime.utc(2026, 4, 1, 9),
        memberId: 'm1',
      );
      final dir = Directory.systemTemp.createTempSync(
        'prism-mig-filename-collide-',
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      // Walk the clock forward by 1s on each call so the epoch
      // suffix is guaranteed to differ even on a clock-stuck
      // simulator. Real wall-clock retries are seconds apart, but
      // we don't want this test to be flaky on a test runner that
      // calls `prepareBackup` twice in the same millisecond.
      var clockTick = DateTime.utc(2026, 4, 1, 9, 0, 0);
      DateTime tickClock() {
        final t = clockTick;
        clockTick = clockTick.add(const Duration(seconds: 1));
        return t;
      }

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: null,
        backupDirectoryProvider: () async => dir,
        clock: tickClock,
      );

      final fileA = await svc.prepareBackup(
        mode: MigrationMode.upgradeAndKeep,
        password: 'a-strong-password-12',
      );
      final fileB = await svc.prepareBackup(
        mode: MigrationMode.upgradeAndKeep,
        password: 'a-strong-password-12',
      );

      expect(fileA.path, isNot(equals(fileB.path)));
      expect(await fileA.exists(), isTrue);
      expect(await fileB.exists(), isTrue);
      // Both should be Prism-Export-...prism in the chosen dir.
      expect(fileA.path, startsWith(dir.path));
      expect(fileB.path, startsWith(dir.path));
      expect(fileA.path, endsWith('.prism'));
      expect(fileB.path, endsWith('.prism'));
    });

    test('prepareBackup refuses to overwrite a same-named rescue file '
        '(throws BackupFileCollisionException)', () async {
      await _seedMember(db, 'm1');
      final dir = Directory.systemTemp.createTempSync(
        'prism-mig-filename-refuse-',
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      // Pin the clock and nonce so the derived filename is
      // deterministic. We pre-create that exact file to force the
      // collision path.
      final fixedNow = DateTime.utc(2026, 4, 1, 9, 0, 0);
      final fixedNowEpoch = fixedNow.millisecondsSinceEpoch ~/ 1000;
      final pinnedRandom = _PinnedRandom([0xab, 0xcd]); // → "abcd"
      final expectedName = 'Prism-Export-2026-04-01-$fixedNowEpoch-abcd.prism';
      final precreated = File('${dir.path}/$expectedName');
      await precreated.writeAsBytes(const [1, 2, 3, 4]);

      final svc = FrontingMigrationService(
        db: db,
        memberRepository: DriftMemberRepository(db.membersDao, null),
        frontingSessionRepository: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
          db.frontSessionCommentsDao,
          null,
        ),
        dataExportService: exportService,
        syncHandle: null,
        backupDirectoryProvider: () async => dir,
        clock: () => fixedNow,
        nonceRandom: pinnedRandom,
      );

      await expectLater(
        svc.prepareBackup(
          mode: MigrationMode.upgradeAndKeep,
          password: 'a-strong-password-12',
        ),
        throwsA(isA<BackupFileCollisionException>()),
      );
      // Pre-existing file is untouched (no overwrite).
      final bytes = await precreated.readAsBytes();
      expect(bytes, [1, 2, 3, 4]);
    });
  });
}

/// Random subclass that returns a fixed sequence of bytes via
/// `nextInt(256)`. Used to pin the backup filename's nonce hex.
class _PinnedRandom implements Random {
  _PinnedRandom(this._bytes);
  final List<int> _bytes;
  int _i = 0;

  @override
  int nextInt(int max) {
    final v = _bytes[_i % _bytes.length];
    _i++;
    return v % max;
  }

  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Delegates every method to [_inner] except the sentinel write paths,
/// which throw so the orphan-sentinel branch fails inside the Drift
/// transaction - used to verify rollback semantics (settings unchanged,
/// PRISM1 file preserved).
class _ThrowingMemberRepository implements MemberRepository {
  _ThrowingMemberRepository(this._inner);

  final MemberRepository _inner;

  @override
  Future<void> createMember(Member member) async {
    throw StateError('Simulated createMember failure');
  }

  @override
  Future<void> updateMember(Member member) => _inner.updateMember(member);

  @override
  Future<void> deleteMember(String id) => _inner.deleteMember(id);

  @override
  Future<List<Member>> getAllMembers() => _inner.getAllMembers();

  @override
  Stream<List<Member>> watchAllMembers() => _inner.watchAllMembers();

  @override
  Stream<List<Member>> watchActiveMembers() => _inner.watchActiveMembers();

  @override
  Future<Member?> getMemberById(String id) => _inner.getMemberById(id);

  @override
  Stream<Member?> watchMemberById(String id) => _inner.watchMemberById(id);

  @override
  Future<List<Member>> getMembersByIds(List<String> ids) =>
      _inner.getMembersByIds(ids);

  @override
  Stream<List<Member>> watchMembersByIds(List<String> ids) =>
      _inner.watchMembersByIds(ids);

  @override
  Future<int> getCount() => _inner.getCount();

  @override
  Future<List<Member>> getDeletedLinkedMembers() =>
      _inner.getDeletedLinkedMembers();

  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);

  @override
  Future<({Member member, bool wasCreated})>
  ensureUnknownSentinelMember() async {
    throw StateError('Simulated ensureUnknownSentinelMember failure');
  }
}

/// Minimal stand-in for the FFI handle.  The migration service treats
/// the handle as opaque - the only interaction is passing it to the
/// resetSyncState callback, which we mock.
class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  @override
  void dispose() {}

  @override
  bool get isDisposed => false;
}

// ---------------------------------------------------------------------------
// Suppression-asserting repository decorators
//
// Wrap the real Drift repos and assert `SyncRecordMixin.isSuppressed ==
// true` at the moment any sync-emitting method (create/update/delete +
// the sentinel ensure path) runs. If the migration body ever issues a
// repository write outside `SyncRecordMixin.suppress(...)`, the assert
// throws synchronously and the test fails fast with a clear message.
//
// We deliberately wrap only the methods the migration body calls so
// the failure message points at the offending call site directly. All
// other methods are pass-through.
// ---------------------------------------------------------------------------

void _assertSuppressed(String method) {
  expect(
    SyncRecordMixin.isSuppressed,
    isTrue,
    reason:
        'Migration writes must run inside SyncRecordMixin.suppress; '
        '$method was called with isSuppressed=false',
  );
}

class _SuppressionAssertingFrontingSessionRepository
    implements FrontingSessionRepository {
  _SuppressionAssertingFrontingSessionRepository(this._inner);
  final FrontingSessionRepository _inner;

  @override
  Future<void> createSession(FrontingSession session) {
    _assertSuppressed('createSession');
    return _inner.createSession(session);
  }

  @override
  Future<void> updateSession(FrontingSession session) {
    _assertSuppressed('updateSession');
    return _inner.updateSession(session);
  }

  @override
  Future<void> deleteSession(String id) {
    _assertSuppressed('deleteSession');
    return _inner.deleteSession(id);
  }

  // Pass-throughs below - none of these emit sync ops on their own, so
  // they're safe to leave without an assert.
  @override
  Future<List<FrontingSession>> getAllSessions() => _inner.getAllSessions();
  @override
  Future<List<FrontingSession>> getFrontingSessions() =>
      _inner.getFrontingSessions();
  @override
  Stream<List<FrontingSession>> watchAllSessions() => _inner.watchAllSessions();
  @override
  Future<List<FrontingSession>> getActiveSessions() =>
      _inner.getActiveSessions();
  @override
  Future<List<FrontingSession>> getAllActiveSessionsUnfiltered() =>
      _inner.getAllActiveSessionsUnfiltered();
  @override
  Stream<List<FrontingSession>> watchActiveSessions() =>
      _inner.watchActiveSessions();
  @override
  Future<FrontingSession?> getActiveSession() => _inner.getActiveSession();
  @override
  Stream<FrontingSession?> watchActiveSession() => _inner.watchActiveSession();
  @override
  Stream<FrontingSession?> watchActiveSleepSession() =>
      _inner.watchActiveSleepSession();
  @override
  Stream<List<FrontingSession>> watchAllSleepSessions() =>
      _inner.watchAllSleepSessions();
  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) => _inner.getSleepStats(since: since, until: until);
  @override
  Stream<List<FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) => _inner.watchRecentSleepSessions(limit: limit);
  @override
  Future<FrontingSession?> getSessionById(String id) =>
      _inner.getSessionById(id);
  @override
  Stream<FrontingSession?> watchSessionById(String id) =>
      _inner.watchSessionById(id);
  @override
  Future<List<FrontingSession>> getSessionsForMember(String memberId) =>
      _inner.getSessionsForMember(memberId);
  @override
  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) =>
      _inner.getRecentSessions(limit: limit);
  @override
  Future<List<FrontingSession>> getRecentSleepSessions({int limit = 10}) =>
      _inner.getRecentSleepSessions(limit: limit);
  @override
  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) =>
      _inner.watchRecentSessions(limit: limit);
  @override
  Stream<List<FrontingSession>> watchRecentAllSessions({int limit = 30}) =>
      _inner.watchRecentAllSessions(limit: limit);
  @override
  Stream<List<FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) => _inner.watchSessionsOverlappingRange(start, end);
  @override
  Future<void> endSession(String id, DateTime endTime) =>
      _inner.endSession(id, endTime);
  @override
  Future<List<FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) => _inner.getSessionsBetween(start, end);
  @override
  Future<int> getCount() => _inner.getCount();
  @override
  Future<int> getFrontingCount() => _inner.getFrontingCount();
  @override
  Future<List<FrontingSession>> getDeletedLinkedSessions() =>
      _inner.getDeletedLinkedSessions();
  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);
  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) => _inner.getMemberFrontingCounts(
    recentLimit: recentLimit,
    startHour: startHour,
    endHour: endHour,
    withinDays: withinDays,
  );
}

class _SuppressionAssertingFrontSessionCommentsRepository
    implements FrontSessionCommentsRepository {
  _SuppressionAssertingFrontSessionCommentsRepository(this._inner);
  final FrontSessionCommentsRepository _inner;

  @override
  Future<void> createComment(FrontSessionComment comment) {
    _assertSuppressed('createComment');
    return _inner.createComment(comment);
  }

  @override
  Future<void> updateComment(FrontSessionComment comment) {
    _assertSuppressed('updateComment');
    return _inner.updateComment(comment);
  }

  @override
  Future<void> deleteComment(String id) {
    _assertSuppressed('deleteComment');
    return _inner.deleteComment(id);
  }

  @override
  Stream<List<FrontSessionComment>> watchCommentsForRange(TimeRange range) =>
      _inner.watchCommentsForRange(range);

  @override
  Stream<int> watchCommentCountForRange(TimeRange range) =>
      _inner.watchCommentCountForRange(range);

  @override
  Stream<List<FrontSessionComment>> watchAllComments() =>
      _inner.watchAllComments();

  @override
  Future<List<FrontSessionComment>> getAllComments() => _inner.getAllComments();
}

class _SuppressionAssertingMemberRepository implements MemberRepository {
  _SuppressionAssertingMemberRepository(this._inner);
  final MemberRepository _inner;

  @override
  Future<({Member member, bool wasCreated})>
  ensureUnknownSentinelMember() async {
    _assertSuppressed('ensureUnknownSentinelMember');
    return _inner.ensureUnknownSentinelMember();
  }

  @override
  Future<void> createMember(Member member) {
    _assertSuppressed('createMember');
    return _inner.createMember(member);
  }

  @override
  Future<void> updateMember(Member member) {
    _assertSuppressed('updateMember');
    return _inner.updateMember(member);
  }

  @override
  Future<void> deleteMember(String id) {
    _assertSuppressed('deleteMember');
    return _inner.deleteMember(id);
  }

  @override
  Future<List<Member>> getAllMembers() => _inner.getAllMembers();
  @override
  Stream<List<Member>> watchAllMembers() => _inner.watchAllMembers();
  @override
  Stream<List<Member>> watchActiveMembers() => _inner.watchActiveMembers();
  @override
  Future<Member?> getMemberById(String id) => _inner.getMemberById(id);
  @override
  Stream<Member?> watchMemberById(String id) => _inner.watchMemberById(id);
  @override
  Future<List<Member>> getMembersByIds(List<String> ids) =>
      _inner.getMembersByIds(ids);
  @override
  Stream<List<Member>> watchMembersByIds(List<String> ids) =>
      _inner.watchMembersByIds(ids);
  @override
  Future<int> getCount() => _inner.getCount();
  @override
  Future<List<Member>> getDeletedLinkedMembers() =>
      _inner.getDeletedLinkedMembers();
  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);
}
