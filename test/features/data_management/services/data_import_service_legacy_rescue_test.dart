/// PRISM1 rescue importer (Phase 5D, spec §4.7).
///
/// The legacy-shape branch in `DataImportService.importData` exists so a
/// pre-0.7.0 PRISM1 export — with `co_fronter_ids`, `pk_member_ids_json`,
/// and comment `session_id` populated — can still re-import after the
/// per-member fronting refactor lands.
///
/// These tests pin the four rescue branches (PK fan-out with
/// deterministic v5 ids, SP 1:1, native multi-member fan-out, orphan →
/// Unknown sentinel) and the spec's load-bearing edge cases (corrupt
/// `co_fronter_ids` JSON falls back to single-member; PK short ids
/// without a local member match are counted as skipped, not crashed;
/// rescue-then-API-reimport produces correct boundaries via fresh HLCs).
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Member, FrontingSession;
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
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart' show Member;
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(AppDatabase db) => DataExportService(
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
      chatMessageRepository:
          DriftChatMessageRepository(db.chatMessagesDao, null),
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
    );

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
      chatMessageRepository:
          DriftChatMessageRepository(db.chatMessagesDao, null),
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
    );

String _envelope({
  List<Map<String, dynamic>> headmates = const [],
  List<Map<String, dynamic>> frontSessions = const [],
  List<Map<String, dynamic>> sleepSessions = const [],
  List<Map<String, dynamic>> frontSessionComments = const [],
}) {
  final now = DateTime(2026, 4, 25, 12, 0, 0).toUtc().toIso8601String();
  return jsonEncode({
    'formatVersion': '2025.1',
    'version': '3.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': headmates.length + frontSessions.length,
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
    if (frontSessionComments.isNotEmpty)
      'frontSessionComments': frontSessionComments,
  });
}

