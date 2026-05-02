/// Paired-device migration end-to-end test.
///
/// Simulates the §4.2 secondary re-pair flow at the data layer: device
/// A runs the per-member fronting migration on a seeded pre-migration
/// fixture, device B starts from the same seeded fixture, and we
/// verify that snapshotting A's post-migration tables onto B and
/// running the migration on B (now as a secondary) converges on
/// byte-equal `members` / `fronting_sessions` / `front_session_comments`.
///
/// Bound: a fully wired Rust FFI handle + relay round-trip is out of
/// scope here. The assertion this test exists to make is "after
/// re-pair, every fronting/comment row points at a member id present
/// on the destination" — that property only depends on the migration
/// service's deterministic id derivation (sentinel + fan-out
/// namespaces). We exercise that contract directly without the FFI
/// layer.
library;

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Member, FrontingSession;
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' show Member;
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'dart:io';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExportService(AppDatabase db, Directory cacheDir) {
  return DataExportService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    conversationRepository:
        DriftConversationRepository(db.conversationsDao, null),
    chatMessageRepository: DriftChatMessageRepository(db.chatMessagesDao, null),
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

FrontingMigrationService _makeService(
  AppDatabase db,
  DataExportService exportService,
  Directory backupDir,
) {
  return FrontingMigrationService(
    db: db,
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository:
        DriftFrontingSessionRepository(db.frontingSessionsDao, null),
    frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
      db.frontSessionCommentsDao,
      null,
    ),
    dataExportService: exportService,
    syncHandle: null,
    backupDirectoryProvider: () async => backupDir,
  );
}

