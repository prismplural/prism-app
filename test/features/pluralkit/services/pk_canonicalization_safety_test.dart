/// C1 / H4: corrective full-import canonicalization safety. Earlier tests
/// built the repository WITHOUT `pkSyncDao`, so delete-intent stamping never
/// fired; these wire it in and assert adoption-in-place, H4 leave-alone for
/// unmapped members, and link-cleared/no-intent tombstoning of artifacts.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock (mirrors pluralkit_sync_service_diff_sweep_test.dart)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Fake client returning a fixed switch history, honoring nothing fancy
// (single page; the canonicalization tests use tiny fixtures).
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  _FakeClient(this.allSwitches);

  /// Newest-first switch history. Returned on the first `getSwitches` call;
  /// subsequent / `before`-bearing calls return empty so paging terminates.
  final List<PKSwitch> allSwitches;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
    if (before != null) return const [];
    return allSwitches;
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(String groupRef, List<String> memberRefs) =>
      throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) => throw UnimplementedError();

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

domain.Member _member({
  required String localId,
  required String pkShortId,
  required String pkUuid,
}) => domain.Member(
  id: localId,
  name: 'Member $localId',
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: pkShortId,
  pluralkitUuid: pkUuid,
);

/// Build the service with the fronting-session repository wired WITH
/// `pkSyncDao` — this is the production wiring (database_providers.dart) and
/// the missing piece in every prior diff-sweep test.
PluralKitSyncService _makeServiceWithPkDao({
  required AppDatabase db,
  required _FakeClient client,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
}) => PluralKitSyncService(
  memberRepository: memberRepo,
  frontingSessionRepository: sessionRepo,
  syncDao: db.pluralKitSyncDao,
  bus: PkSyncEventBus(),
  secureStorage: const FlutterSecureStorage(),
  clientFactory: (_) => client,
);