void main() {
  group('PRISM1 rescue importer (legacy-shape branch)', () {
    late AppDatabase db;
    late DataImportService importService;
    late DriftMemberRepository memberRepo;

    setUp(() {
      db = _makeDb();
      importService = _makeImport(db);
      memberRepo = DriftMemberRepository(db.membersDao, null);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'PK legacy-shape rows fan out per pk_member_ids_json with '
      'deterministic v5 ids and lossy boundaries preserved',
      () async {
        // Arrange: two local members linked to PK shorts "abcde" / "fghij"
        // with full UUIDs. The legacy PK row's `headmateId` ("alex") is
        // a relic from the old collapse — the rescue path ignores it
        // and rebuilds per-member rows from `pk_member_ids_json`.
        const alexLocalId = 'alex-local';
        const ezraLocalId = 'ezra-local';
        const alexPkUuid = '11111111-1111-4111-8111-111111111111';
        const ezraPkUuid = '22222222-2222-4222-8222-222222222222';
        const switchUuid = '99999999-9999-4999-8999-999999999999';
        await memberRepo.createMember(Member(
          id: alexLocalId,
          name: 'Alex',
          emoji: 'A',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'abcde',
          pluralkitUuid: alexPkUuid,
        ));
        await memberRepo.createMember(Member(
          id: ezraLocalId,
          name: 'Ezra',
          emoji: 'E',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'fghij',
          pluralkitUuid: ezraPkUuid,
        ));

        final start = DateTime.utc(2026, 4, 1, 9).toIso8601String();
        final end = DateTime.utc(2026, 4, 1, 11).toIso8601String();
        final json = _envelope(frontSessions: [
          {
            'id': 'legacy-pk-row',
            'startTime': start,
            'endTime': end,
            'headmateId': alexLocalId,
            'coFronterIds': [ezraLocalId], // legacy marker
            'pluralkitUuid': switchUuid,
            'pkMemberIdsJson': jsonEncode(['abcde', 'fghij']),
          },
        ]);

        // Act
        final result = await importService.importData(json);

        // Assert: two per-member rows with deterministic ids, both
        // carrying the lossy boundaries from the rescue file.
        final alexId = derivePkSessionId(switchUuid, alexPkUuid);
        final ezraId = derivePkSessionId(switchUuid, ezraPkUuid);
        expect(result.frontSessionsCreated, 2);
        expect(result.legacyPkShortIdsSkipped, 0);
        final rows = await db.frontingSessionsDao.getAllSessions();
        final byId = {for (final r in rows) r.id: r};
        expect(byId.keys, containsAll([alexId, ezraId]));
        expect(byId[alexId]!.memberId, alexLocalId);
        expect(byId[ezraId]!.memberId, ezraLocalId);
        expect(byId[alexId]!.pluralkitUuid, switchUuid);
        expect(byId[ezraId]!.pluralkitUuid, switchUuid);
        // Drift returns DateTime in local form; compare via
        // millisecondsSinceEpoch to ignore the local/UTC display
        // difference.
        expect(byId[alexId]!.startTime.toUtc(),
            DateTime.parse(start).toUtc());
        expect(byId[alexId]!.endTime!.toUtc(),
            DateTime.parse(end).toUtc());
      },
    );

    test(
      'rescue-then-API-reimport corrects PK boundaries via fresh HLCs '
      '(spec §4.7 critical test)',
      () async {
        // Spec: "rescue-then-API-reimport produces correct boundaries
        // (verifies fresh HLCs); rescue-only retains lossy boundaries."
        //
        // We can't drive the API importer directly here — instead we
        // simulate the second leg by writing a corrective row through
        // the same repository path, using the same deterministic id
        // the API importer would derive. The test asserts the corrected
        // boundaries land on disk, which is what field-LWW + fresh HLCs
        // guarantee in the real sync engine.
        //
        // The actual diff-sweep collision path is exercised end-to-end
        // by `pluralkit_sync_service_diff_sweep_test.dart` ("PRISM1
        // rescue collision upsert" group) — which catches the codex P1
        // #6 regression where the previous create-then-catch pattern
        // recorded the row id without writing the API truth.
        const memberId = 'm-corrective';
        const pkUuid = '33333333-3333-4333-8333-333333333333';
        const switchUuid = '44444444-4444-4444-8444-444444444444';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'M',
          emoji: 'M',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'mshrt',
          pluralkitUuid: pkUuid,
        ));

        // Lossy bounds in the rescue file (one row covering hours 9-11).
        final lossyStart = DateTime.utc(2026, 4, 1, 9);
        final lossyEnd = DateTime.utc(2026, 4, 1, 11);
        final json = _envelope(frontSessions: [
          {
            'id': 'lossy-row',
            'startTime': lossyStart.toIso8601String(),
            'endTime': lossyEnd.toIso8601String(),
            'headmateId': memberId,
            'coFronterIds': [],
            'pluralkitUuid': switchUuid,
            'pkMemberIdsJson': jsonEncode(['mshrt']),
          },
        ]);
        await importService.importData(json);

        // Rescue-only assertion: derived id present with lossy bounds.
        final derivedId = derivePkSessionId(switchUuid, pkUuid);
        var rows = await db.frontingSessionsDao.getAllSessions();
        var row = rows.firstWhere((r) => r.id == derivedId);
        expect(row.startTime.toUtc(), lossyStart);
        expect(row.endTime!.toUtc(), lossyEnd);

        // Simulated API re-import: corrective row at the same id with
        // tighter bounds (hours 9:30-10:30). The repository's
        // `syncRecordUpdate` path advances HLCs naturally; field-LWW
        // would take the corrective values on the next sync. We verify
        // the local DB carries the corrected bounds after the write.
        final correctStart = DateTime.utc(2026, 4, 1, 9, 30);
        final correctEnd = DateTime.utc(2026, 4, 1, 10, 30);
        final domainSession = await importService.frontingSessionRepository
            .getSessionById(derivedId);
        await importService.frontingSessionRepository.updateSession(
          domainSession!.copyWith(
            startTime: correctStart,
            endTime: correctEnd,
          ),
        );
        rows = await db.frontingSessionsDao.getAllSessions();
        row = rows.firstWhere((r) => r.id == derivedId);
        expect(row.startTime.toUtc(), correctStart,
            reason: 'API-corrective write must replace lossy bounds');
        expect(row.endTime!.toUtc(), correctEnd);
      },
    );

    test(
      'PK short id with no matching local member is counted as skipped, '
      'not crashed',
      () async {
        const alexLocalId = 'alex';
        const alexPkUuid = '11111111-1111-4111-8111-111111111111';
        const switchUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        await memberRepo.createMember(Member(
          id: alexLocalId,
          name: 'Alex',
          emoji: 'A',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'abcde',
          pluralkitUuid: alexPkUuid,
        ));

        final json = _envelope(frontSessions: [
          {
            'id': 'legacy-pk-orphan-shorts',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': alexLocalId,
            'coFronterIds': [],
            'pluralkitUuid': switchUuid,
            // "abcde" resolves; "ghost" doesn't.
            'pkMemberIdsJson': jsonEncode(['abcde', 'ghost']),
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        expect(result.legacyPkShortIdsSkipped, 1);
        final aliceId = derivePkSessionId(switchUuid, alexPkUuid);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows.map((r) => r.id), contains(aliceId));
      },
    );

    test(
      'SP legacy-shape rows tier 1: sp_id_map present → derive id via '
      'deriveSpSessionId(entityId) (review finding #43, WS4 step 6)',
      () async {
        const memberId = 'sp-member';
        const sessionId = 'sp-session-1';
        const spEntityId = 'sp-source-id-xyz';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'SP-M',
          emoji: 'S',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        // Seed sp_id_map so the rescue importer classifies this as SP
        // and resolves tier 1 (reverse-lookup → entityId → derive).
        await db.spImportDao.upsertMapping(
          SpIdMapTableCompanion.insert(
            spId: spEntityId,
            entityType: 'session',
            prismId: sessionId,
          ),
        );

        final json = _envelope(frontSessions: [
          {
            'id': sessionId,
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': memberId,
            'coFronterIds': [],
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        // Tier 1: id is the deterministic derivation, not the legacy
        // prismId. A future SP re-import producing the same entityId
        // collides on this id and field-LWW reconciles.
        final derivedId = deriveSpSessionId(spEntityId);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, derivedId);
        expect(rows.single.memberId, memberId);
        // Tier 1 hit, not tier 3 — counter stays zero.
        expect(result.legacySpIdPreservedCount, 0);
      },
    );

    test(
      'SP legacy-shape rows tier 3: no sp_id_map entry → preserve s.id '
      'and increment legacySpIdPreservedCount (review finding #43)',
      () async {
        const memberId = 'sp-member-tier3';
        const sessionId = 'random-v4-id-tier3';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'SP-M3',
          emoji: 'S',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        // Seed sp_id_map with the row's id but a DIFFERENT entityType
        // so resolveSpSessionPrismIds sees the row, but
        // resolveSpPrismToEntityId returns null for 'session'. To
        // exercise tier 3 we need the row to be classified SP-rescue
        // (sp_id_map.session has the prismId) but with no entity-id
        // entry. Trick: write the mapping with an empty spId so tier 1
        // detects '' and falls through to tier 3.
        await db.spImportDao.upsertMapping(
          SpIdMapTableCompanion.insert(
            spId: '',
            entityType: 'session',
            prismId: sessionId,
          ),
        );

        final json = _envelope(frontSessions: [
          {
            'id': sessionId,
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': memberId,
            'coFronterIds': [],
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        expect(result.legacySpIdPreservedCount, 1);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, sessionId);
        expect(rows.single.memberId, memberId);
      },
    );

    test(
      'native legacy multi-member fan-out: primary keeps id, '
      'co-fronters get migrationFrontingNamespace v5 ids',
      () async {
        const primaryId = 'primary-member';
        const coId1 = 'co-1';
        const coId2 = 'co-2';
        const sessionId = 'native-multi-1';
        for (final m in [primaryId, coId1, coId2]) {
          await memberRepo.createMember(Member(
            id: m,
            name: m,
            emoji: 'X',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ));
        }

        final json = _envelope(frontSessions: [
          {
            'id': sessionId,
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': primaryId,
            'coFronterIds': [coId1, coId2],
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 3);
        const uuid = Uuid();
        final co1Id = uuid.v5(
          migrationFrontingNamespace,
          '$sessionId:$coId1',
        );
        final co2Id = uuid.v5(
          migrationFrontingNamespace,
          '$sessionId:$coId2',
        );
        final rows = await db.frontingSessionsDao.getAllSessions();
        final byId = {for (final r in rows) r.id: r};
        expect(byId.keys, containsAll([sessionId, co1Id, co2Id]));
        expect(byId[sessionId]!.memberId, primaryId);
        expect(byId[co1Id]!.memberId, coId1);
        expect(byId[co2Id]!.memberId, coId2);
      },
    );

    test(
      'legacy detection: empty-but-present coFronterIds — orphan native '
      'row routes through rescue and assigns Unknown sentinel',
      () async {
        // Back-compat for files that DO carry an empty `coFronterIds`
        // key (some intermediate dev builds emitted them). The
        // explicit legacy-key sniff handles these directly.
        // No members seeded — orphan row arrives with member_id null.
        final json = _envelope(frontSessions: [
          {
            'id': 'orphan-1',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'coFronterIds': [], // legacy marker, empty
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        expect(result.unknownSentinelCreated, isTrue);

        const uuid = Uuid();
        final sentinelId =
            uuid.v5(spFrontingNamespace, 'unknown-member-sentinel');
        final members = await memberRepo.getAllMembers();
        expect(members.any((m) => m.id == sentinelId), isTrue);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows.single.id, 'orphan-1');
        expect(rows.single.memberId, sentinelId);
      },
    );

    test(
      'legacy detection: completely absent coFronterIds (real old shape) '
      '— orphan row still routes to rescue + Unknown sentinel '
      '(codex pass 3 #B-PASS3-P2)',
      () async {
        // Real pre-0.7 PRISM1 export shape: an orphan native row had
        // member_id NULL and an empty co_fronter_ids list, both of
        // which the v6/v7 exporter omitted from JSON entirely (toJson
        // skips nulls and empty lists). With no envelope marker (the
        // file pre-dates 0.7), there is NOTHING per-row that flags
        // legacy under the explicit-key sniff. Pre-fix the row leaked
        // into the new-shape importer and tried to write member_id
        // null, which v8's CHECK rejects. The broadened sniff
        // (no headmateId AND no coFronterIds key AND no new-shape
        // marker) routes it through rescue → Unknown sentinel.
        final json = _envelope(frontSessions: [
          {
            'id': 'orphan-real-pre-0-7',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            // No headmateId, no coFronterIds, no pkMemberIdsJson, no
            // sessionType/memberId — the real pre-0.7 orphan shape.
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        expect(result.unknownSentinelCreated, isTrue,
            reason: 'broadened detection must route this to rescue and '
                'create the Unknown sentinel');

        const uuid = Uuid();
        final sentinelId =
            uuid.v5(spFrontingNamespace, 'unknown-member-sentinel');
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows.single.id, 'orphan-real-pre-0-7');
        expect(rows.single.memberId, sentinelId,
            reason: 'orphan must land on Unknown sentinel, not member_id null');
      },
    );

    test(
      'legacy detection: completely absent legacy keys on a solo PK row '
      '(real old shape) routes through rescue and derives canonical '
      '(switch, member) v5 id (codex pass 3 #B-PASS3-P2)',
      () async {
        // Real pre-0.7 PRISM1 export shape for a solo PK row: the
        // exporter omitted empty co_fronter_ids and null
        // pk_member_ids_json. The row carries pluralkit_uuid +
        // headmateId only — under the old explicit-key sniff this
        // looked indistinguishable from a new-shape row, leaked into
        // the new-shape importer, and preserved the legacy random v4
        // id. A future PK API re-import then derives a different
        // deterministic id and produces two rows for the same
        // (switch, member) pair, defeating field-LWW boundary
        // correction. The broadened sniff (pluralkitUuid present
        // without sessionType/memberId markers) routes this to legacy
        // and the rescue path derives the canonical id from
        // local member.pluralkit_uuid.
        const memberLocalId = 'solo-pk-local';
        const memberPkUuid = '88888888-8888-4888-8888-888888888888';
        const switchUuid = '99999999-9999-4999-8999-999999999999';
        const legacyV4Id = 'legacy-random-v4';
        await memberRepo.createMember(Member(
          id: memberLocalId,
          name: 'Solo',
          emoji: 'S',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'spsht',
          pluralkitUuid: memberPkUuid,
        ));

        final json = _envelope(frontSessions: [
          {
            'id': legacyV4Id,
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': memberLocalId,
            'pluralkitUuid': switchUuid,
            // No coFronterIds key, no pkMemberIdsJson key, no
            // sessionType/memberId — the real pre-0.7 solo PK shape.
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        final derivedId = derivePkSessionId(switchUuid, memberPkUuid);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, derivedId,
            reason: 'broadened detection must route this through rescue, '
                'which derives the canonical (switch, member) v5 id');
        expect(rows.single.id, isNot(legacyV4Id),
            reason: 'legacy random v4 id must not leak through');
        expect(rows.single.memberId, memberLocalId);
        expect(rows.single.pluralkitUuid, switchUuid);
      },
    );

    test(
      'corrupt co_fronter_ids JSON falls back to single-member migration '
      'and logs the row id (spec §6 edge case)',
      () async {
        const primaryId = 'p-corrupt';
        await memberRepo.createMember(Member(
          id: primaryId,
          name: 'P',
          emoji: 'P',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final json = _envelope(frontSessions: [
          {
            'id': 'corrupt-co-row',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': primaryId,
            // Stringified, malformed JSON — the parser falls through to
            // an empty list; the raw text is preserved on the model so
            // the rescue importer can flag the row.
            'coFronterIds': '{not valid json',
          },
        ]);

        final result = await importService.importData(json);
        // Only the primary row gets written — no fan-out attempt.
        expect(result.frontSessionsCreated, 1);
        expect(result.legacyCorruptCoFronterRows, contains('corrupt-co-row'));
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows.single.id, 'corrupt-co-row');
        expect(rows.single.memberId, primaryId);
      },
    );

    test(
      'legacy comments join to parent session by sessionId and write '
      'new-shape target_time + author_member_id (spec §3.5 + §4.1 step 5)',
      () async {
        const memberId = 'm-comments';
        const sessionId = 'session-with-comments';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'C',
          emoji: 'C',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));

        final commentTimestamp = DateTime.utc(2026, 4, 1, 10);
        final json = _envelope(
          frontSessions: [
            {
              'id': sessionId,
              'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
              'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
              'headmateId': memberId,
              'coFronterIds': [],
            },
          ],
          frontSessionComments: [
            {
              'id': 'comment-1',
              'sessionId': sessionId,
              'body': 'feeling great',
              'timestamp': commentTimestamp.toIso8601String(),
              'createdAt': DateTime.utc(2026, 4, 2).toIso8601String(),
            },
          ],
        );

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 1);
        expect(result.frontSessionCommentsCreated, 1);

        // Read raw row via custom select to confirm the target_time and
        // author_member_id columns landed (the repository's
        // watchAllComments would also work, but raw assertion is more
        // explicit about which column the value lives in).
        final commentRow = await db
            .customSelect(
              'SELECT target_time, author_member_id FROM '
              'front_session_comments WHERE id = ?',
              variables: [drift.Variable.withString('comment-1')],
            )
            .getSingle();
        final targetMs =
            commentRow.read<DateTime?>('target_time')?.toUtc();
        expect(targetMs, commentTimestamp.toUtc());
        expect(commentRow.read<String?>('author_member_id'), memberId);
      },
    );

    test(
      'legacy PK comments derive author from the first resolved PK '
      'member of the parent switch',
      () async {
        const alexLocalId = 'alex-pk-comm';
        const ezraLocalId = 'ezra-pk-comm';
        const alexPkUuid = 'aaaaaaaa-1111-4111-8111-111111111111';
        const ezraPkUuid = 'bbbbbbbb-2222-4222-8222-222222222222';
        const switchUuid = 'cccccccc-3333-4333-8333-333333333333';
        await memberRepo.createMember(Member(
          id: alexLocalId,
          name: 'Alex',
          emoji: 'A',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'aaa',
          pluralkitUuid: alexPkUuid,
        ));
        await memberRepo.createMember(Member(
          id: ezraLocalId,
          name: 'Ezra',
          emoji: 'E',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'eee',
          pluralkitUuid: ezraPkUuid,
        ));

        final json = _envelope(
          frontSessions: [
            {
              'id': 'pk-with-comment',
              'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
              'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
              'headmateId': alexLocalId,
              'coFronterIds': [ezraLocalId],
              'pluralkitUuid': switchUuid,
              // First short id resolves to Alex; the importer picks
              // Alex's local id as the comment author per spec.
              'pkMemberIdsJson': jsonEncode(['aaa', 'eee']),
            },
          ],
          frontSessionComments: [
            {
              'id': 'pk-comment-1',
              'sessionId': 'pk-with-comment',
              'body': 'pk note',
              'timestamp':
                  DateTime.utc(2026, 4, 1, 10).toIso8601String(),
              'createdAt': DateTime.utc(2026, 4, 2).toIso8601String(),
            },
          ],
        );

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 2);
        expect(result.frontSessionCommentsCreated, 1);

        final commentRow = await db
            .customSelect(
              'SELECT author_member_id FROM front_session_comments '
              'WHERE id = ?',
              variables: [drift.Variable.withString('pk-comment-1')],
            )
            .getSingle();
        expect(commentRow.read<String?>('author_member_id'), alexLocalId);
      },
    );

    test(
      'new-shape rows route through the standard import path, no fan-out, '
      'no v5 derivation, sessionType honored',
      () async {
        // No legacy markers — `memberId` + `sessionType` keys present
        // pin the row as new-shape.
        const memberId = 'new-shape-member';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'NS',
          emoji: 'N',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));

        final json = _envelope(frontSessions: [
          {
            'id': 'new-shape-row',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'memberId': memberId,
            'sessionType': 0,
          },
          {
            'id': 'new-shape-sleep',
            'startTime': DateTime.utc(2026, 4, 1, 22).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 2, 6).toIso8601String(),
            'memberId': memberId,
            'sessionType': 1,
            'quality': 4,
            'isHealthKitImport': true,
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 2);
        expect(result.legacyPkShortIdsSkipped, 0);
        expect(result.unknownSentinelCreated, isFalse);
        final rows = await db.frontingSessionsDao.getAllSessions();
        final byId = {for (final r in rows) r.id: r};
        expect(byId['new-shape-row']!.sessionType,
            SessionType.normal.index);
        expect(byId['new-shape-sleep']!.sessionType,
            SessionType.sleep.index);
        expect(byId['new-shape-sleep']!.quality, 4);
        expect(byId['new-shape-sleep']!.isHealthKitImport, isTrue);
      },
    );

    test(
      'migration-time export shape (legacy fields + sessionType on the '
      'same row) routes through the rescue path (codex P1 #2 regression)',
      () async {
        // The migration-time PRISM1 exporter emits BOTH the legacy
        // co_fronter_ids / pk_member_ids_json columns AND the new-shape
        // sessionType field on every row (the rescue file is meant to be
        // self-sufficient). The previous AND-NOT detection treated such
        // rows as new-shape and silently dropped the PK / native fan-out
        // — meaning every PK switch landed as a single non-fanned row,
        // every multi-member native session lost its co-fronters, and
        // the deterministic-id contract for future API re-import was
        // broken. This test pins the detection on the load-bearing
        // shape: a PK row with legacy markers + sessionType MUST fan
        // out per pk_member_ids_json.
        const alexLocalId = 'alex-mig';
        const ezraLocalId = 'ezra-mig';
        const alexPkUuid = '11111111-1111-4111-8111-111111111111';
        const ezraPkUuid = '22222222-2222-4222-8222-222222222222';
        const switchUuid = '99999999-9999-4999-8999-999999999999';
        await memberRepo.createMember(Member(
          id: alexLocalId,
          name: 'Alex',
          emoji: 'A',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'mga',
          pluralkitUuid: alexPkUuid,
        ));
        await memberRepo.createMember(Member(
          id: ezraLocalId,
          name: 'Ezra',
          emoji: 'E',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'mge',
          pluralkitUuid: ezraPkUuid,
        ));

        final json = _envelope(frontSessions: [
          {
            'id': 'mig-pk-row',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': alexLocalId,
            // Legacy markers — present on migration-time exports.
            'coFronterIds': [ezraLocalId],
            'pluralkitUuid': switchUuid,
            'pkMemberIdsJson': jsonEncode(['mga', 'mge']),
            // New-shape marker — also present on migration-time exports.
            'sessionType': 0,
          },
        ]);

        final result = await importService.importData(json);
        // Two rows (one per PK member) — fan-out happened. The previous
        // bug would have produced a single row with the legacy id.
        expect(result.frontSessionsCreated, 2);
        final alexId = derivePkSessionId(switchUuid, alexPkUuid);
        final ezraId = derivePkSessionId(switchUuid, ezraPkUuid);
        final rows = await db.frontingSessionsDao.getAllSessions();
        final byId = {for (final r in rows) r.id: r};
        expect(byId.keys, containsAll([alexId, ezraId]),
            reason: 'PK fan-out must derive deterministic ids per member');
        expect(byId[alexId]!.memberId, alexLocalId);
        expect(byId[ezraId]!.memberId, ezraLocalId);
      },
    );

    test(
      'PK rescue with empty pkMemberIdsJson but headmateId present derives '
      'deterministic id from local member.pluralkit_uuid (codex P1 #10), '
      'driven by real DataExportService.buildExport (codex pass 2 #C-NEW1)',
      () async {
        // Real-export-driven test (codex pass 2 #C-NEW1). The previous
        // version hand-built `coFronterIds: []` JSON — a key the real
        // exporter would never emit (`toJson` skips empty lists). With
        // the envelope-level rescueLegacyFields marker (codex pass 2
        // #B-NEW1), the row no longer needs any per-row legacy key to
        // route through the rescue path; this test pins that the
        // real exporter + importer round-trip produces the canonical
        // deterministic id for the pre-Phase-2 PK fallback scenario.
        //
        // Source DB:
        //   - one PK-linked member (local id "fallback-member", pluralkit
        //     short "fmsht", full uuid 555…555)
        //   - one fronting session: pluralkit_uuid = switchUuid,
        //     member_id = fallback-member, co_fronter_ids defaults to
        //     '[]', pk_member_ids_json defaults to NULL (Phase-2-style)
        //
        // Without the fix the row landed at the legacy `s.id` (a random
        // v4) — a future PK API re-import would derive a different
        // deterministic id and produce two distinct rows for the same
        // (switch, member) pair, defeating the field-LWW boundary
        // correction contract.
        const memberLocalId = 'fallback-member';
        const memberPkUuid = '55555555-5555-4555-8555-555555555555';
        const switchUuid = '66666666-6666-4666-8666-666666666666';
        const legacySessionId = 'legacy-v4-id-not-deterministic';

        // -- Source DB: seed real Drift rows --------------------------
        await memberRepo.createMember(Member(
          id: memberLocalId,
          name: 'Fallback',
          emoji: 'F',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'fmsht',
          pluralkitUuid: memberPkUuid,
        ));
        final sourceFronting = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        await sourceFronting.createSession(FrontingSession(
          id: legacySessionId,
          startTime: DateTime.utc(2026, 4, 1, 9),
          endTime: DateTime.utc(2026, 4, 1, 11),
          memberId: memberLocalId,
          pluralkitUuid: switchUuid,
          // sessionType defaults to normal; co_fronter_ids defaults to
          // '[]' and pk_member_ids_json defaults to NULL on the v7
          // table — exactly the bug-scenario shape.
        ));

        // -- Build a real export with includeLegacyFields = true ------
        final exportSvc = _makeExport(db);
        final exportModel =
            await exportSvc.buildExport(includeLegacyFields: true);
        // Pin the load-bearing properties: envelope marker is set, but
        // the per-row legacy keys are absent (the bug condition that
        // motivated the envelope marker). Together they prove the
        // round-trip exercises the previously-broken path.
        expect(exportModel.rescueLegacyFields, isTrue,
            reason: 'buildExport(includeLegacyFields: true) must set '
                'rescueLegacyFields on the envelope');
        final exportedSessionJson = exportModel.frontSessions.single.toJson();
        expect(exportedSessionJson.containsKey('coFronterIds'), isFalse,
            reason: 'real exporter omits empty coFronterIds — this is the '
                'shape that motivated the envelope marker');
        expect(exportedSessionJson.containsKey('pkMemberIdsJson'), isFalse,
            reason: 'real exporter omits null pkMemberIdsJson — same '
                'as above');

        final jsonStr = jsonEncode(exportModel.toJson());

        // -- Re-import on a fresh DB ----------------------------------
        final freshDb = _makeDb();
        try {
          final freshImport = _makeImport(freshDb);
          final freshMemberRepo =
              DriftMemberRepository(freshDb.membersDao, null);
          // Re-seed the local member on the fresh DB so the rescue
          // importer can resolve `headmateId` → `pluralkit_uuid` for
          // the deterministic id derivation.
          await freshMemberRepo.createMember(Member(
            id: memberLocalId,
            name: 'Fallback',
            emoji: 'F',
            createdAt: DateTime(2026, 1, 1).toUtc(),
            pluralkitId: 'fmsht',
            pluralkitUuid: memberPkUuid,
          ));

          final result = await freshImport.importData(jsonStr);
          expect(result.frontSessionsCreated, 1);
          final derivedId = derivePkSessionId(switchUuid, memberPkUuid);
          final rows = await freshDb.frontingSessionsDao.getAllSessions();
          expect(rows, hasLength(1));
          expect(rows.single.id, derivedId,
              reason: 'fallback id must be the canonical (switch, member) v5');
          expect(rows.single.id, isNot(legacySessionId),
              reason: 'legacy random v4 id must not leak through');

          // Simulated API re-import at the same deterministic id: writes
          // through the same row (no duplicate) — the boundary correction
          // contract holds.
          final domainSession = await freshImport.frontingSessionRepository
              .getSessionById(derivedId);
          await freshImport.frontingSessionRepository.updateSession(
            domainSession!.copyWith(
              startTime: DateTime.utc(2026, 4, 1, 9, 30),
              endTime: DateTime.utc(2026, 4, 1, 10, 30),
            ),
          );
          final after = await freshDb.frontingSessionsDao.getAllSessions();
          expect(after, hasLength(1),
              reason: 'API write must collide on the same id, not duplicate');
          expect(after.single.startTime.toUtc(),
              DateTime.utc(2026, 4, 1, 9, 30));
        } finally {
          await freshDb.close();
        }
      },
    );

    test(
      'orphan native row (member_id NULL) round-trips through '
      'buildExport(includeLegacyFields: true) and lands on the Unknown '
      'sentinel via the envelope-marker rescue path (codex pass 2 #B-NEW1)',
      () async {
        // Same envelope-marker contract as the previous test, but
        // exercising the orphan path: a native row with member_id NULL
        // that the real exporter would emit with NEITHER `coFronterIds`
        // NOR `headmateId` (both null/empty) — i.e., zero per-row legacy
        // keys. Pre-fix this row bypassed the rescue importer and tried
        // to import with member_id null, which v8's CHECK constraint
        // would reject.
        const orphanId = 'orphan-row';
        final sourceFronting = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        await sourceFronting.createSession(FrontingSession(
          id: orphanId,
          startTime: DateTime.utc(2026, 4, 1, 9),
          endTime: DateTime.utc(2026, 4, 1, 11),
          // memberId omitted → NULL; co_fronter_ids defaults to '[]'.
        ));

        final exportSvc = _makeExport(db);
        final exportModel =
            await exportSvc.buildExport(includeLegacyFields: true);
        expect(exportModel.rescueLegacyFields, isTrue);
        final orphanJson = exportModel.frontSessions
            .firstWhere((s) => s.id == orphanId)
            .toJson();
        expect(orphanJson.containsKey('headmateId'), isFalse,
            reason: 'null member_id is not serialized');
        expect(orphanJson.containsKey('coFronterIds'), isFalse,
            reason: 'empty co_fronter_ids is not serialized');
        // No per-row legacy markers → only the envelope flag steers
        // this row to the rescue path.

        final jsonStr = jsonEncode(exportModel.toJson());

        final freshDb = _makeDb();
        try {
          final freshImport = _makeImport(freshDb);
          final result = await freshImport.importData(jsonStr);
          expect(result.frontSessionsCreated, 1);
          expect(result.unknownSentinelCreated, isTrue,
              reason: 'orphan row must be rerouted to the Unknown sentinel '
                  'by the rescue importer');

          const uuid = Uuid();
          final sentinelId =
              uuid.v5(spFrontingNamespace, 'unknown-member-sentinel');
          final rows = await freshDb.frontingSessionsDao.getAllSessions();
          expect(rows.single.id, orphanId);
          expect(rows.single.memberId, sentinelId,
              reason: 'orphan must land on the Unknown sentinel, not be '
                  'imported with member_id null');
        } finally {
          await freshDb.close();
        }
      },
    );

    test(
      'PK rescue fallback with headmateId whose local member has no '
      'pluralkit_uuid is counted as skipped, not silently misimported',
      () async {
        // The fallback can only derive the canonical id when the local
        // member has a `pluralkit_uuid`. Without one, writing a
        // non-deterministic id would re-introduce the codex #10 bug —
        // skip the row instead, surface via legacyPkShortIdsSkipped.
        const memberLocalId = 'no-pk-uuid-member';
        await memberRepo.createMember(Member(
          id: memberLocalId,
          name: 'NoPK',
          emoji: 'X',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          // no pluralkitUuid
        ));

        final json = _envelope(frontSessions: [
          {
            'id': 'unmappable-pk-rescue',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': memberLocalId,
            'coFronterIds': [],
            'pluralkitUuid': '77777777-7777-4777-8777-777777777777',
          },
        ]);

        final result = await importService.importData(json);
        expect(result.frontSessionsCreated, 0);
        expect(result.legacyPkShortIdsSkipped, 1);
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, isEmpty);
      },
    );

    // -----------------------------------------------------------------
    // Adjacent-merge pass for legacy-shape rescue (spec §2.1).
    // Mirrors the migration's post-fan-out merge so the rescue file
    // produces the same shape as a fresh migration.
    // -----------------------------------------------------------------
    test(
      'continuous-host scenario: legacy A (Zari alone) + B (Zari + Aimee) '
      'rescue-fan-out, then adjacent-merge collapses Zari to one row',
      () async {
        const zari = 'zari';
        const aimee = 'aimee';
        for (final m in [zari, aimee]) {
          await memberRepo.createMember(Member(
            id: m,
            name: m,
            emoji: 'X',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ));
        }
        final json = _envelope(frontSessions: [
          {
            'id': 'sess-a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': <String>[],
          },
          {
            'id': 'sess-b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': [aimee],
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(2));
        final zariRows = rows.where((r) => r.memberId == zari).toList();
        expect(zariRows, hasLength(1));
        expect(zariRows.single.id, 'sess-a',
            reason: 'earlier row id survives the merge');
        expect(zariRows.single.startTime.toUtc(),
            DateTime.utc(2026, 4, 1, 6, 42));
        expect(zariRows.single.endTime?.toUtc(),
            DateTime.utc(2026, 4, 1, 9, 7));
        final aimeeRows =
            rows.where((r) => r.memberId == aimee).toList();
        expect(aimeeRows, hasLength(1));
      },
    );

    test(
      'three-row cascade: legacy A→B→C all touching for the same headmate '
      'collapse to one row through the rescue path',
      () async {
        const host = 'host';
        await memberRepo.createMember(Member(
          id: host,
          name: 'Host',
          emoji: 'H',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final json = _envelope(frontSessions: [
          {
            'id': 'a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
          {
            'id': 'b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
          {
            'id': 'c',
            'startTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'endTime':
                DateTime.utc(2026, 4, 1, 9, 30).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'a');
        expect(rows.single.startTime.toUtc(),
            DateTime.utc(2026, 4, 1, 6, 42));
        expect(rows.single.endTime?.toUtc(),
            DateTime.utc(2026, 4, 1, 9, 30));
      },
    );

    test(
      'gap preserves separation: 5-min gap between legacy rows → no merge',
      () async {
        const host = 'host';
        await memberRepo.createMember(Member(
          id: host,
          name: 'Host',
          emoji: 'H',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final json = _envelope(frontSessions: [
          {
            'id': 'a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
          {
            'id': 'b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 55).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(2));
      },
    );

    test(
      'notes concatenate when both legacy rows carry notes',
      () async {
        const host = 'host';
        await memberRepo.createMember(Member(
          id: host,
          name: 'Host',
          emoji: 'H',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final json = _envelope(frontSessions: [
          {
            'id': 'a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
            'notes': 'morning',
          },
          {
            'id': 'b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
            'notes': 'post-meeting',
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.notes, 'morning\n\npost-meeting');
      },
    );

    test(
      'open-ended merge: B has null endTime in the legacy file → merged '
      'row stays open-ended after rescue',
      () async {
        const host = 'host';
        await memberRepo.createMember(Member(
          id: host,
          name: 'Host',
          emoji: 'H',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final json = _envelope(frontSessions: [
          {
            'id': 'a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
          {
            'id': 'b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': null,
            'headmateId': host,
            'coFronterIds': <String>[],
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.endTime, isNull);
        expect(rows.single.startTime.toUtc(),
            DateTime.utc(2026, 4, 1, 6, 42));
      },
    );

    test(
      'sleep rows are not merged into adjacent normal rows during rescue',
      () async {
        const host = 'host';
        await memberRepo.createMember(Member(
          id: host,
          name: 'Host',
          emoji: 'H',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        // Sleep rows arrive in the legacy `sleepSessions` array, not
        // `frontSessions`. Build a normal legacy row touching the start
        // of the sleep row's window. They share `member_id` but the
        // sleep row's session_type=1 prevents the merge helper from
        // walking over it.
        final json = _envelope(frontSessions: [
          {
            'id': 'normal',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': host,
            'coFronterIds': <String>[],
          },
        ], sleepSessions: [
          {
            'id': 'sleep-row',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'quality': 0,
            'isHealthKitImport': false,
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        // Both rows survive — the sleep row carries session_type=1 and
        // the merge helper's `getSessionsForMember` filters those out.
        expect(rows, hasLength(2));
      },
    );

    test(
      'multi-member sanity: rescue native multi-member fans out then '
      'merges only same-member adjacency',
      () async {
        const zari = 'z';
        const aimee = 'a';
        for (final m in [zari, aimee]) {
          await memberRepo.createMember(Member(
            id: m,
            name: m,
            emoji: 'X',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ));
        }
        final json = _envelope(frontSessions: [
          {
            'id': 'sess-a',
            'startTime':
                DateTime.utc(2026, 4, 1, 6, 42).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': <String>[],
          },
          {
            'id': 'sess-b',
            'startTime':
                DateTime.utc(2026, 4, 1, 8, 50).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 9, 7).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': [aimee],
          },
          // Aimee's later row, separate by hours — must not be touched.
          {
            'id': 'aimee-later',
            'startTime': DateTime.utc(2026, 4, 1, 14).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 15).toIso8601String(),
            'headmateId': aimee,
            'coFronterIds': <String>[],
          },
        ]);

        await importService.importData(json);

        final rows = await db.frontingSessionsDao.getAllSessions();
        // 1 Zari merged + 1 Aimee fan-out + 1 Aimee later = 3 rows.
        expect(rows, hasLength(3));
        expect(rows.where((r) => r.memberId == zari), hasLength(1));
        expect(rows.where((r) => r.memberId == aimee), hasLength(2));
      },
    );
  });

  // -- PR G additions (review findings #9, #10, #41, #42, #44) -----------

  group('rescue importer sync semantics + structured dedup (PR G)', () {
    late AppDatabase db;
    late DataImportService importService;
    late DriftMemberRepository memberRepo;

    setUp(() {
      db = _makeDb();
      importService = _makeImport(db);
      memberRepo = DriftMemberRepository(db.membersDao, null);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'rescue body runs under SyncRecordMixin.suppress; '
      'final-state ops emit per surviving id (review finding #9)',
      () async {
        // The rescue path (legacy fan-out + adjacent-merge) must not
        // emit intermediate sync ops. With no sync handle wired, the
        // post-suppress emit pass still walks the touched ids and
        // attempts the FFI call (which logs and returns since the
        // handle is null) — but the WRITE COUNT to the underlying
        // table reflects the final merged shape, not the transient
        // pre-merge state. We assert the final shape here; the
        // suppression invariant itself is tested by the static
        // SyncRecordMixin.isSuppressed mid-flight asserts below.
        const zari = 'z-suppress';
        for (final m in [zari]) {
          await memberRepo.createMember(Member(
            id: m,
            name: m,
            emoji: 'X',
            createdAt: DateTime(2026, 1, 1).toUtc(),
          ));
        }
        // Two adjacent legacy rows for the same member that the merge
        // collapses to one. If the merge had escaped suppression it
        // would emit syncRecordUpdate + syncRecordDelete; instead the
        // post-commit pass emits a single final-state create for the
        // surviving merged row.
        final json = _envelope(frontSessions: [
          {
            'id': 'leg-a',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 10).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': <String>[],
          },
          {
            'id': 'leg-b',
            'startTime': DateTime.utc(2026, 4, 1, 10).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': zari,
            'coFronterIds': <String>[],
          },
        ]);

        // Suppression has been off before the call.
        expect(SyncRecordMixin.isSuppressed, false);

        await importService.importData(json);

        // Suppression is reset to off after the call (either the
        // suppress(...) wrapper's finally restored it, or no rescue
        // path ran).
        expect(SyncRecordMixin.isSuppressed, false);

        // Final-state row: one merged session covering both legacy
        // intervals. The merged row keeps `leg-a`'s id (earlier row
        // is the merge survivor by helper convention); `leg-b` is
        // soft-deleted by the merge.
        final rows = await db.frontingSessionsDao.getAllSessions();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'leg-a');
        expect(rows.single.endTime?.toUtc(), DateTime.utc(2026, 4, 1, 11));
      },
    );

    test(
      'soft-deleted member PK uuid still resolves through includeDeleted '
      'DAO during rescue (review finding #10)',
      () async {
        const memberId = 'soft-deleted-pk-member';
        const memberPkUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        const switchUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
        // Create a member, then soft-delete via the repository so the
        // tombstone is in place (not just is_active=false).
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'SoftDeleted',
          emoji: 'D',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'sdshrt',
          pluralkitUuid: memberPkUuid,
        ));
        await memberRepo.deleteMember(memberId);
        // Sanity: the active-only view filters this row out.
        final activeOnly = await memberRepo.getAllMembers();
        expect(
          activeOnly.where((m) => m.id == memberId).toList(),
          isEmpty,
        );

        // Legacy PK row with empty pkMemberIdsJson — falls back to
        // headmateId-with-pk-uuid resolver (`_pkUuidForLocalMemberId`).
        // Pre-fix, that resolver filtered tombstones and returned null,
        // counting the row as skipped. Post-fix it returns the
        // tombstoned member's pluralkit_uuid and the row is written
        // with the deterministic id derived from it.
        final json = _envelope(frontSessions: [
          {
            'id': 'legacy-pk-orphan-on-tombstone',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'headmateId': memberId,
            'coFronterIds': <String>[],
            'pluralkitUuid': switchUuid,
            // pkMemberIdsJson omitted entirely — exercises the
            // headmateId fallback that uses _pkUuidForLocalMemberId.
          },
        ]);

        final result = await importService.importData(json);
        // No "skipped" since the tombstone-included resolver fired.
        expect(result.legacyPkShortIdsSkipped, 0);
        expect(result.frontSessionsCreated, 1);
        // The row landed at the deterministic (switch, member) id.
        final derivedId = derivePkSessionId(switchUuid, memberPkUuid);
        final rows = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final byId = {for (final r in rows) r.id: r};
        expect(byId.keys, contains(derivedId));
        // The new session row references the tombstoned member id —
        // intentional, per finding #10's "rescue file's intent is
        // re-create everything that existed."
        expect(byId[derivedId]!.memberId, memberId);
      },
    );

    test(
      'Unknown sentinel orphan rows stay distinct after rescue '
      '(review finding #42 — sentinel excluded from adjacent-merge)',
      () async {
        // Two adjacent orphan-rescue rows assigned to the Unknown
        // sentinel. With the sentinel excluded from the merge they
        // remain as two separate rows preserving per-row notes /
        // confidence. Pre-fix they collapsed into one giant sentinel
        // session with concatenated notes.
        final json = _envelope(frontSessions: [
          {
            'id': 'orphan-a',
            'startTime': DateTime.utc(2026, 4, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 10).toIso8601String(),
            'coFronterIds': <String>[],
            'notes': 'Note A',
          },
          {
            'id': 'orphan-b',
            'startTime': DateTime.utc(2026, 4, 1, 10).toIso8601String(),
            'endTime': DateTime.utc(2026, 4, 1, 11).toIso8601String(),
            'coFronterIds': <String>[],
            'notes': 'Note B',
          },
        ]);

        final result = await importService.importData(json);
        expect(result.unknownSentinelCreated, true);
        final rows = await db.frontingSessionsDao.getAllSessions();
        // Both orphan rows survive; their per-row identity (notes)
        // is preserved.
        expect(rows, hasLength(2));
        expect(
          rows.map((r) => r.notes).toSet(),
          {'Note A', 'Note B'},
        );
        // Both reference the sentinel.
        for (final r in rows) {
          expect(r.memberId, unknownSentinelMemberId);
        }
      },
    );

    test(
      'PkSessionMemberKey: null memberId differs from empty string and '
      'from delimiter-containing ids (review finding #44)',
      () {
        const uuid = 'switch-uuid-1';
        const keyNull = PkSessionMemberKey(
          pluralkitUuid: uuid,
          localMemberId: null,
        );
        const keyEmpty = PkSessionMemberKey(
          pluralkitUuid: uuid,
          localMemberId: '',
        );
        const keyA = PkSessionMemberKey(
          pluralkitUuid: uuid,
          localMemberId: '|foo',
        );
        const keyB = PkSessionMemberKey(
          pluralkitUuid: '$uuid|',
          localMemberId: 'foo',
        );
        // Null vs empty string: distinct under the structured key,
        // collided under the old `'$uuid|$memberId'` scheme (both
        // produced "$uuid|").
        expect(keyNull == keyEmpty, false);
        expect(keyNull.hashCode == keyEmpty.hashCode, false);
        // Delimiter-containing memberId: distinct from a different
        // (uuid, memberId) pair that happened to compose into the
        // same string under the old delimiter scheme. Pre-fix both
        // produced "switch-uuid-1|foo" via the boundary slip.
        expect(keyA == keyB, false);
        expect(keyA.hashCode == keyB.hashCode, false);
        // Same fields → same key (sanity).
        const keyA2 = PkSessionMemberKey(
          pluralkitUuid: uuid,
          localMemberId: '|foo',
        );
        expect(keyA == keyA2, true);
        expect(keyA.hashCode == keyA2.hashCode, true);
      },
    );

    test(
      'legacy comments outside parent bounds clamp to nearest bound '
      'and increment legacyClampedCommentsCount (review finding #41)',
      () async {
        const memberId = 'member-clamp';
        const sessionId = 'parent-session-clamp';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'M',
          emoji: 'M',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        final start = DateTime.utc(2026, 4, 1, 10);
        final end = DateTime.utc(2026, 4, 1, 12);
        // Comment 1: BEFORE start → clamps to start.
        // Comment 2: INSIDE bounds → keeps own timestamp.
        // Comment 3: AFTER end → clamps to end.
        final beforeTs = DateTime.utc(2026, 4, 1, 9, 30);
        final insideTs = DateTime.utc(2026, 4, 1, 11);
        final afterTs = DateTime.utc(2026, 4, 1, 13);
        final json = _envelope(
          frontSessions: [
            {
              'id': sessionId,
              'startTime': start.toIso8601String(),
              'endTime': end.toIso8601String(),
              'headmateId': memberId,
              'coFronterIds': <String>[],
            },
          ],
          frontSessionComments: [
            {
              'id': 'c-before',
              'sessionId': sessionId,
              'body': 'before',
              'timestamp': beforeTs.toIso8601String(),
              'createdAt': beforeTs.toIso8601String(),
            },
            {
              'id': 'c-inside',
              'sessionId': sessionId,
              'body': 'inside',
              'timestamp': insideTs.toIso8601String(),
              'createdAt': insideTs.toIso8601String(),
            },
            {
              'id': 'c-after',
              'sessionId': sessionId,
              'body': 'after',
              'timestamp': afterTs.toIso8601String(),
              'createdAt': afterTs.toIso8601String(),
            },
          ],
        );

        final result = await importService.importData(json);
        expect(result.frontSessionCommentsCreated, 3);
        // 2 of the 3 comments were clamped (before + after).
        expect(result.legacyClampedCommentsCount, 2);

        final commentRows = await db.frontSessionCommentsDao.getAllComments();
        final byId = {for (final r in commentRows) r.id: r};
        expect(byId['c-before']!.targetTime?.toUtc(), start);
        expect(byId['c-inside']!.targetTime?.toUtc(), insideTs);
        expect(byId['c-after']!.targetTime?.toUtc(), end);
      },
    );

    test(
      'legacy comment with null parent.endTime: only clamps before-start; '
      'after-start with null end stays at own timestamp',
      () async {
        const memberId = 'member-open';
        const sessionId = 'parent-session-open';
        await memberRepo.createMember(Member(
          id: memberId,
          name: 'M',
          emoji: 'M',
          createdAt: DateTime(2026, 1, 1).toUtc(),
        ));
        // Open-ended parent (endTime null).
        final start = DateTime.utc(2026, 4, 1, 10);
        final beforeTs = DateTime.utc(2026, 4, 1, 9);
        final afterStartTs = DateTime.utc(2026, 4, 1, 23);
        final json = _envelope(
          frontSessions: [
            {
              'id': sessionId,
              'startTime': start.toIso8601String(),
              'headmateId': memberId,
              'coFronterIds': <String>[],
            },
          ],
          frontSessionComments: [
            {
              'id': 'c-pre-open',
              'sessionId': sessionId,
              'body': 'pre',
              'timestamp': beforeTs.toIso8601String(),
              'createdAt': beforeTs.toIso8601String(),
            },
            {
              'id': 'c-post-open',
              'sessionId': sessionId,
              'body': 'post',
              'timestamp': afterStartTs.toIso8601String(),
              'createdAt': afterStartTs.toIso8601String(),
            },
          ],
        );

        final result = await importService.importData(json);
        expect(result.legacyClampedCommentsCount, 1);
        final rows = await db.frontSessionCommentsDao.getAllComments();
        final byId = {for (final r in rows) r.id: r};
        expect(byId['c-pre-open']!.targetTime?.toUtc(), start);
        // Open-ended parent: post-start comment keeps its timestamp.
        expect(byId['c-post-open']!.targetTime?.toUtc(), afterStartTs);
      },
    );
  });

  // -- Codex pass 2 #B-NEW2: rescue → API corrective end-to-end ----------
  //
  // The "rescue then API re-import fixes bounds" recovery story has to
  // hold for histories where a member is continuously fronting across
  // multiple PK switches. The rescue importer fans out one row per
  // (switch, member) pair, but the API diff sweep only writes ENTRANT
  // rows (one per "this member just became active"). For A → A+B → A:
  //   - rescue creates 4 PK-linked rows: det(sw1,A), det(sw2,A),
  //     det(sw2,B), det(sw3,A) — three of which carry stale lossy
  //     boundaries because they're not the entrant point for that
  //     member's actual presence interval.
  //   - the diff sweep only re-writes the 2 entrant rows: det(sw1,A)
  //     and det(sw2,B). The other two rescue rows linger.
  //
  // performFullImport() must canonicalize: tombstone stale rescue
  // rows the API wouldn't create, and clobber end_time on canonical
  // collisions so currently-active sessions show as open. Pre-fix,
  // this scenario left A with 3 stale closed rows and no open A row.

  group('rescue → API corrective re-import end-to-end (codex pass 2 #B-NEW2)',
      () {
    final storageStub = _SecureStorageStub();

    setUp(storageStub.setup);
    tearDown(storageStub.teardown);

    test(
      'A → A+B → A: rescue fans out to stale rows, API corrective '
      'tombstones stale ones and leaves A currently fronting',
      () async {
        const alexLocalId = 'alex-local';
        const ezraLocalId = 'ezra-local';
        const alexPkUuid = '11111111-1111-4111-8111-111111111111';
        const ezraPkUuid = '22222222-2222-4222-8222-222222222222';
        const sw1Id = 'aaaaaaaa-1111-4111-8111-111111111111';
        const sw2Id = 'bbbbbbbb-2222-4222-8222-222222222222';
        const sw3Id = 'cccccccc-3333-4333-8333-333333333333';

        final db = _makeDb();
        addTearDown(db.close);
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final importService = _makeImport(db);

        await memberRepo.createMember(Member(
          id: alexLocalId,
          name: 'Alex',
          emoji: 'A',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'alxsh',
          pluralkitUuid: alexPkUuid,
        ));
        await memberRepo.createMember(Member(
          id: ezraLocalId,
          name: 'Ezra',
          emoji: 'E',
          createdAt: DateTime(2026, 1, 1).toUtc(),
          pluralkitId: 'ezrsh',
          pluralkitUuid: ezraPkUuid,
        ));

        // Step 1: PRISM1 rescue file with the legacy collapsed shape
        // for each PK switch — one row per switch (members in
        // pk_member_ids_json). The rescue importer fans these out:
        // sw1 → [A], sw2 → [A, E], sw3 → [A]. So 4 rows after rescue.
        // All carry the lossy old-shape boundaries.
        final t1 = DateTime.utc(2026, 4, 1, 9);
        final t2 = DateTime.utc(2026, 4, 1, 10);
        final t3 = DateTime.utc(2026, 4, 1, 11);
        final rescueJson = _envelope(frontSessions: [
          {
            'id': 'legacy-sw1',
            'startTime': t1.toIso8601String(),
            'endTime': t2.toIso8601String(),
            'headmateId': alexLocalId,
            'coFronterIds': <String>[],
            'pluralkitUuid': sw1Id,
            'pkMemberIdsJson': jsonEncode(['alxsh']),
          },
          {
            'id': 'legacy-sw2',
            'startTime': t2.toIso8601String(),
            'endTime': t3.toIso8601String(),
            'headmateId': alexLocalId,
            'coFronterIds': [ezraLocalId],
            'pluralkitUuid': sw2Id,
            'pkMemberIdsJson': jsonEncode(['alxsh', 'ezrsh']),
          },
          {
            'id': 'legacy-sw3',
            'startTime': t3.toIso8601String(),
            'endTime': t3.add(const Duration(hours: 1)).toIso8601String(),
            'headmateId': alexLocalId,
            'coFronterIds': <String>[],
            'pluralkitUuid': sw3Id,
            'pkMemberIdsJson': jsonEncode(['alxsh']),
          },
        ]);

        await importService.importData(rescueJson);

        // Verify the rescue produced the expected fan-out — 4 rows
        // at the deterministic ids, all with lossy boundaries.
        final afterRescue = await sessionRepo.getAllSessions();
        final rescueIds = {
          derivePkSessionId(sw1Id, alexPkUuid),
          derivePkSessionId(sw2Id, alexPkUuid),
          derivePkSessionId(sw2Id, ezraPkUuid),
          derivePkSessionId(sw3Id, alexPkUuid),
        };
        expect(afterRescue.map((s) => s.id).toSet(), rescueIds,
            reason: 'rescue importer must fan out 4 rows for A→A+B→A');
        expect(afterRescue.every((s) => s.endTime != null), isTrue,
            reason: 'rescue rows are all closed in lossy shape');

        // Step 2: corrective API re-import. The API reports the
        // canonical history: A enters at sw-1 and is continuously
        // fronting; B enters at sw-2 and leaves at sw-3.
        final pkSw1 = PKSwitch(
          id: sw1Id,
          timestamp: t1,
          members: const ['alxsh'],
        );
        final pkSw2 = PKSwitch(
          id: sw2Id,
          timestamp: t2,
          members: const ['alxsh', 'ezrsh'],
        );
        final pkSw3 = PKSwitch(
          id: sw3Id,
          timestamp: t3,
          members: const ['alxsh'],
        );
        // PK API returns newest-first; service sorts oldest-first.
        final fakeClient = _FakePkClient([
          [pkSw3, pkSw2, pkSw1],
          [],
        ]);
        final pkService = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: sessionRepo,
          syncDao: db.pluralKitSyncDao,
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => fakeClient,
        );
        await pkService.setToken('t');
        await pkService.acknowledgeMapping();
        await pkService.performFullImport();

        // Step 3: assert canonical state after corrective re-import.
        //
        // Canonical entrant set (what the API would have created
        // from scratch):
        //   - det(sw1, A)  (A enters at sw-1, never closed → still open)
        //   - det(sw2, B)  (B enters at sw-2, leaver at sw-3)
        // Stale rescue rows that must be tombstoned:
        //   - det(sw2, A)  (A continuous, never an entrant at sw-2)
        //   - det(sw3, A)  (A continuous, never an entrant at sw-3)
        final after = await sessionRepo.getAllSessions();
        final canonicalAlex = derivePkSessionId(sw1Id, alexPkUuid);
        final canonicalEzra = derivePkSessionId(sw2Id, ezraPkUuid);
        final staleAlexAtSw2 = derivePkSessionId(sw2Id, alexPkUuid);
        final staleAlexAtSw3 = derivePkSessionId(sw3Id, alexPkUuid);

        expect(after.map((s) => s.id).toSet(), {canonicalAlex, canonicalEzra},
            reason: 'only canonical entrant rows survive the corrective '
                're-import; stale rescue fan-outs are tombstoned');
        expect(after.any((s) => s.id == staleAlexAtSw2), isFalse,
            reason: 'continuous-A stale row at sw-2 must be tombstoned');
        expect(after.any((s) => s.id == staleAlexAtSw3), isFalse,
            reason: 'continuous-A stale row at sw-3 must be tombstoned');

        // The canonical A row reflects API truth: starts at sw-1
        // and is currently active (corrective entrant collision
        // clobbered the rescue's lossy end_time).
        final alexRow = after.firstWhere((s) => s.id == canonicalAlex);
        expect(alexRow.memberId, alexLocalId);
        expect(alexRow.pluralkitUuid, sw1Id);
        expect(alexRow.startTime.toUtc(), t1);
        expect(alexRow.endTime, isNull,
            reason: 'A is currently fronting per API; corrective re-import '
                'must clear the lossy rescue end_time');

        // The canonical B row: enters at sw-2, closed by leaver at sw-3.
        final ezraRow = after.firstWhere((s) => s.id == canonicalEzra);
        expect(ezraRow.memberId, ezraLocalId);
        expect(ezraRow.pluralkitUuid, sw2Id);
        expect(ezraRow.startTime.toUtc(), t2);
        expect(ezraRow.endTime?.toUtc(), t3);
      },
    );
  });
}

/// Mocks the secure storage channel so PluralKitSyncService can persist
/// its config (token, etc.) without a real platform channel.
class _SecureStorageStub {
  final Map<String, String?> _store = {};

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                _store[call.arguments['key'] as String] =
                    call.arguments['value'] as String?;
                return null;
              case 'read':
                return _store[call.arguments['key'] as String];
              case 'delete':
                _store.remove(call.arguments['key'] as String);
                return null;
              case 'containsKey':
                return _store.containsKey(call.arguments['key'] as String);
              default:
                return null;
            }
          },
        );
  }

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    _store.clear();
  }
}

/// Minimal fake PluralKit client returning preconfigured switch pages.
class _FakePkClient implements PluralKitClient {
  final List<List<PKSwitch>> switchPages;

  _FakePkClient(this.switchPages);

  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
    if (switchPages.isEmpty) return const [];
    return switchPages.removeAt(0);
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds, {DateTime? timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(String switchId, {required DateTime timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(String switchId, List<String> memberIds) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  void dispose() {}
}
