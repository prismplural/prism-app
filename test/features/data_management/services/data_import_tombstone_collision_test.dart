/// Regression coverage for the data-import unique-constraint catch-site.
///
/// Sibling to `pluralkit_sync_tombstone_collision_test.dart`. Different
/// entry point, same shape: the partial unique indexes
/// `idx_members_pluralkit_uuid`, `idx_members_pluralkit_id`, and
/// `idx_fronting_sessions_pluralkit_uuid` cover tombstones (no
/// `is_deleted = 0` clause). The full-export importer used to dedup
/// against `getAllMembers()` / `getAllSessions()`, both of which filter
/// tombstones, so an imported row whose PK link matched a soft-deleted
/// local row would throw `SQLITE_CONSTRAINT_UNIQUE` and roll back the
/// entire import transaction.
///
/// See `docs/plans/data-import-tombstone-collision.md`.
library;

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
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
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataImportService _makeImport(AppDatabase db) => DataImportService(
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
  memberGroupsRepository: DriftMemberGroupsRepository(db.memberGroupsDao, null),
  customFieldsRepository: DriftCustomFieldsRepository(db.customFieldsDao, null),
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
);

String _exportJson({
  List<Map<String, dynamic>> headmates = const [],
  List<Map<String, dynamic>> frontSessions = const [],
  List<Map<String, dynamic>> sleepSessions = const [],
}) {
  final now = DateTime(2026, 4, 25, 10, 0, 0).toUtc().toIso8601String();
  return jsonEncode({
    'formatVersion': '2025.1',
    'version': '3.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': headmates.length + frontSessions.length + sleepSessions.length,
    'headmates': headmates,
    'frontSessions': frontSessions,
    'sleepSessions': sleepSessions,
    'conversations': [],
    'messages': [],
    'polls': [],
    'pollOptions': [],
    'systemSettings': [],
    'habits': [],
    'habitCompletions': [],
  });
}

Map<String, dynamic> _headmateJson({
  required String id,
  String name = 'Imported',
  String? pluralkitUuid,
  String? pluralkitId,
  String? parentSystemId,
}) {
  final now = DateTime(2026, 4, 25, 10, 0, 0).toUtc().toIso8601String();
  return {
    'id': id,
    'name': name,
    'isActive': true,
    'createdAt': now,
    'displayOrder': 0,
    'isAdmin': false,
    'customColorEnabled': false,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
    if (pluralkitId != null) 'pluralkitId': pluralkitId,
    if (parentSystemId != null) 'parentSystemId': parentSystemId,
  };
}

Map<String, dynamic> _frontJson({
  required String id,
  String? headmateId,
  String? pluralkitUuid,
}) {
  final now = DateTime(2026, 4, 25, 11, 0, 0).toUtc().toIso8601String();
  return {
    'id': id,
    'startTime': now,
    if (headmateId != null) 'headmateId': headmateId,
    if (pluralkitUuid != null) 'pluralkitUuid': pluralkitUuid,
  };
}

Map<String, dynamic> _sleepJson({required String id}) {
  final now = DateTime(2026, 4, 25, 23, 0, 0).toUtc().toIso8601String();
  return {
    'id': id,
    'startTime': now,
    'quality': 0,
    'isHealthKitImport': false,
  };
}

