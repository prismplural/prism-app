/// Tests for PluralKitSyncService.importFromFile.
///
/// Regression guard for the groups-drop bug: importFromFile previously
/// required a live PK token to import groups (it called _buildClient() and
/// gated the import on client != null). Groups are now imported directly from
/// the file data without any API call.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

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

  PluralKitSyncService _makeService() => PluralKitSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository:
            DriftFrontingSessionRepository(db.frontingSessionsDao, null),
        syncDao: db.pluralKitSyncDao,
        groupsImporter: PkGroupsImporter(db: db, memberRepository: memberRepo),
      );

  test('imports groups from file without a PK token linked', () async {
    final export = PkFileExport(
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

    final result = await _makeService().importFromFile(export);

    expect(result.groupsImported, 1);
    final groups = await db.memberGroupsDao.getAllActiveGroups();
    expect(groups, hasLength(1));
    expect(groups.single.name, 'Fronters');
    expect(groups.single.pluralkitUuid, 'g-uuid-1');
  });

  test('group membership is wired to imported members', () async {
    final export = PkFileExport(
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

    await _makeService().importFromFile(export);

    final groups = await db.memberGroupsDao.getAllActiveGroups();
    final entries = await db.memberGroupsDao.entriesForGroup(groups.single.id);
    expect(entries, hasLength(1));
    expect(entries.single.pkMemberUuid, 'u-alice');
  });

  test('imports member banner URL from file', () async {
    final export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [
        PKMember(
          id: 'aaaaa',
          uuid: 'u-alice',
          name: 'Alice',
          bannerUrl: 'https://cdn.example.com/banner.png',
        ),
      ],
      groups: [],
      switches: [],
    );

    await _makeService().importFromFile(export);

    final rows = await db.membersDao.getAllMembers();
    expect(rows.single.pkBannerUrl, 'https://cdn.example.com/banner.png');
  });
}
