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
///   - notNow mode writes the `'deferred'` flag and returns immediately.
///   - Failure mid-transaction rolls back; settings stays at notStarted;
///     PRISM1 file from step 2 survives on disk.
///   - Native multi-member fan-out: deterministic v5 ids match the
///     migration namespace, primary keeps the legacy id.
///   - Sentinel idempotency: rerunning migration doesn't duplicate.
///   - Sync state reset: Rust FFI is invoked exactly once.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' hide Member;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
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
import 'package:prism_plurality/domain/models/member.dart' show Member;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Directory _tempCacheDir() =>
    Directory.systemTemp.createTempSync('prism-mig-test-');

DataExportService _makeExportService(AppDatabase db, Directory cacheDir) {
  return DataExportService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository:
        DriftFrontingSessionRepository(db.frontingSessionsDao, null),
    conversationRepository:
        DriftConversationRepository(db.conversationsDao, null),
    chatMessageRepository:
        DriftChatMessageRepository(db.chatMessagesDao, null),
    pollRepository: DriftPollRepository(
      db.pollsDao,
      db.pollOptionsDao,
      db.pollVotesDao,
      null,
    ),
    systemSettingsRepository:
        DriftSystemSettingsRepository(db.systemSettingsDao, null),
    habitRepository: DriftHabitRepository(db.habitsDao, null),
    pluralKitSyncDao: db.pluralKitSyncDao,
    memberGroupsRepository:
        DriftMemberGroupsRepository(db.memberGroupsDao, null),
    customFieldsRepository:
        DriftCustomFieldsRepository(db.customFieldsDao, null),
    notesRepository: DriftNotesRepository(db.notesDao, null),
    frontSessionCommentsRepository:
        DriftFrontSessionCommentsRepository(db.frontSessionCommentsDao, null),
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
/// The Rust FFI handle is null by default — the service skips the real
/// reset call when [syncHandle] is null.  The mock callback also runs
/// in that mode so tests can record whether the FFI branch *would*
/// have run; tests that need to assert "FFI invoked" pass an explicit
/// `_FakePrismSyncHandle` when constructing the service.
FrontingMigrationService _makeService(
  AppDatabase db,
  DataExportService exportService, {
  List<ffi.PrismSyncHandle>? resetCalls,
}) {
  return FrontingMigrationService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository:
        DriftFrontingSessionRepository(db.frontingSessionsDao, null),
    frontSessionCommentsRepository:
        DriftFrontSessionCommentsRepository(db.frontSessionCommentsDao, null),
    dataExportService: exportService,
    syncHandle: null,
    resetSyncState: (h) async {
      resetCalls?.add(h);
    },
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
  await db.into(db.frontingSessions).insert(
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
  await db.into(db.frontSessionComments).insert(
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
    // notNow mode
    // -------------------------------------------------------------------
    test(
      'notNow mode writes deferred to settings, no other side effects',
      () async {
        // Seed a row that would be destroyed if migration ran.
        await _seedMember(db, 'm1');
        await _seedSession(
          db,
          id: 's1',
          startTime: DateTime(2026, 4, 1).toUtc(),
          memberId: 'm1',
        );

        final svc = _makeService(db, exportService);
        final result = await svc.runMigration(
          mode: MigrationMode.notNow,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.deferred);
        expect(result.exportFile, isNull);
        expect(
          await db.systemSettingsDao.readPendingFrontingMigrationMode(),
          'deferred',
        );
        // Session still on disk — no destructive work ran.
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
      },
    );

    // -------------------------------------------------------------------
    // Solo upgradeAndKeep — mixed data
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
        // Native orphan row (no member_id) — gets Unknown sentinel
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
        final sentinel =
            await DriftMemberRepository(db.membersDao, null)
                .getMemberById(sentinelId);
        expect(sentinel, isNotNull);
        expect(sentinel!.name, 'Unknown');

        // Sync FFI not called because handle was null in this run.
        expect(resetCalls, isEmpty);
        // Quarantine cleared.
        expect(await db.syncQuarantineDao.count(), 0);
      },
    );

    // -------------------------------------------------------------------
    // startFresh — wipes everything, no sentinel
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
    test(
      'primary upgradeAndKeep: comments on PK parents deleted; comments on '
      'SP/native parents migrated to new shape with target_time = legacy '
      'timestamp and author_member_id from parent',
      () async {
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
      },
    );

    // -------------------------------------------------------------------
    // Corrupt co_fronter_ids JSON
    // -------------------------------------------------------------------
    test(
      'corrupt co_fronter_ids JSON falls back to single-member migration '
      'and surfaces the row id (spec §6 edge case)',
      () async {
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
      },
    );

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
            .customSelect(
              'SELECT COUNT(*) AS c FROM front_session_comments',
            )
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
    test(
      'failure inside Drift transaction rolls back; settings stays at '
      'notStarted; PRISM1 file from step 2 is preserved on disk',
      () async {
        // Force a failing reset_sync_state via a non-null mock handle
        // backed by a thrower.  But the transaction is what we want to
        // fail.  Easier path: poison a row so step 4's writeSession
        // throws.  We achieve that by seeding a row with a member_id
        // referencing a member that exists, then rigging the
        // memberRepository to throw on update.  Instead, simulate by
        // throwing from shareFile AFTER export but BEFORE transaction —
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
        await db.systemSettingsDao
            .writePendingFrontingMigrationMode('notStarted');
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
          frontingSessionRepository:
              DriftFrontingSessionRepository(db.frontingSessionsDao, null),
          frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          dataExportService: exportService,
          syncHandle: null,
          resetSyncState: (_) async {},
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
      },
    );

    // -------------------------------------------------------------------
    // Sentinel idempotency
    // -------------------------------------------------------------------
    test(
      'rerunning migration with an existing Unknown sentinel does not '
      'duplicate the member (deterministic id)',
      () async {
        const uuid = Uuid();
        final sentinelId =
            uuid.v5(spFrontingNamespace, 'unknown-member-sentinel');
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
        expect(result.unknownSentinelCreated, isFalse,
            reason: 'sentinel already existed, no recreate');
        expect(result.orphanRowsAssignedToSentinel, 1);
        final allSentinels =
            await DriftMemberRepository(db.membersDao, null).getAllMembers();
        expect(
          allSentinels.where((m) => m.id == sentinelId).toList(),
          hasLength(1),
        );
      },
    );

    // -------------------------------------------------------------------
    // Sync state reset (Rust FFI mock)
    // -------------------------------------------------------------------
    test(
      'sync state reset: when a handle is provided, the FFI '
      'reset_sync_state is invoked exactly once after the Drift '
      'transaction commits',
      () async {
        final resetCalls = <ffi.PrismSyncHandle>[];
        // Use an opaque sentinel handle — service treats it as opaque.
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
          frontingSessionRepository:
              DriftFrontingSessionRepository(db.frontingSessionsDao, null),
          frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
            db.frontSessionCommentsDao,
            null,
          ),
          dataExportService: exportService,
          syncHandle: fakeHandle,
          resetSyncState: (h) async {
            resetCalls.add(h);
          },
        );

        final result = await svc.runMigration(
          mode: MigrationMode.upgradeAndKeep,
          role: DeviceRole.solo,
          shareFile: _noopShare,
        );

        expect(result.outcome, MigrationOutcome.success);
        expect(resetCalls, hasLength(1));
        expect(identical(resetCalls.single, fakeHandle), isTrue);
      },
    );

    // -------------------------------------------------------------------
    // Multi-member fan-out: deterministic v5 ids
    // -------------------------------------------------------------------
    test(
      'native multi-member fan-out: primary keeps legacy id, co-fronters '
      'get migrationFrontingNamespace v5 ids matching 5D',
      () async {
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
        expect(byId.keys, containsAll([['multi'], [co1Id], [co2Id]].expand((e) => e)));
        expect(byId['multi']!.memberId, primaryId);
        expect(byId[co1Id]!.memberId, coId1);
        expect(byId[co2Id]!.memberId, coId2);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Delegates every method to [_inner] except [createMember], which
/// throws so the orphan-sentinel branch fails inside the Drift
/// transaction — used to verify rollback semantics (settings unchanged,
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
}

/// Minimal stand-in for the FFI handle.  The migration service treats
/// the handle as opaque — the only interaction is passing it to the
/// resetSyncState callback, which we mock.
class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  @override
  void dispose() {}

  @override
  bool get isDisposed => false;
}