Future<void> _link(PluralKitSyncService service) async {
  await service.setToken('t');
  await service.confirmDirection();
  await service.acknowledgeMapping();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('canonicalization safety (pkSyncDao wired)', () {
    test(
      '(a) adopts a locally-pushed row (random v4 id, real switch uuid) in '
      'place — no tombstone, no delete intent stamped anywhere',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        // Repository wired WITH pkSyncDao — intent stamping is now live, so
        // a buggy canonicalization would surface as a non-null
        // deleteIntentEpoch and a non-empty getDeletedLinkedSessions().
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // A locally-pushed front: random v4 id, stamped with the real switch
        // uuid the API will report. Never re-keyed to the deterministic id,
        // so it is non-canonical by id — exactly the C1 population. The
        // switch id MUST be uuid-shaped: `isPluralKitSwitchUuid` is a strict
        // 8-4-4-4-12 hex gate, and a non-uuid id would short-circuit the
        // canonicalization loop entirely, making this test vacuous.
        const localPushedId = '11111111-2222-4333-8444-555555555555';
        const switchUuid = '1f1f1f1f-0000-4000-8000-000000000001';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: localPushedId,
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: switchUuid,
          ),
        );

        final sw1 = PKSwitch(
          id: switchUuid,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await _link(service);
        await service.performFullImport();

        // The row survives under its original id (adopted in place), still
        // live and still linked to the same switch.
        final all = await sessionRepo.getAllSessions();
        expect(all, hasLength(1), reason: 'locally-pushed row was preserved');
        final row = all.single;
        expect(row.id, localPushedId, reason: 'adopted in place, not re-keyed');
        expect(row.isDeleted, isFalse);
        expect(row.pluralkitUuid, switchUuid);
        expect(row.memberId, 'local-a');

        // CRITICAL C1 assertion: nothing was stamped for PK-side deletion.
        final raw = await db.frontingSessionsDao.getAllSessionsIncludingDeleted();
        expect(
          raw.where((s) => s.deleteIntentEpoch != null),
          isEmpty,
          reason: 'canonicalization must not stamp ANY delete intent',
        );
        expect(
          await sessionRepo.getDeletedLinkedSessions(),
          isEmpty,
          reason: 'no PK switch deletion may be queued by a re-import',
        );
      },
    );

    test(
      '(b) leaves rows for an unlinked member entirely alone (H4) — no '
      'tombstone, no delete intent',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // A historical PK-linked row for local-a at some switch. The switch
        // uuid must be uuid-shaped to pass the strict `isPluralKitSwitchUuid`
        // gate — otherwise the loop never even considers this row and the
        // test is vacuous.
        const rowId = '99999999-aaaa-4bbb-8ccc-dddddddddddd';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rowId,
            startTime: DateTime.utc(2025, 6, 1, 8),
            endTime: DateTime.utc(2025, 6, 1, 9),
            memberId: 'local-a',
            pluralkitUuid: '2f2f2f2f-0000-4000-8000-000000000001',
          ),
        );

        // Now UNLINK local-a (clear its pluralkit ids). After this the member
        // no longer resolves in uuidToLocalId, so the canonical set built
        // from currently-resolvable members can't cover its rows.
        await db.membersDao.updateMemberById(
          'local-a',
          const MembersCompanion(
            pluralkitId: Value(null),
            pluralkitUuid: Value(null),
          ),
        );

        // The API reports an unrelated switch (no members the device maps).
        final sw1 = PKSwitch(
          id: '2f2f2f2f-0000-4000-8000-000000000099',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkZ'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await _link(service);
        await service.performFullImport();

        // The unlinked member's historical row is untouched.
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final preserved = raw.firstWhere((s) => s.id == rowId);
        expect(
          preserved.isDeleted,
          isFalse,
          reason: 'H4: unlinked member history must not be tombstoned',
        );
        expect(
          raw.where((s) => s.deleteIntentEpoch != null),
          isEmpty,
          reason: 'H4: no delete intent for excluded/unmapped members',
        );
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
      },
    );

    test(
      '(b2) leaves rows for a pluralkitSyncIgnored member alone (H4)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // Uuid-shaped switch ref so the row passes the strict
        // `isPluralKitSwitchUuid` gate and the H4 skip branch is actually
        // exercised (a non-uuid id would make this test vacuous).
        const rowId = '88888888-aaaa-4bbb-8ccc-eeeeeeeeeeee';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rowId,
            startTime: DateTime.utc(2025, 6, 1, 8),
            memberId: 'local-a',
            pluralkitUuid: '3f3f3f3f-0000-4000-8000-000000000001',
          ),
        );

        // Mark the member as excluded from PK sync. The map builders skip
        // `pluralkitSyncIgnored` members, so local-a won't be in the
        // resolvable set.
        await db.membersDao.updateMemberById(
          'local-a',
          const MembersCompanion(pluralkitSyncIgnored: Value(true)),
        );

        final sw1 = PKSwitch(
          id: '3f3f3f3f-0000-4000-8000-000000000099',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await _link(service);
        await service.performFullImport();

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final preserved = raw.firstWhere((s) => s.id == rowId);
        expect(preserved.isDeleted, isFalse);
        expect(raw.where((s) => s.deleteIntentEpoch != null), isEmpty);
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
      },
    );

    test(
      '(c) tombstones a genuine rescue artifact (switch not in the API) but '
      'clears the link first and stamps NO delete intent',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // A rescue artifact: linked to a switch uuid the API fixture does
        // NOT contain, for a resolvable member. This is the population that
        // SHOULD be tombstoned — but via clear-link-then-delete so the
        // deletion pusher never fires.
        const rescueId = '77777777-aaaa-4bbb-8ccc-ffffffffffff';
        const ghostSwitch = '00000000-0000-0000-0000-0000000000aa';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rescueId,
            startTime: DateTime.utc(2025, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: ghostSwitch,
          ),
        );

        // The API only knows sw-1 (for local-a) — the ghost switch is gone.
        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await _link(service);
        await service.performFullImport();

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final rescue = raw.firstWhere((s) => s.id == rescueId);
        expect(
          rescue.isDeleted,
          isTrue,
          reason: 'genuine rescue artifact is tombstoned',
        );
        expect(
          rescue.pluralkitUuid,
          isNull,
          reason: 'PK link cleared BEFORE tombstoning (C1 idiom)',
        );
        expect(
          rescue.deleteIntentEpoch,
          isNull,
          reason: 'no delete intent — importer cleanup must not push DELETE',
        );
        // The deletion pusher only ever picks up rows with BOTH a non-null
        // pluralkit_uuid AND a non-null intent epoch — this row has neither.
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
      },
    );

    test(
      'sanity: an explicit user delete (deleteSession on a linked live row) '
      'DOES stamp intent — proves the test wiring can observe stamping',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        const id = '66666666-aaaa-4bbb-8ccc-aaaaaaaaaaaa';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: id,
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: 'sw-1',
          ),
        );
        // Explicit user delete: link present → intent stamped.
        await sessionRepo.deleteSession(id);

        final queued = await sessionRepo.getDeletedLinkedSessions();
        expect(
          queued.map((s) => s.id),
          contains(id),
          reason: 'control: deleteSession on a linked row stamps intent so '
              'the (a)/(c) "no intent" assertions are meaningful',
        );
      },
    );
  });
}
