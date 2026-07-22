// Tests for setToken() branching by systemId.
//
// Three scenarios:
//   (a) Same systemId reconnect — both flags preserved, linkedAt unchanged.
//   (b) Different systemId — both flags reset to false, linkedAt updated.
//   (c) Fresh connect (no pre-existing row) — flags start false, row created.
//
// Uses the same mock/fixture patterns as pluralkit_sync_service_test.dart.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Secure-storage stub (same pattern as pluralkit_sync_service_test.dart)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};

  /// When true, the 'write' handler throws BEFORE mutating the store —
  /// simulating a classified secure-storage write failure for the H9
  /// "couldn't save the token" path. The store stays untouched, mirroring
  /// the real plugin contract (a failed write never half-writes).
  bool throwOnWrite = false;
  int writeCount = 0;
  int deleteCount = 0;

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                writeCount++;
                if (throwOnWrite) {
                  throw PlatformException(
                    code: 'PrismTestWriteFailure',
                    message: 'injected secure-storage write failure',
                  );
                }
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                _store[key] = value;
                return null;
              case 'read':
                final key = call.arguments['key'] as String;
                return _store[key];
              case 'delete':
                deleteCount++;
                final key = call.arguments['key'] as String;
                _store.remove(key);
                return null;
              case 'containsKey':
                final key = call.arguments['key'] as String;
                return _store.containsKey(key);
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
    throwOnWrite = false;
    writeCount = 0;
    deleteCount = 0;
  }
}

// ---------------------------------------------------------------------------
// Minimal fake PluralKitClient
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  _FakeClient(this._systemId);

  final String _systemId;

  /// Optional handler for `createMember` so PR 1's re-push test can return a
  /// fabricated PK member instead of the default `UnimplementedError`. Counts
  /// invocations.
  PKMember Function(Map<String, dynamic> data)? onCreate;
  int createCallCount = 0;

  /// Failure knobs for the H9 token-rotation tests: simulate a 401 or a
  /// transport failure from `getSystem` (the setToken validation call).
  bool throwAuthError = false;
  bool throwNetworkError = false;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async {
    if (throwAuthError) throw const PluralKitAuthError();
    if (throwNetworkError) throw Exception('Network unreachable');
    return PKSystem(id: _systemId, name: 'Test System');
  }

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async =>
      const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    if (onCreate == null) throw UnimplementedError();
    return onCreate!(data);
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Minimal fake repositories (only what setToken exercises)
// ---------------------------------------------------------------------------

class _FakeMemberRepository implements MemberRepository {
  @override
  Future<List<domain.Member>> getAllMembers() async => const [];
  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => const [];
  @override
  Future<domain.Member?> getMemberById(String id) async => null;
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async => const [];
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(const []);
  @override
  Future<void> createMember(domain.Member member) async {}
  @override
  Future<void> updateMember(domain.Member member) async {}
  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 0;
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      0;
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => 0;
  @override
  Future<int> excludePluralKitSync(String id) async => 0;
  @override
  Future<int> resumePluralKitSync(String id) async => 0;
  @override
  Future<void> deleteMember(String id) async {}
  @override
  Stream<List<domain.Member>> watchAllMembers() => Stream.value(const []);
  @override
  Stream<List<domain.Member>> watchActiveMembers() => Stream.value(const []);
  @override
  Stream<domain.Member?> watchMemberById(String id) => Stream.value(null);
  @override
  Future<int> getCount() async => 0;
  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> clearCreatePushStartedAt(String id) async {}
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

class _FakeFrontingSessionRepository implements FrontingSessionRepository {
  @override
  Future<List<domain.FrontingSession>> getAllSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      const [];
  @override
  Future<domain.FrontingSession?> getActiveSession() async => null;
  @override
  Future<domain.FrontingSession?> getSessionById(String id) async => null;
  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
    String memberId,
  ) async => const [];
  @override
  Future<List<domain.FrontingSession>> getRecentSessions({
    int limit = 20,
  }) async => const [];
  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async => const [];
  @override
  Future<void> createSession(domain.FrontingSession session) async {}
  @override
  Future<void> updateSession(domain.FrontingSession session) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Stream<List<domain.FrontingSession>> watchActiveSessions() =>
      Stream.value(const []);
  @override
  Stream<domain.FrontingSession?> watchActiveSession() => Stream.value(null);
  @override
  Stream<domain.FrontingSession?> watchActiveSleepSession() =>
      Stream.value(null);
  @override
  Stream<List<domain.FrontingSession>> watchAllSleepSessions() =>
      Stream.value(const []);
  @override
  Stream<domain.FrontingSession?> watchSessionById(String id) =>
      Stream.value(null);
  @override
  Stream<List<domain.FrontingSession>> watchAllSessions() =>
      Stream.value(const []);
  @override
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(const []);
  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) => Stream.value(const []);
  @override
  Stream<List<domain.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) => Stream.value(const []);
  @override
  Stream<List<domain.FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) => Stream.value(const []);
  @override
  Future<List<domain.FrontingSession>> getDeletedSleepSessions() async =>
      const [];

  @override
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions() async =>
      const [];
  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
  @override
  Future<void> endSession(String id, DateTime endTime) async {}
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<int> getCount() async => 0;
  @override
  Future<int> getFrontingCount() async => 0;
  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) async => const {};
  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) async => (count: 0, avgDuration: null);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