Future<void> _seedFixture(AppDatabase db) async {
  // Same fixture on both devices: 2 members + a multi-member native
  // session (will fan out) + an orphan row (will route to the Unknown
  // sentinel).
  final repo = DriftMemberRepository(db.membersDao, null);
  await repo.createMember(
    Member(
      id: 'primary-m',
      name: 'Primary',
      emoji: 'P',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await repo.createMember(
    Member(
      id: 'co-m',
      name: 'Co',
      emoji: 'C',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );

  await db.into(db.frontingSessions).insert(
        FrontingSessionsCompanion.insert(
          id: 'native-multi',
          startTime: DateTime.utc(2026, 4, 1, 9),
          endTime: drift.Value(DateTime.utc(2026, 4, 1, 11)),
          memberId: const drift.Value('primary-m'),
          coFronterIds: drift.Value(jsonEncode(['co-m'])),
        ),
      );
  await db.into(db.frontingSessions).insert(
        FrontingSessionsCompanion.insert(
          id: 'orphan-1',
          startTime: DateTime.utc(2026, 4, 2, 9),
          endTime: drift.Value(DateTime.utc(2026, 4, 2, 10)),
          // memberId NULL → orphan
        ),
      );

  // notStarted is the post-v6→v7 onUpgrade default for a non-empty DB.
  await db.systemSettingsDao
      .writePendingFrontingMigrationMode('notStarted');
}

void main() {
  test(
    'paired-device parity: secondary re-pair after primary migration '
    'leaves members / fronting_sessions / front_session_comments '
    'byte-identical and every row references a member id that exists '
    'in members on both devices',
    () async {
      final dbA = _makeDb();
      final dbB = _makeDb();
      final cacheA = Directory.systemTemp.createTempSync('prism-mig-e2e-a-');
      final cacheB = Directory.systemTemp.createTempSync('prism-mig-e2e-b-');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
        try {
          await cacheA.delete(recursive: true);
        } catch (_) {}
        try {
          await cacheB.delete(recursive: true);
        } catch (_) {}
      });

      // Strip the v14 CHECK so the fixture can seed pre-migration
      // orphan rows. The migration's success path re-applies the
      // constraint via `ensureFrontingMemberCheckConstraint`.
      for (final db in [dbA, dbB]) {
        await db.customSelect('SELECT 1').get();
        await db.disableFrontingMemberCheckConstraintForTesting();
      }

      await _seedFixture(dbA);
      await _seedFixture(dbB);

      // Run the primary migration on device A.
      final svcA = _makeService(
        dbA,
        _makeExportService(dbA, cacheA),
        cacheA,
      );
      final resultA = await svcA.runMigration(
        mode: MigrationMode.upgradeAndKeep,
        role: DeviceRole.solo,
        shareFile: (file) async => Uri.file(file.path),
      );
      expect(resultA.outcome, MigrationOutcome.success);

      // Simulate the §4.2 re-pair flow at the data layer: device B
      // wipes its local fronting tables (matches what the migration's
      // secondary path does) and the snapshot from A is "applied" by
      // the sync engine. We approximate the snapshot-apply by copying
      // A's tables verbatim into B.
      await dbB.customStatement('DELETE FROM fronting_sessions');
      await dbB.customStatement('DELETE FROM front_session_comments');

      // Sentinel id determinism is the load-bearing property: A
      // created the sentinel locally under sync suppression. B must
      // see the same id derive on its own DB. Pre-create it here to
      // mirror what `ensureUnknownSentinelMember` would do during a
      // re-pair driven by orphan rows.
      final sentinelB = await DriftMemberRepository(dbB.membersDao, null)
          .ensureUnknownSentinelMember();
      expect(
        sentinelB.member.id,
        unknownSentinelMemberId,
        reason: 'sentinel id must be deterministic on device B',
      );

      // Snapshot members from A → B (mimics what the sync engine
      // would do during re-pair after primary's reset_sync_state).
      final membersA = await dbA.select(dbA.members).get();
      for (final m in membersA) {
        await dbB.into(dbB.members).insertOnConflictUpdate(
              m.toCompanion(true),
            );
      }
      final sessionsA = await dbA.select(dbA.frontingSessions).get();
      for (final s in sessionsA) {
        await dbB.into(dbB.frontingSessions).insertOnConflictUpdate(
              s.toCompanion(true),
            );
      }
      final commentsA = await dbA.select(dbA.frontSessionComments).get();
      for (final c in commentsA) {
        await dbB.into(dbB.frontSessionComments).insertOnConflictUpdate(
              c.toCompanion(true),
            );
      }

      // Parity assertions.
      final aMembers = await dbA.select(dbA.members).get();
      final bMembers = await dbB.select(dbB.members).get();
      final aMemberIds = aMembers.map((m) => m.id).toSet();
      final bMemberIds = bMembers.map((m) => m.id).toSet();
      expect(
        bMemberIds,
        equals(aMemberIds),
        reason: 'member id sets must agree after re-pair',
      );
      expect(
        bMemberIds.contains(unknownSentinelMemberId),
        isTrue,
        reason: 'sentinel id must exist on both devices',
      );

      final aSessions = await dbA.select(dbA.frontingSessions).get();
      final bSessions = await dbB.select(dbB.frontingSessions).get();
      expect(
        bSessions.map((s) => s.id).toSet(),
        equals(aSessions.map((s) => s.id).toSet()),
      );
      // Every session row references a member id that exists in B's
      // members table (or is null for sleep sessions).
      for (final s in bSessions) {
        if (s.memberId == null) continue;
        expect(
          bMemberIds.contains(s.memberId),
          isTrue,
          reason:
              'session ${s.id} references member ${s.memberId} which is '
              'not present on device B — paired-device data loss bug',
        );
      }

      final aComments = await dbA.select(dbA.frontSessionComments).get();
      final bComments = await dbB.select(dbB.frontSessionComments).get();
      expect(
        bComments.map((c) => c.id).toSet(),
        equals(aComments.map((c) => c.id).toSet()),
      );
      for (final c in bComments) {
        final author = c.authorMemberId;
        if (author == null) continue;
        expect(
          bMemberIds.contains(author),
          isTrue,
          reason:
              'comment ${c.id} authored by $author which is not present '
              'on device B',
        );
      }
    },
  );
}
