/// H2: deleting one co-fronter's row must not DELETE the whole shared PK
/// switch, and the remaining-members list must come from PK itself (local
/// rows only carry ENTRANT switch uuids). Tests use REAL Drift repos wired
/// WITH `pkSyncDao` so intent stamping runs against the same database.
library;

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
// Secure-storage mock
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
// Recording fake client: serves getSwitch from configured snapshots (404 +
// code 20007 when absent, mirroring the live API) and records deleteSwitch +
// updateSwitchMembers calls. updateSwitchMembers can be told to throw.
// ---------------------------------------------------------------------------

class _RecordingClient implements PluralKitClient {
  _RecordingClient({this.patchError});

  /// If non-null, `updateSwitchMembers` throws this AFTER recording.
  final PluralKitApiError? patchError;

  /// PK-side switch snapshots served by [getSwitch], keyed by switch uuid.
  final Map<String, PKSwitch> switchSnapshots = {};

  int getSwitchCalls = 0;
  final List<String> deletedSwitches = [];
  final List<({String switchId, List<String> members})> patchedSwitches = [];

  /// When set, [getSwitch] throws this instead of consulting the snapshot
  /// map — used to exercise the transient-failure branch.
  Object? getSwitchError;

  @override
  Future<PKSwitch> getSwitch(String switchRef) async {
    getSwitchCalls++;
    if (getSwitchError != null) throw getSwitchError!;
    final sw = switchSnapshots[switchRef.trim()];
    if (sw == null) {
      throw const PluralKitApiError(
        404,
        '{"message":"Switch not found.","code":20007}',
        code: 20007,
      );
    }
    return sw;
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    deletedSwitches.add(switchId);
  }

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    patchedSwitches.add((switchId: switchId, members: memberIds));
    if (patchError != null) throw patchError!;
    return PKSwitch(
      id: switchId,
      timestamp: DateTime.utc(2026, 1, 1),
      members: memberIds,
    );
  }

  @override
  String get currentToken => 'fake-token';
  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');
  @override
  Future<List<PKMember>> getMembers() async => const [];
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async => const [];
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

// A real switch uuid all co-fronters share, plus the earlier switch a
// continuing member entered at.
const _sharedSwitch = '0a0a0a0a-0000-0000-0000-000000000002';
const _earlierSwitch = '0a0a0a0a-0000-0000-0000-000000000001';