PluralKitSyncService _makeService(AppDatabase db, String systemId) {
  return PluralKitSyncService(
    memberRepository: _FakeMemberRepository(),
    frontingSessionRepository: _FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => _FakeClient(systemId),
  );
}

// Seeds the DAO row with the given flags and systemId so that the next
// setToken call can observe an existing row.
Future<void> _seedRow(
  AppDatabase db, {
  required String systemId,
  required bool mappingAcknowledged,
  required bool directionConfirmed,
  required DateTime linkedAt,
}) async {
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      systemId: Value(systemId),
      isConnected: const Value(true),
      mappingAcknowledged: Value(mappingAcknowledged),
      directionConfirmed: Value(directionConfirmed),
      linkedAt: Value(linkedAt),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('setToken — same systemId (token rotation)', () {
    test('preserves both flags and linkedAt when systemId matches', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final t0 = DateTime(2024, 1, 1, 12, 0, 0).toUtc();
      await _seedRow(
        db,
        systemId: 'sys-X',
        mappingAcknowledged: true,
        directionConfirmed: true,
        linkedAt: t0,
      );

      // Service whose client returns the SAME systemId.
      final service = _makeService(db, 'sys-X');
      await service.setToken('new-token');

      // In-memory state: both flags preserved.
      expect(service.state.isConnected, isTrue);
      expect(service.state.mappingAcknowledged, isTrue);
      expect(service.state.directionConfirmed, isTrue);
      expect(service.state.canAutoSync, isTrue);
      // Compare by epoch ms to avoid UTC/local timezone divergence from Drift.
      expect(
        service.state.linkedAt?.millisecondsSinceEpoch,
        equals(t0.millisecondsSinceEpoch),
      );

      // Persisted state: verify via DAO.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.mappingAcknowledged, isTrue);
      expect(row.directionConfirmed, isTrue);
      expect(
        row.linkedAt?.millisecondsSinceEpoch,
        equals(t0.millisecondsSinceEpoch),
      );
    });
  });

  group('setToken — different systemId', () {
    test('resets both flags, updates linkedAt, and bumps linkEpoch', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final t0 = DateTime(2024, 1, 1, 12, 0, 0).toUtc();
      await _seedRow(
        db,
        systemId: 'sys-X',
        mappingAcknowledged: true,
        directionConfirmed: true,
        linkedAt: t0,
      );

      // Service whose client returns a DIFFERENT systemId.
      final service = _makeService(db, 'sys-Y');
      await service.setToken('new-token');

      // In-memory state: both flags reset.
      expect(service.state.isConnected, isTrue);
      expect(service.state.mappingAcknowledged, isFalse);
      expect(service.state.directionConfirmed, isFalse);
      expect(service.state.needsDirection, isTrue);
      expect(service.state.canAutoSync, isFalse);
      // linkedAt updated (different from t0).
      expect(service.state.linkedAt, isNotNull);
      expect(service.state.linkedAt, isNot(equals(t0)));

      // Persisted state: verify via DAO.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.mappingAcknowledged, isFalse);
      expect(row.directionConfirmed, isFalse);
      expect(row.linkedAt, isNot(equals(t0)));

      // linkEpoch bumped because systemId changed.
      final epoch = await db.pluralKitSyncDao.getLinkEpoch();
      expect(epoch, greaterThan(0));
    });
  });

  group('setToken — fresh connect (no existing row)', () {
    test('creates row with both flags false, isConnected=true', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final service = _makeService(db, 'sys-Z');
      await service.setToken('initial-token');

      expect(service.state.isConnected, isTrue);
      expect(service.state.mappingAcknowledged, isFalse);
      expect(service.state.directionConfirmed, isFalse);
      expect(service.state.needsDirection, isTrue);
      expect(service.state.canAutoSync, isFalse);
      expect(service.state.linkedAt, isNotNull);

      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isTrue);
      expect(row.mappingAcknowledged, isFalse);
      expect(row.directionConfirmed, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PR 1 (mapping recovery): pk_mapping_state behavior on system swap.
  //
  // setToken's `!isSameSystem` branch must `clearAll` pk_mapping_state so a
  // re-mapping against a different PK system isn't silently no-op'd by stale
  // "applied" rows keyed to the prior session's identifiers. The same-system
  // branch must NOT clear (it's a token rotation, not a remap).
  // ---------------------------------------------------------------------------

  group('PR 1: setToken — pk_mapping_state lifecycle', () {
    test(
      'same-system token rotation preserves pk_mapping_state rows',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        await _seedRow(
          db,
          systemId: 'sys-X',
          mappingAcknowledged: true,
          directionConfirmed: true,
          linkedAt: DateTime(2024, 1, 1, 12).toUtc(),
        );

        // Seed an applied push row tied to the prior token.
        await PkMappingStateDao(db).upsert(
          PkMappingStateCompanion(
            id: const Value('push:l1'),
            decisionType: const Value('push'),
            localMemberId: const Value('l1'),
            status: const Value('applied'),
            createdAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
            updatedAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
          ),
        );

        // Service whose client returns the SAME systemId — token rotation.
        final service = _makeService(db, 'sys-X');
        await service.setToken('new-token');

        final rows = await PkMappingStateDao(db).getAll();
        expect(
          rows.map((r) => r.id),
          contains('push:l1'),
          reason:
              'Same-system token rotation must NOT clear pk_mapping_state',
        );
      },
    );

    test(
      'different-system swap clears pk_mapping_state',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        await _seedRow(
          db,
          systemId: 'sys-X',
          mappingAcknowledged: true,
          directionConfirmed: true,
          linkedAt: DateTime(2024, 1, 1, 12).toUtc(),
        );

        await PkMappingStateDao(db).upsert(
          PkMappingStateCompanion(
            id: const Value('push:l1'),
            decisionType: const Value('push'),
            localMemberId: const Value('l1'),
            status: const Value('applied'),
            createdAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
            updatedAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
          ),
        );

        final before = await PkMappingStateDao(db).getAll();
        expect(before, hasLength(1));

        // Service whose client returns a DIFFERENT systemId.
        final service = _makeService(db, 'sys-Y');
        await service.setToken('new-token');

        final after = await PkMappingStateDao(db).getAll();
        expect(
          after,
          isEmpty,
          reason:
              'Different-system swap must clear pk_mapping_state so a '
              're-mapping is not silently no-op\'d by stale applied rows',
        );
      },
    );

    test(
      're-push of same local after different-system swap succeeds (no '
      'alreadyApplied)',
      () async {
        // End-to-end proof of why the clear matters: after a system swap a
        // PkPushNewDecision for the same local id must produce a real
        // applier write, not an alreadyApplied no-op against the prior
        // session's "push:l1" row.
        final db = _makeDb();
        addTearDown(db.close);

        await _seedRow(
          db,
          systemId: 'sys-X',
          mappingAcknowledged: true,
          directionConfirmed: true,
          linkedAt: DateTime(2024, 1, 1, 12).toUtc(),
        );
        await PkMappingStateDao(db).upsert(
          PkMappingStateCompanion(
            id: const Value('push:l1'),
            decisionType: const Value('push'),
            localMemberId: const Value('l1'),
            pkMemberId: const Value('priorid'),
            pkMemberUuid: const Value('prior-uuid'),
            status: const Value('applied'),
            createdAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
            updatedAt: Value(DateTime(2024, 1, 1, 12).toUtc()),
          ),
        );

        // Swap to a different system.
        final memberRepo = _RepushMemberRepo([
          domain.Member(
            id: 'l1',
            name: 'Alice',
            createdAt: DateTime(2024).toUtc(),
          ),
        ]);
        final client = _FakeClient('sys-Y')
          ..onCreate = (data) => PKMember(
                id: 'newid',
                uuid: 'new-uuid',
                name: data['name'] as String,
              );
        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: _FakeFrontingSessionRepository(),
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => client,
        );
        await service.setToken('new-token');

        // Now drive the applier directly against the cleared state.
        final applier = PkMappingApplier(
          members: memberRepo,
          state: PkMappingStateDao(db),
          pushService: const PkPushService(),
          client: client,
          bus: PkSyncEventBus(),
        );
        final results = await applier.apply([
          const PkPushNewDecision(localMemberId: 'l1'),
        ]);

        expect(
          results.single.outcome,
          PkApplyOutcome.applied,
          reason:
              'After system swap the prior "push:l1" row must be gone; '
              'this decision must not be reported as alreadyApplied',
        );
        expect(client.createCallCount, 1);

        final updated = await memberRepo.getMemberById('l1');
        expect(updated!.pluralkitId, 'newid');
        expect(updated.pluralkitUuid, 'new-uuid');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // H9: failed token rotation must not destroy the working token, and the
  // DB/storage must never diverge. New contract: validate first (ephemeral
  // client), persist only on success with a CHECKED safeSecureWrite, and
  // leave the prior token + connection state untouched on any failure.
  // ---------------------------------------------------------------------------

  group('H9: setToken failure leaves the working token intact', () {
    const pkTokenKey = 'prism_pluralkit_token';
    final t0 = DateTime(2024, 1, 1, 12).toUtc();

    PluralKitSyncService makeServiceWithClient(
      AppDatabase db,
      _FakeClient client,
    ) {
      return PluralKitSyncService(
        memberRepository: _FakeMemberRepository(),
        frontingSessionRepository: _FakeFrontingSessionRepository(),
        syncDao: db.pluralKitSyncDao,
        bus: PkSyncEventBus(),
        secureStorage: const FlutterSecureStorage(),
        clientFactory: (_) => client,
      );
    }

    test('401 during rotation: old token + connection state untouched',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      await _seedRow(
        db,
        systemId: 'sys-X',
        mappingAcknowledged: true,
        directionConfirmed: true,
        linkedAt: t0,
      );
      // A working token from the prior successful connect.
      storageStub._store[pkTokenKey] = 'old-working-token';

      final client = _FakeClient('sys-X')..throwAuthError = true;
      final service = makeServiceWithClient(db, client);
      await service.loadState();
      expect(service.state.isConnected, isTrue);

      await service.setToken('bad-new-token');

      // Storage: the working token survives; nothing was written or deleted.
      expect(
        storageStub._store[pkTokenKey],
        'old-working-token',
        reason: 'H9: a failed rotation must not overwrite the working token',
      );
      expect(storageStub.writeCount, 0,
          reason: 'H9: validation must precede any storage write');
      expect(storageStub.deleteCount, 0,
          reason: 'H9: failure paths must never delete the token slot');

      // DB + in-memory state: still connected on the old token.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isTrue,
          reason: 'H9: DB connection state untouched on validation failure');
      expect(row.systemId, 'sys-X');
      expect(service.state.isConnected, isTrue);
      expect(service.state.syncError, contains('Invalid token'));
    });

    test(
        'transient network error during rotation: old token + connection '
        'state untouched', () async {
      final db = _makeDb();
      addTearDown(db.close);

      await _seedRow(
        db,
        systemId: 'sys-X',
        mappingAcknowledged: true,
        directionConfirmed: true,
        linkedAt: t0,
      );
      storageStub._store[pkTokenKey] = 'old-working-token';

      final client = _FakeClient('sys-X')..throwNetworkError = true;
      final service = makeServiceWithClient(db, client);
      await service.loadState();

      await service.setToken('new-token-from-pk');

      expect(
        storageStub._store[pkTokenKey],
        'old-working-token',
        reason:
            'H9: the audit case — a transient failure during rotation '
            'previously DELETED the working token',
      );
      expect(storageStub.writeCount, 0);
      expect(storageStub.deleteCount, 0);

      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isTrue);
      expect(service.state.isConnected, isTrue);
      expect(service.state.syncError, contains('Connection failed'));
    });

    test(
        'secure-storage write failure after successful validation: error '
        'surfaced, prior token intact, DB not flipped', () async {
      final db = _makeDb();
      addTearDown(db.close);

      await _seedRow(
        db,
        systemId: 'sys-X',
        mappingAcknowledged: true,
        directionConfirmed: true,
        linkedAt: t0,
      );
      storageStub._store[pkTokenKey] = 'old-working-token';
      storageStub.throwOnWrite = true;

      // Validation SUCCEEDS (client healthy); only the persist step fails.
      final client = _FakeClient('sys-X');
      final service = makeServiceWithClient(db, client);
      await service.loadState();

      await service.setToken('new-token');

      // safeSecureWrite failure semantics: the write threw before storing,
      // so the previously stored token was not overwritten.
      expect(storageStub.writeCount, greaterThan(0),
          reason: 'the write was attempted (validation passed)');
      expect(storageStub._store[pkTokenKey], 'old-working-token');

      // The DB row keeps its prior shape — setToken returned before the
      // upsert. In particular linkedAt was not re-stamped.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isTrue);
      expect(
        row.linkedAt?.millisecondsSinceEpoch,
        t0.millisecondsSinceEpoch,
      );
      expect(service.state.syncError, contains('save the token'));
    });

    test(
        'secure-storage write failure on a FRESH device: DB must not claim '
        'connected while storage is empty', () async {
      final db = _makeDb();
      addTearDown(db.close);

      storageStub.throwOnWrite = true;
      final client = _FakeClient('sys-Z');
      final service = makeServiceWithClient(db, client);

      await service.setToken('first-token');

      // The H9 divergence: DB says connected + storage empty = auto-poll
      // skips forever while the UI shows connected. Both must stay "not
      // connected" here.
      expect(storageStub._store.containsKey(pkTokenKey), isFalse);
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isFalse);
      expect(service.state.isConnected, isFalse);
      expect(service.state.syncError, contains('save the token'));
    });
  });

  // ---------------------------------------------------------------------------
  // M4: a different-system swap must null the switch cursor
  // and lastSyncDate (parity with clearToken). Otherwise the OLD system's
  // cursor `covers()` the NEW system's history: if the user dismisses the
  // mapping flow, the new system's switches are
  // silently never imported.
  // ---------------------------------------------------------------------------

  group('M4: setToken system swap resets the switch cursor', () {
    final t0 = DateTime(2024, 1, 1, 12).toUtc();
    final cursorTs = DateTime(2024, 6, 1, 9).toUtc();
    final lastSync = DateTime(2024, 6, 2, 10).toUtc();

    Future<void> seedConnectedWithCursor(AppDatabase db) async {
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          systemId: const Value('sys-X'),
          isConnected: const Value(true),
          mappingAcknowledged: const Value(true),
          directionConfirmed: const Value(true),
          linkedAt: Value(t0),
          switchCursorTimestamp: Value(cursorTs),
          switchCursorId: const Value('sw-cursor-old'),
          lastSyncDate: Value(lastSync),
        ),
      );
    }

    test('different-system swap nulls cursor + lastSyncDate', () async {
      final db = _makeDb();
      addTearDown(db.close);
      await seedConnectedWithCursor(db);

      final service = _makeService(db, 'sys-Y');
      await service.setToken('new-token');

      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.systemId, 'sys-Y');
      expect(
        row.switchCursorTimestamp,
        isNull,
        reason:
            'M4: the old system\'s cursor would cover() the new system\'s '
            'history and silently skip its import',
      );
      expect(row.switchCursorId, isNull);
      expect(row.lastSyncDate, isNull,
          reason:
              'M4: a retained lastSyncDate sends the next sync down the '
              'incremental branch instead of the first-sync full import');
    });

    test('same-system token rotation preserves cursor + lastSyncDate',
        () async {
      final db = _makeDb();
      addTearDown(db.close);
      await seedConnectedWithCursor(db);

      final service = _makeService(db, 'sys-X');
      await service.setToken('rotated-token');

      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.systemId, 'sys-X');
      expect(
        row.switchCursorTimestamp?.millisecondsSinceEpoch,
        cursorTs.millisecondsSinceEpoch,
        reason: 'rotation is not a remap — the incremental sweep must resume',
      );
      expect(row.switchCursorId, 'sw-cursor-old');
      expect(
        row.lastSyncDate?.millisecondsSinceEpoch,
        lastSync.millisecondsSinceEpoch,
      );
    });
  });
}