void main() {
  group('DataImportService tombstone unique-constraint collisions', () {
    late AppDatabase db;
    late DataImportService importService;

    setUp(() {
      db = _makeDb();
      importService = _makeImport(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'fronting session import skips a row whose pluralkit_uuid collides '
      'with a soft-deleted local tombstone',
      () async {
        // Seed a tombstone carrying pluralkit_uuid='X'. The partial unique
        // index covers tombstones, so a future INSERT with the same UUID
        // would throw SQLITE_CONSTRAINT_UNIQUE without the fix.
        await db.frontingSessionsDao.insertSession(
          FrontingSessionsCompanion.insert(
            id: 'tombstone-id',
            startTime: DateTime(2026, 4, 1, 12),
            memberId: const drift.Value('local-member-id'),
            pluralkitUuid: const drift.Value('X'),
            isDeleted: const drift.Value(true),
            deleteIntentEpoch: const drift.Value(0),
          ),
        );

        // Sanity: getAllSessions filters tombstones. The bug is that the
        // importer used to dedup off this active-only set.
        final activeBefore = await db.frontingSessionsDao.getAllSessions();
        expect(activeBefore, isEmpty);

        final json = _exportJson(
          frontSessions: [
            _frontJson(
              id: 'imported-id',
              headmateId: 'local-member-id',
              pluralkitUuid: 'X',
            ),
          ],
        );

        final result = await importService.importData(json);

        // The collision was caught at the dedup layer — no insert attempted,
        // counter reflects 0 created, the import transaction committed
        // (rather than rolled back), and the tombstone is unchanged.
        expect(result.frontSessionsCreated, 0);

        final liveWithSamePkUuid = await (db.select(db.frontingSessions)
              ..where(
                (s) =>
                    s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
              ))
            .get();
        expect(liveWithSamePkUuid, isEmpty);

        final tombstone = await (db.select(
          db.frontingSessions,
        )..where((s) => s.id.equals('tombstone-id'))).getSingle();
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.pluralkitUuid, 'X');
      },
    );

    test(
      'member import skips a row whose pluralkitUuid collides with a '
      'soft-deleted local tombstone',
      () async {
        // Seed a tombstoned member carrying pluralkit_uuid='m1'.
        await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'tombstoned-member',
            name: 'Old Name',
            emoji: const drift.Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            pluralkitUuid: const drift.Value('m1'),
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          headmates: [
            _headmateJson(
              id: 'imported-member',
              name: 'New Name',
              pluralkitUuid: 'm1',
            ),
          ],
        );

        final result = await importService.importData(json);

        expect(result.membersCreated, 0);

        final liveWithSamePkUuid = await (db.select(db.members)
              ..where(
                (m) => m.pluralkitUuid.equals('m1') & m.isDeleted.equals(false),
              ))
            .get();
        expect(liveWithSamePkUuid, isEmpty);

        final tombstone = await (db.select(
          db.members,
        )..where((m) => m.id.equals('tombstoned-member'))).getSingle();
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.pluralkitUuid, 'm1');
      },
    );

    test(
      'member import skips a row whose pluralkitId collides with a '
      'soft-deleted local tombstone',
      () async {
        await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'tombstoned-member',
            name: 'Old Name',
            emoji: const drift.Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            pluralkitId: const drift.Value('abcde'),
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          headmates: [
            _headmateJson(
              id: 'imported-member',
              pluralkitId: 'abcde',
            ),
          ],
        );

        final result = await importService.importData(json);

        expect(result.membersCreated, 0);

        final liveWithSamePkId = await (db.select(db.members)
              ..where(
                (m) => m.pluralkitId.equals('abcde') & m.isDeleted.equals(false),
              ))
            .get();
        expect(liveWithSamePkId, isEmpty);
      },
    );

    test(
      'fronting session import succeeds when no tombstone collision exists',
      () async {
        // Tombstone with pluralkit_uuid='X', import row with 'Y' — no
        // collision, the import row should land normally.
        //
        // Seed the local member with a pluralkit_uuid so the rescue
        // importer's empty-pkMemberIdsJson fallback can derive the
        // canonical (switch, member) deterministic id (codex P1 #10).
        // Without a local pluralkit_uuid the rescue row is correctly
        // skipped — that's covered by other tests.
        await db.into(db.members).insert(
              MembersCompanion.insert(
                id: 'local-member-id',
                name: 'Local',
                createdAt: DateTime(2026, 1, 1),
                pluralkitUuid: const drift.Value('member-pk-uuid'),
              ),
            );
        await db.frontingSessionsDao.insertSession(
          FrontingSessionsCompanion.insert(
            id: 'tombstone-id',
            startTime: DateTime(2026, 4, 1, 12),
            memberId: const drift.Value('local-member-id'),
            pluralkitUuid: const drift.Value('X'),
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          frontSessions: [
            _frontJson(
              id: 'imported-id',
              headmateId: 'local-member-id',
              pluralkitUuid: 'Y',
            ),
          ],
        );

        final result = await importService.importData(json);

        expect(result.frontSessionsCreated, 1);

        final live = await (db.select(db.frontingSessions)
              ..where((s) => s.isDeleted.equals(false)))
            .get();
        expect(live, hasLength(1));
        // Row id is now the deterministic v5(switchUuid, memberPkUuid)
        // — see derivePkSessionId — not the legacy `imported-id`. The
        // legacy id would have produced two rows on a future API
        // re-import, defeating the field-LWW correction contract.
        expect(live.single.pluralkitUuid, 'Y');
        expect(live.single.memberId, 'local-member-id');
      },
    );

    test(
      'fronting session import skips a row whose id collides with a '
      'soft-deleted tombstone (id-dedup preserved through the fix)',
      () async {
        await db.frontingSessionsDao.insertSession(
          FrontingSessionsCompanion.insert(
            id: 'shared-id',
            startTime: DateTime(2026, 4, 1, 12),
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          frontSessions: [_frontJson(id: 'shared-id')],
        );

        final result = await importService.importData(json);

        expect(result.frontSessionsCreated, 0);

        // The tombstone is still the only row, untouched.
        final allRows = await db.select(db.frontingSessions).get();
        expect(allRows, hasLength(1));
        expect(allRows.single.isDeleted, isTrue);
      },
    );

    test(
      'sleep session import skips a row whose id collides with a deleted '
      'normal-session tombstone (table-wide id dedup)',
      () async {
        // Sleep and normal share the same primary-key namespace in
        // `fronting_sessions`. A deleted normal-session tombstone with the
        // same id as an imported sleep row used to slip past the
        // sleep-only dedup and hit the row-level primary key.
        await db.frontingSessionsDao.insertSession(
          FrontingSessionsCompanion.insert(
            id: 'shared-id',
            startTime: DateTime(2026, 4, 1, 12),
            sessionType: const drift.Value(0), // normal
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          sleepSessions: [_sleepJson(id: 'shared-id')],
        );

        final result = await importService.importData(json);

        expect(result.sleepSessionsCreated, 0);

        final allRows = await db.select(db.frontingSessions).get();
        expect(allRows, hasLength(1));
        // Tombstone is unchanged: still session_type=0 (normal) and
        // is_deleted=true. The sleep import did not flip its type.
        expect(allRows.single.sessionType, 0);
        expect(allRows.single.isDeleted, isTrue);
      },
    );

    test(
      'second-pass parentSystemId update does not revive a member tombstone',
      () async {
        // Seed a tombstoned member with id='M', no parent. The id-dedup
        // skips the import row's create. The second-pass parent update
        // used to call updateMember on the tombstone (because
        // getMemberById doesn't filter is_deleted), which would emit a
        // sync op with is_deleted=false and effectively revive the row.
        await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'M',
            name: 'Deleted',
            emoji: const drift.Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            isDeleted: const drift.Value(true),
          ),
        );

        final json = _exportJson(
          headmates: [
            _headmateJson(
              id: 'M',
              name: 'Imported',
              parentSystemId: 'P',
            ),
            _headmateJson(id: 'P', name: 'Parent System'),
          ],
        );

        final result = await importService.importData(json);

        // 'P' is brand new — it should be created. 'M' should NOT be
        // created (id-dedup) and the tombstone should NOT be flipped.
        expect(result.membersCreated, 1);

        final tombstone = await (db.select(
          db.members,
        )..where((m) => m.id.equals('M'))).getSingle();
        expect(
          tombstone.isDeleted,
          isTrue,
          reason: 'Second-pass parent update must not revive tombstones',
        );
        expect(
          tombstone.parentSystemId,
          isNull,
          reason: 'Second-pass parent update must not rewrite tombstones',
        );

        final parent = await (db.select(
          db.members,
        )..where((m) => m.id.equals('P'))).getSingle();
        expect(parent.isDeleted, isFalse);
      },
    );
  });
}
