/// Tests for PluralKitSyncService.importFromFile.
///
/// Covers:
/// - Groups and members are imported from file (no token required).
/// - The fronting/switches portion of file imports is DROPPED (§2.1): switches
///   are counted and reported but no fronting sessions are created.
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ignore_for_file: avoid_print

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftMemberRepository memberRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    memberRepo = DriftMemberRepository(db.membersDao, null);
  });
  tearDown(() => db.close());

  PluralKitSyncService makeService() => PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    syncDao: db.pluralKitSyncDao,
    groupsImporter: PkGroupsImporter(db: db, memberRepository: memberRepo),
    bannerCacheService: PkBannerCacheService(
      fetcher: (_) async => Uint8List.fromList([1, 2, 3]),
      normalizer: (bytes) async => bytes,
    ),
  );

  test('imports groups from file without a PK token linked', () async {
    const export = PkFileExport(
      system: PKSystem(id: 'sys1', name: 'Test System'),
      members: [PKMember(id: 'aaaaa', uuid: 'u-alice', name: 'Alice')],
      groups: [
        PKGroup(
          id: 'ggggg',
          uuid: 'g-uuid-1',
          name: 'Fronters',
          memberIds: ['u-alice'],
        ),
      ],
      switches: [],
    );

    final result = await makeService().importFromFile(export);

    expect(result.groupsImported, 1);
    final groups = await db.memberGroupsDao.getAllActiveGroups();
    expect(groups, hasLength(1));
    expect(groups.single.name, 'Fronters');
    expect(groups.single.pluralkitUuid, 'g-uuid-1');
  });

  test('group membership is wired to imported members', () async {
    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'aaaaa', uuid: 'u-alice', name: 'Alice')],
      groups: [
        PKGroup(
          id: 'ggggg',
          uuid: 'g-uuid-1',
          name: 'Fronters',
          memberIds: ['u-alice'],
        ),
      ],
      switches: [],
    );

    await makeService().importFromFile(export);

    final groups = await db.memberGroupsDao.getAllActiveGroups();
    final entries = await db.memberGroupsDao.entriesForGroup(groups.single.id);
    expect(entries, hasLength(1));
    expect(entries.single.pkMemberUuid, 'u-alice');
  });

  test('imports member banner URL from file', () async {
    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [
        PKMember(
          id: 'aaaaa',
          uuid: 'u-alice',
          name: 'Alice',
          bannerUrl: 'https://cdn.example.com/banner.png',
          hasBannerField: true,
        ),
      ],
      groups: [],
      switches: [],
    );

    await makeService().importFromFile(export);

    final rows = await db.membersDao.getAllMembers();
    expect(rows.single.pkBannerUrl, 'https://cdn.example.com/banner.png');
  });

  // ---------------------------------------------------------------------------
  // §2.1: File-import-of-fronting-history is dropped
  // ---------------------------------------------------------------------------

  test('switches in file are skipped — no fronting sessions created', () async {
    // File exports may contain switch history, but §2.1 drops file-import
    // of fronting-history. The API diff-sweep path is required instead.
    final export = PkFileExport(
      system: const PKSystem(id: 'sys1'),
      members: const [PKMember(id: 'aaaaa', uuid: 'u-alice', name: 'Alice')],
      groups: [],
      switches: [
        PkFileSwitch(
          timestamp: DateTime.utc(2026, 1, 1, 10),
          memberIds: ['aaaaa'],
        ),
        PkFileSwitch(timestamp: DateTime.utc(2026, 1, 1, 12), memberIds: []),
      ],
    );

    final service = makeService();
    final result = await service.importFromFile(export);

    // Switches are counted but NOT created.
    expect(result.switchesCreated, 0);
    expect(result.switchesSkipped, 2);

    // No fronting sessions were written to the DB.
    final sessions = await DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ).getAllSessions();
    expect(sessions, isEmpty);
  });

  test('members and groups still import when switches are present', () async {
    // Verifies that dropping switches doesn't abort member/group import.
    final export = PkFileExport(
      system: const PKSystem(id: 'sys1', name: 'My System'),
      members: const [PKMember(id: 'bbbbb', uuid: 'u-bob', name: 'Bob')],
      groups: [
        const PKGroup(
          id: 'ggggg',
          uuid: 'g-uuid-2',
          name: 'Team',
          memberIds: ['u-bob'],
        ),
      ],
      switches: [
        PkFileSwitch(
          timestamp: DateTime.utc(2026, 2, 1),
          memberIds: const ['bbbbb'],
        ),
      ],
    );

    final result = await makeService().importFromFile(export);

    expect(result.membersImported, 1);
    expect(result.groupsImported, 1);
    expect(result.switchesCreated, 0);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(1));
    expect(members.single.name, 'Bob');
  });
}