/// In-memory member repo used only by the re-push test below. The file's main
/// `_FakeMemberRepository` returns empty for everything, which would break the
/// applier's `getMemberById` lookup.
class _RepushMemberRepo implements MemberRepository {
  _RepushMemberRepo(Iterable<domain.Member> seed) {
    for (final m in seed) {
      _byId[m.id] = m;
    }
  }
  final Map<String, domain.Member> _byId = {};

  @override
  Future<List<domain.Member>> getAllMembers() async => _byId.values.toList();
  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _byId.values.toList();
  @override
  Future<domain.Member?> getMemberById(String id) async => _byId[id];
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _byId[id]).whereType<domain.Member>().toList();
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(const []);
  @override
  Future<void> createMember(domain.Member member) async {
    _byId[member.id] = member;
  }

  @override
  Future<void> updateMember(domain.Member member) async {
    _byId[member.id] = member;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 0;
  @override
  Future<int> applyPluralKitLink(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(
      pluralkitUuid: patch.containsKey('pluralkit_uuid')
          ? patch['pluralkit_uuid'] as String?
          : existing.pluralkitUuid,
      pluralkitId: patch.containsKey('pluralkit_id')
          ? patch['pluralkit_id'] as String?
          : existing.pluralkitId,
      pluralkitDisplayName: patch.containsKey('pluralkit_display_name')
          ? patch['pluralkit_display_name'] as String?
          : existing.pluralkitDisplayName,
      pluralkitSyncIgnored: false,
    );
    return 1;
  }
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(
      pluralkitUuid: patch.containsKey('pluralkit_uuid')
          ? patch['pluralkit_uuid'] as String?
          : existing.pluralkitUuid,
      pluralkitId: patch.containsKey('pluralkit_id')
          ? patch['pluralkit_id'] as String?
          : existing.pluralkitId,
      pluralkitDisplayName: patch.containsKey('pluralkit_display_name')
          ? patch['pluralkit_display_name'] as String?
          : existing.pluralkitDisplayName,
    );
    return 1;
  }
  @override
  Future<int> excludePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: true);
    return 1;
  }
  @override
  Future<int> resumePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: false);
    return 1;
  }
  @override
  Future<void> deleteMember(String id) async {
    _byId.remove(id);
  }

  @override
  Stream<List<domain.Member>> watchAllMembers() => Stream.value(const []);
  @override
  Stream<List<domain.Member>> watchActiveMembers() => Stream.value(const []);
  @override
  Stream<domain.Member?> watchMemberById(String id) => Stream.value(_byId[id]);
  @override
  Future<int> getCount() async => _byId.length;
  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> clearCreatePushStartedAt(String id) async {}
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}
