/// F22 (wave-2 pk-import-canonicalization-destruction): the corrective
/// full-import canonicalization pass must be RESTRICTED to members inside the
/// canonical computation domain — those whose switches were enumerable while
/// `canonicalIds` was built. A row whose member fell outside that domain
/// (`pluralkitSyncIgnored`, PK link auto-cleared, or a legacy `memberId == null`
/// shape) is preserved untouched and reported via the new
/// `unresolvableMemberRowsPreserved` counter, instead of being tombstoned as a
/// "stale rescue artifact" — which under absorbing CRDT delete semantics would
/// destroy that member's entire valid fronting history on every paired device.
///
/// These tests drive the REAL `performOneTimeFullImport` so the returned
/// [PkTokenImportResult] counter is observed, and wire the fronting-session
/// repository WITH `pkSyncDao` (production wiring) so any spurious
/// canonicalization tombstone would also surface as a `deleteIntentEpoch`.
///
/// Coverage:
///  (1) a `pluralkitSyncIgnored` member's imported history is FULLY preserved
///      and `unresolvableMemberRowsPreserved` equals their row count.
///  (2) the same with the member's `pluralkit_uuid`/`pluralkit_id` nulled
///      (PkStaleLinkException auto-clear shape).
///  (3) regression: rescue fan-out artifacts of a STILL-MAPPED member ARE
///      still tombstoned (the domain guard must not break legitimate
///      canonicalization), and that row is NOT counted as preserved.
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
// Secure-storage mock (mirrors pk_canonicalization_safety_test.dart)
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
// Fake client returning a fixed switch history (single page; tiny fixtures).
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  _FakeClient(this.allSwitches);

  /// Newest-first switch history. Returned on the first `getSwitches` call;
  /// `before`-bearing calls return empty so paging terminates.
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
  Future<PKSwitch> getSwitch(String switchRef) => throw UnimplementedError();

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('F22 canonicalization domain restriction', () {
    test(
      "(1) a pluralkitSyncIgnored member's imported history is fully preserved "
      'and unresolvableMemberRowsPreserved == row count',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        // Repository wired WITH pkSyncDao so a spurious tombstone would surface
        // as a delete intent too.
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // Two historical PK-linked rows for the member, at two real (uuid-
        // shaped) switch uuids so they pass the strict `isPluralKitSwitchUuid`
        // gate and the domain predicate is actually exercised.
        const rowA = '11111111-aaaa-4bbb-8ccc-000000000001';
        const rowB = '11111111-aaaa-4bbb-8ccc-000000000002';
        const switch1 = '5f5f5f5f-0000-4000-8000-000000000001';
        const switch2 = '5f5f5f5f-0000-4000-8000-000000000002';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rowA,
            startTime: DateTime.utc(2025, 6, 1, 8),
            endTime: DateTime.utc(2025, 6, 1, 9),
            memberId: 'local-a',
            pluralkitUuid: switch1,
          ),
        );
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rowB,
            startTime: DateTime.utc(2025, 6, 2, 8),
            memberId: 'local-a',
            pluralkitUuid: switch2,
          ),
        );

        // Mark the member excluded from PK sync. The map builders skip
        // `pluralkitSyncIgnored` members, so local-a leaves the canonical
        // domain and its rows can never enter `canonicalIds`.
        await db.membersDao.updateMemberById(
          'local-a',
          const MembersCompanion(pluralkitSyncIgnored: Value(true)),
        );

        // API reports a switch the device does not map (the ignored member's
        // short id resolves to nothing).
        final sw1 = PKSwitch(
          id: '5f5f5f5f-0000-4000-8000-000000000099',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final result = await service.performOneTimeFullImport(token: 't');

        // BOTH rows stay live, undeleted, links intact.
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        for (final id in const [rowA, rowB]) {
          final row = raw.firstWhere((s) => s.id == id);
          expect(row.isDeleted, isFalse, reason: 'row $id preserved');
          expect(
            row.pluralkitUuid,
            isNotNull,
            reason: 'row $id link left intact',
          );
        }
        expect(
          raw.where((s) => s.deleteIntentEpoch != null),
          isEmpty,
          reason: 'no delete intent for an excluded member',
        );
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);

        // The counter equals the preserved row count and is surfaced.
        expect(result.unresolvableMemberRowsPreserved, 2);
      },
    );

    test(
      "(2) same with the member's pluralkit_uuid/pluralkit_id nulled "
      '(PkStaleLinkException auto-clear shape) — preserved + counted',
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

        const rowId = '22222222-aaaa-4bbb-8ccc-000000000001';
        const switchUuid = '6f6f6f6f-0000-4000-8000-000000000001';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: rowId,
            startTime: DateTime.utc(2025, 6, 1, 8),
            memberId: 'local-a',
            pluralkitUuid: switchUuid,
          ),
        );

        // Auto-clear shape: PkStaleLinkException nulls BOTH pluralkit ids on
        // the member. After this local-a no longer resolves in any map and is
        // outside the canonical domain.
        await db.membersDao.updateMemberById(
          'local-a',
          const MembersCompanion(
            pluralkitId: Value(null),
            pluralkitUuid: Value(null),
          ),
        );

        final sw1 = PKSwitch(
          id: '6f6f6f6f-0000-4000-8000-000000000099',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkZ'],
        );
        final service = _makeServiceWithPkDao(
          db: db,
          client: _FakeClient([sw1]),
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final result = await service.performOneTimeFullImport(token: 't');

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final preserved = raw.firstWhere((s) => s.id == rowId);
        expect(preserved.isDeleted, isFalse);
        expect(preserved.pluralkitUuid, switchUuid, reason: 'link intact');
        expect(raw.where((s) => s.deleteIntentEpoch != null), isEmpty);
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
        expect(result.unresolvableMemberRowsPreserved, 1);
      },
    );

    test(
      '(3) regression: rescue fan-out artifacts of a STILL-MAPPED member ARE '
      'still tombstoned and are NOT counted as preserved',
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

        // A genuine rescue fan-out artifact: still-mapped member, linked to a
        // switch uuid the API fixture does NOT report. This is exactly the
        // F03 det(sw-2,A)/det(sw-3,A) population the canonicalization must
        // still tombstone.
        const artifactId = '33333333-aaaa-4bbb-8ccc-000000000001';
        const ghostSwitch = '7f7f7f7f-0000-4000-8000-000000000aaa';
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: artifactId,
            startTime: DateTime.utc(2025, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: ghostSwitch,
          ),
        );

        // API only knows sw-1 for the still-mapped member — the ghost switch
        // is gone, so the artifact's (switch, member) pair is non-canonical.
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

        final result = await service.performOneTimeFullImport(token: 't');

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        final artifact = raw.firstWhere((s) => s.id == artifactId);
        expect(
          artifact.isDeleted,
          isTrue,
          reason: 'still-mapped rescue artifact IS tombstoned (domain guard '
              'must not break legitimate canonicalization)',
        );
        // F03/C1: link cleared first, no delete intent — importer cleanup
        // never queues a real PK switch DELETE.
        expect(artifact.pluralkitUuid, isNull);
        expect(artifact.deleteIntentEpoch, isNull);
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);

        // A tombstoned in-domain artifact is NOT a preserved unresolvable row.
        expect(result.unresolvableMemberRowsPreserved, 0);
      },
    );
  });
}
