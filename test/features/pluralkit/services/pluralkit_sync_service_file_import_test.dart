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
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

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
    bus: PkSyncEventBus(),
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
    expect(rows.single.pkBannerImageData, Uint8List.fromList([1, 2, 3]));
    expect(rows.single.pkBannerCachedUrl, 'https://cdn.example.com/banner.png');
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

  // ---------------------------------------------------------------------------
  // I1: file import dedups against unlinked same-name locals (the
  // Simply-Plural-then-PK-file megasystem duplication path).
  // ---------------------------------------------------------------------------

  Future<void> seedLocal(
    String id,
    String name, {
    String? pluralkitUuid,
    bool ignored = false,
  }) =>
      memberRepo.createMember(
        domain.Member(
          id: id,
          name: name,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: pluralkitUuid,
          pluralkitSyncIgnored: ignored,
        ),
      );

  test('I1: links an unlinked same-name local instead of duplicating it',
      () async {
    await seedLocal('local-alice', 'Alice'); // e.g. from an SP import, no PK link

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'aaaaa', uuid: 'u-alice', name: 'Alice')],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(1), reason: 'I1: no duplicate Alice created');
    expect(members.single.id, 'local-alice',
        reason: 'adopted the existing local row, not a fresh uuid');
    expect(members.single.pluralkitUuid, 'u-alice',
        reason: 'the local is now linked to the PK identity');
  });

  test('I1: matches case-insensitively when the exact case differs', () async {
    await seedLocal('local-sam', 'sam');

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'sssss', uuid: 'u-sam', name: 'Sam')],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(1));
    expect(members.single.id, 'local-sam');
    expect(members.single.pluralkitUuid, 'u-sam');
  });

  test('I1: an AMBIGUOUS same-name match is not auto-adopted — creates fresh',
      () async {
    await seedLocal('alex-1', 'Alex');
    await seedLocal('alex-2', 'Alex');

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'aaaaa', uuid: 'u-alex', name: 'Alex')],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(3),
        reason: 'ambiguous → no guess; the PK member is a NEW row');
    final linked = members.where((m) => m.pluralkitUuid == 'u-alex').toList();
    expect(linked, hasLength(1));
    expect(const ['alex-1', 'alex-2'], isNot(contains(linked.single.id)),
        reason: 'neither existing Alex was arbitrarily linked');
  });

  test('I1: does not adopt a same-name local already linked to another PK id',
      () async {
    await seedLocal('linked-bob', 'Bob', pluralkitUuid: 'u-other');

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'bbbbb', uuid: 'u-bob', name: 'Bob')],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(2),
        reason: 'the PK-linked local is off-limits; PK Bob is a new row');
    expect(members.firstWhere((m) => m.id == 'linked-bob').pluralkitUuid,
        'u-other');
    expect(members.where((m) => m.pluralkitUuid == 'u-bob'), hasLength(1));
  });

  test('I1: does not adopt a same-name local the user marked keep-local',
      () async {
    await seedLocal('ignored-cleo', 'Cleo', ignored: true);

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [PKMember(id: 'ccccc', uuid: 'u-cleo', name: 'Cleo')],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final members = await db.membersDao.getAllMembers();
    expect(members, hasLength(2),
        reason: 'a keep-local (ignored) member must not be silently re-linked');
    expect(members.firstWhere((m) => m.id == 'ignored-cleo').pluralkitUuid,
        isNull);
  });

  test(
      'F5: two same-name STALE-lease locals each adopt their own orphan '
      '(no last-write-wins duplicate)', () async {
    // Two interrupted create attempts for same-named members: both carry a
    // stale create lease (2026-01-01 is far older than the 10-min takeover).
    // A file import bringing both PK orphans must link BOTH locals — the old
    // last-write-wins Map stranded one as a duplicate.
    final staleLease = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    for (final id in ['local-alex-1', 'local-alex-2']) {
      await memberRepo.createMember(
        domain.Member(
          id: id,
          name: 'Alex',
          createdAt: DateTime.utc(2026, 1, 1),
          createPushStartedAt: staleLease,
        ),
      );
    }

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [
        PKMember(id: 'a1111', uuid: 'pk-alex-1', name: 'Alex'),
        PKMember(id: 'a2222', uuid: 'pk-alex-2', name: 'Alex'),
      ],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final alexes = (await db.membersDao.getAllMembers())
        .where((m) => m.name == 'Alex')
        .toList();
    expect(alexes, hasLength(2),
        reason: 'F5: both locals adopted — no stranded duplicate minted');
    expect(alexes.map((m) => m.id).toSet(), {'local-alex-1', 'local-alex-2'},
        reason: 'the two pre-existing locals were adopted, not new rows');
    expect(alexes.map((m) => m.pluralkitUuid).toSet(),
        {'pk-alex-1', 'pk-alex-2'});
  });

  test(
      'F5: an all-fresh same-name pool still lets a DISTINCT second PK member '
      'be created (fresh candidate consumed on skip)', () async {
    // One local "Alex" with a FRESH lease (a peer is mid-POST). Two DISTINCT PK
    // "Alex" arrive: the first matches+skips (the peer's in-flight create), the
    // second — a genuinely different member — must still be created, not
    // skipped against the same already-claimed local.
    final freshLease = DateTime.now().millisecondsSinceEpoch;
    await memberRepo.createMember(
      domain.Member(
        id: 'local-alex',
        name: 'Alex',
        createdAt: DateTime.utc(2026, 1, 1),
        createPushStartedAt: freshLease,
      ),
    );

    const export = PkFileExport(
      system: PKSystem(id: 'sys1'),
      members: [
        PKMember(id: 'a1111', uuid: 'pk-alex-1', name: 'Alex'),
        PKMember(id: 'a2222', uuid: 'pk-alex-2', name: 'Alex'),
      ],
      groups: [],
      switches: [],
    );
    await makeService().importFromFile(export);

    final alexes = (await db.membersDao.getAllMembers())
        .where((m) => m.name == 'Alex')
        .toList();
    expect(alexes, hasLength(2),
        reason: 'the fresh local is skipped (claimed by the peer) but the '
            'distinct second PK Alex is still created');
    expect(alexes.where((m) => m.pluralkitUuid == 'pk-alex-2'), hasLength(1));
  });
}