PluralKitSyncService _makeService({
  required AppDatabase db,
  required _RecordingClient client,
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

  group('shared-switch deletion (H2, PK-authoritative)', () {
    test(
      'CONTINUING co-fronter absent from local rows is preserved: PK '
      'snapshot [A,B,C], local rows only A@sw2 + C@sw2 (B entered at sw1) '
      '→ deleting A PATCHes [B,C] in PK order',
      () async {
        // THE key regression: PK history sw1=[B], sw2=[A,B,C].
        // Local canonical rows carry only ENTRANT switch uuids: B@sw1,
        // A@sw2, C@sw2. A locally-derived sibling list for sw2 sees only C
        // and would PATCH sw2 to [C] — removing B from sw2's full snapshot,
        // i.e. B's PK timeline would show B leaving the front at sw2. The
        // PK-authoritative remaining list must keep B.
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );
        await memberRepo.createMember(
          _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        );
        await memberRepo.createMember(
          _member(localId: 'local-c', pkShortId: 'pkC', pkUuid: 'uuid-c'),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        // B's row is anchored at the EARLIER switch (B continued fronting
        // across sw2 — no local row links B to sw2).
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-b',
            startTime: DateTime.utc(2026, 1, 1, 9),
            memberId: 'local-b',
            pluralkitUuid: _earlierSwitch,
          ),
        );
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-a',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-c',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-c',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        // User deletes A's row → intent stamped (pkSyncDao wired).
        await sessionRepo.deleteSession('row-a');

        final client = _RecordingClient();
        // PK's authoritative sw2 snapshot: ALL fronters, including the
        // continuing B. Note 'PkA' — hids are case-insensitive on PK, so
        // the departing-member subtraction must match case-insensitively.
        client.switchSnapshots[_sharedSwitch] = PKSwitch(
          id: _sharedSwitch,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['PkA', 'pkB', 'pkC'],
        );
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        // No DELETE on the shared switch.
        expect(client.deletedSwitches, isEmpty);
        // PATCH removed only A; B (continuing, no local row at sw2) and C
        // are both kept, in PK's order.
        expect(client.patchedSwitches, hasLength(1));
        expect(client.patchedSwitches.single.switchId, _sharedSwitch);
        expect(
          client.patchedSwitches.single.members,
          ['pkB', 'pkC'],
          reason: 'continuing co-fronter B must survive; PK order preserved',
        );
        expect(pushed, 1, reason: 'the member-removal counts as pushed');

        // Link cleared on A's tombstone; B's and C's live rows untouched.
        final aRow = await sessionRepo.getSessionById('row-a');
        expect(aRow!.pluralkitUuid, isNull);
        final bRow = await sessionRepo.getSessionById('row-b');
        expect(bRow!.isDeleted, isFalse);
        expect(bRow.pluralkitUuid, _earlierSwitch);
        final cRow = await sessionRepo.getSessionById('row-c');
        expect(cRow!.isDeleted, isFalse);
        expect(cRow.pluralkitUuid, _sharedSwitch);
      },
    );

    test(
      'sole-fronter snapshot (no co-fronters on PK) still DELETEs the switch',
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

        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-solo',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.deleteSession('row-solo');

        final client = _RecordingClient();
        client.switchSnapshots[_sharedSwitch] = PKSwitch(
          id: _sharedSwitch,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        // PK's snapshot has only the departing member → full-snapshot
        // semantics guarantee no continuing fronter exists on it → the
        // historical DELETE path is preserved.
        expect(client.patchedSwitches, isEmpty);
        expect(client.deletedSwitches, [_sharedSwitch]);
        expect(pushed, 1);
        final solo = await sessionRepo.getSessionById('row-solo');
        expect(solo!.pluralkitUuid, isNull);
      },
    );

    test(
      'transient GET failure keeps the link and intent for a later retry',
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

        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-transient',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.deleteSession('row-transient');

        final client = _RecordingClient();
        // A 5xx (e.g. Fly/Caddy blip) is NOT terminal: the deletion must
        // stay queued — link and intent intact — so a later pass retries.
        client.getSwitchError = const PluralKitApiError(
          500,
          'Internal Server Error',
        );
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        expect(pushed, 0);
        expect(client.patchedSwitches, isEmpty);
        expect(client.deletedSwitches, isEmpty);
        final row = await sessionRepo.getSessionById('row-transient');
        expect(row!.pluralkitUuid, _sharedSwitch,
            reason: 'a transient failure must not clear the link');
        expect(row.deleteIntentEpoch, isNotNull,
            reason: 'the queued deletion must survive for the next pass');
      },
    );

    test('40004 on the members PATCH is treated as success', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );
      await memberRepo.createMember(
        _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
      );

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
        pkSyncDao: db.pluralKitSyncDao,
      );

      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'row-a',
          startTime: DateTime.utc(2026, 1, 1, 10),
          memberId: 'local-a',
          pluralkitUuid: _sharedSwitch,
        ),
      );
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'row-b',
          startTime: DateTime.utc(2026, 1, 1, 10),
          memberId: 'local-b',
          pluralkitUuid: _sharedSwitch,
        ),
      );
      await sessionRepo.deleteSession('row-a');

      // PK rejects the PATCH as identical-to-current (the body embeds 40004).
      final client = _RecordingClient(
        patchError: const PluralKitApiError(
          400,
          '{"message":"Member list identical","code":40004}',
          code: 40004,
        ),
      );
      client.switchSnapshots[_sharedSwitch] = PKSwitch(
        id: _sharedSwitch,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA', 'pkB'],
      );
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );

      final pushed = await service.debugPushPendingSwitchDeletions(
        client: client,
      );

      // Attempted the PATCH, no DELETE, counted as success, link cleared.
      expect(client.patchedSwitches, hasLength(1));
      expect(client.deletedSwitches, isEmpty);
      expect(pushed, 1, reason: '40004 (already identical) is benign success');
      final aRow = await sessionRepo.getSessionById('row-a');
      expect(aRow!.pluralkitUuid, isNull);
    });

    test(
      'unresolvable departing member → fail-safe: clear link, never DELETE '
      'or PATCH',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        // The departing member exists locally but has NO pluralkit refs —
        // we cannot tell which snapshot entry to subtract, so we must not
        // write to PK at all (the snapshot may hold co-fronters).
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          domain.Member(
            id: 'local-a',
            name: 'Member a',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            // no pluralkitId / pluralkitUuid → unresolvable
          ),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );

        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-a',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.deleteSession('row-a');

        final client = _RecordingClient();
        client.switchSnapshots[_sharedSwitch] = PKSwitch(
          id: _sharedSwitch,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA', 'pkB'],
        );
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        // Fail-safe: no PK write at all; local link cleared so we stop
        // re-attempting; the switch is left intact for any co-fronters.
        expect(client.deletedSwitches, isEmpty);
        expect(client.patchedSwitches, isEmpty);
        expect(pushed, 0);
        final aRow = await sessionRepo.getSessionById('row-a');
        expect(aRow!.pluralkitUuid, isNull);
      },
    );

    test(
      'departing member not on the PK snapshot → already off PK: clear link, '
      'no write, not counted as pushed',
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

        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-a',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.deleteSession('row-a');

        final client = _RecordingClient();
        // Another client already removed A from the switch server-side.
        client.switchSnapshots[_sharedSwitch] = PKSwitch(
          id: _sharedSwitch,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkB', 'pkC'],
        );
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        expect(client.deletedSwitches, isEmpty);
        expect(client.patchedSwitches, isEmpty);
        expect(pushed, 0, reason: 'handled (already off PK), not pushed');
        final aRow = await sessionRepo.getSessionById('row-a');
        expect(aRow!.pluralkitUuid, isNull);
      },
    );

    test(
      'switch gone on PK (getSwitch 404/20007) → clear link, no write',
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

        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'row-a',
            startTime: DateTime.utc(2026, 1, 1, 10),
            memberId: 'local-a',
            pluralkitUuid: _sharedSwitch,
          ),
        );
        await sessionRepo.deleteSession('row-a');

        // No snapshot configured → getSwitch throws 404/20007.
        final client = _RecordingClient();
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final pushed = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        expect(client.getSwitchCalls, 1);
        expect(client.deletedSwitches, isEmpty);
        expect(client.patchedSwitches, isEmpty);
        expect(pushed, 0);
        final aRow = await sessionRepo.getSessionById('row-a');
        expect(aRow!.pluralkitUuid, isNull);
      },
    );
  });
}
