import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqlExtendedError, SqliteException;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_import_source.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_switch_cursor.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Secure storage stub (copied verbatim from biometric_service_test.dart)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};
  bool throwOnRead = false;
  int readCount = 0;
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
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                _store[key] = value;
                return null;
              case 'read':
                readCount++;
                if (throwOnRead) throw PlatformException(code: 'AuthError');
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
    throwOnRead = false;
    readCount = 0;
    writeCount = 0;
    deleteCount = 0;
  }
}

// ---------------------------------------------------------------------------
// Fake PluralKitClient
// ---------------------------------------------------------------------------

class FakePluralKitClient implements PluralKitClient {
  int getSystemCallCount = 0;
  int getSwitchesCallCount = 0;
  int getMembersCallCount = 0;
  int getGroupsCallCount = 0;
  int disposeCallCount = 0;
  final List<String> calls = [];

  @override
  String get currentToken => 'fake-token';

  // Configurable behavior
  bool throwAuthError = false;
  bool throwNetworkError = false;

  PKSystem systemToReturn = const PKSystem(id: 'sys-1', name: 'Test System');
  List<PKMember> membersToReturn = const [];
  List<PKGroup> groupsToReturn = const [];
  List<PKSwitch> switchesToReturn = const [];

  /// When set, each getSwitches call pops the first list from this queue.
  /// Useful for pagination tests. When empty, falls back to [switchesToReturn].
  List<List<PKSwitch>>? switchesPageQueue;

  @override
  Future<PKSystem> getSystem() async {
    calls.add('getSystem');
    getSystemCallCount++;
    if (throwAuthError) throw const PluralKitAuthError();
    if (throwNetworkError) throw Exception('Network unreachable');
    return systemToReturn;
  }

  @override
  Future<List<PKMember>> getMembers() async {
    calls.add('getMembers');
    getMembersCallCount++;
    return membersToReturn;
  }

  @override
  Future<PKMember> getMember(String memberRef) async {
    calls.add('getMember');
    return membersToReturn.firstWhere(
      (member) => member.id == memberRef || member.uuid == memberRef,
    );
  }

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    calls.add('getSwitches');
    getSwitchesCallCount++;
    if (switchesPageQueue != null && switchesPageQueue!.isNotEmpty) {
      return switchesPageQueue!.removeAt(0);
    }
    return switchesToReturn;
  }

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  final List<({List<String> memberIds, DateTime? timestamp})>
  createSwitchCalls = [];
  String Function(List<String> memberIds)? createSwitchIdGenerator;

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    calls.add('createSwitch');
    createSwitchCalls.add((memberIds: memberIds, timestamp: timestamp));
    final id =
        createSwitchIdGenerator?.call(memberIds) ??
        'sw-${createSwitchCalls.length}';
    return PKSwitch(
      id: id,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      members: memberIds,
    );
  }

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    calls.add('getGroups');
    getGroupsCallCount++;
    return groupsToReturn;
  }

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();

  PKSwitch? currentFrontersToReturn;
  int getCurrentFrontersCallCount = 0;

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    calls.add('getCurrentFronters');
    getCurrentFrontersCallCount++;
    return currentFrontersToReturn;
  }

  @override
  void dispose() {
    disposeCallCount++;
  }
}

// ---------------------------------------------------------------------------
// Fake MemberRepository
// ---------------------------------------------------------------------------

class FakeMemberRepository implements MemberRepository {
  final Map<String, domain.Member> _members = {};

  void seed(List<domain.Member> members) {
    for (final m in members) {
      _members[m.id] = m;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async => _members.values.toList();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _members.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _members[id];

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _members[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> createMember(domain.Member member) async {
    _members[member.id] = member;
  }

  @override
  Future<void> updateMember(domain.Member member) async {
    _members[member.id] = member;
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.remove(id);
  }

  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();

  @override
  Future<int> getCount() async => _members.length;

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Fake FrontingSessionRepository
// ---------------------------------------------------------------------------

class FakeFrontingSessionRepository implements FrontingSessionRepository {
  final List<domain.FrontingSession> sessions = [];
  final List<domain.FrontingSession> deletedLinkedSessions = [];

  @override
  Future<List<domain.FrontingSession>> getAllSessions() async =>
      List.unmodifiable(sessions);

  @override
  Future<void> createSession(domain.FrontingSession session) async {
    sessions.add(session);
  }

  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async =>
      sessions.where((s) => s.isActive && !s.isSleep).toList();

  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async =>
      sessions.where((s) => !s.isSleep).toList();

  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      sessions.where((s) => s.isActive).toList();

  @override
  Future<domain.FrontingSession?> getActiveSession() async => sessions
      .cast<domain.FrontingSession?>()
      .firstWhere((s) => s!.isActive, orElse: () => null);

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async => sessions
      .cast<domain.FrontingSession?>()
      .firstWhere((s) => s!.id == id, orElse: () => null);

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
    String memberId,
  ) async => sessions.where((s) => s.memberId == memberId).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({
    int limit = 20,
  }) async => sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async => sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async => sessions
      .where((s) => !s.startTime.isBefore(start) && !s.startTime.isAfter(end))
      .toList();

  @override
  Future<void> updateSession(domain.FrontingSession session) async {
    final uuid = session.pluralkitUuid?.trim();
    if (uuid != null && uuid.isNotEmpty && session.memberId != null) {
      final collides = sessions.any(
        (s) =>
            s.id != session.id &&
            s.memberId == session.memberId &&
            s.pluralkitUuid == uuid,
      );
      if (collides) {
        throw SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
          message: 'UNIQUE constraint failed',
        );
      }
    }
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) sessions[idx] = session;
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    final idx = sessions.indexWhere((s) => s.id == id);
    if (idx >= 0) sessions[idx] = sessions[idx].copyWith(endTime: endTime);
  }

  @override
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
  }

  @override
  Stream<List<domain.FrontingSession>> watchAllSessions() =>
      throw UnimplementedError();

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
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(sessions.take(limit).toList());

  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) => Stream.value(sessions.take(limit).toList());

  @override
  Stream<List<domain.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) {
    final overlapping = sessions.where((s) {
      if (!s.startTime.isBefore(end)) return false;
      final endTime = s.endTime;
      if (endTime == null) return true;
      return endTime.isAfter(start);
    }).toList();
    return Stream.value(overlapping);
  }

  @override
  Future<int> getCount() async => sessions.length;

  @override
  Future<int> getFrontingCount() async =>
      sessions.where((s) => !s.isSleep).length;

  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) async => {};

  @override
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions() async =>
      List.unmodifiable(deletedLinkedSessions);
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) async => (count: 0, avgDuration: null);

  @override
  Stream<List<domain.FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) => Stream.value(const []);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

const _pkTokenKey = 'prism_pluralkit_token';

/// Build a service under test. [fakeClient] is returned by the factory for
/// every token. The [storageStub] method channel must already be set up.
PluralKitSyncService _makeService({
  required FakePluralKitClient fakeClient,
  required AppDatabase db,
  FakeMemberRepository? memberRepo,
  FakeFrontingSessionRepository? sessionRepo,
  PluralKitClient Function(String token)? clientFactory,
}) {
  return PluralKitSyncService(
    memberRepository: memberRepo ?? FakeMemberRepository(),
    frontingSessionRepository: sessionRepo ?? FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    clientFactory: clientFactory ?? (_) => fakeClient,
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

  // PR D / WS3 cursor + pagination guard tests live in their own group with
  // their own setUp/tearDown so the secure-storage stub doesn't double-attach.
  _registerWs3PrDTests();

  group('PluralKit switch UUID guard', () {
    test('accepts only UUID-shaped switch refs', () {
      expect(
        isPluralKitSwitchUuid('00000000-0000-0000-0000-000000000001'),
        isTrue,
      );
      expect(
        isPluralKitSwitchUuid('ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB'),
        isTrue,
      );
      expect(isPluralKitSwitchUuid(null), isFalse);
      expect(isPluralKitSwitchUuid(''), isFalse);
      expect(isPluralKitSwitchUuid('pkfile:v1:abc'), isFalse);
      expect(isPluralKitSwitchUuid('uuid-s1'), isFalse);
    });
  });

  // ── setToken ────────────────────────────────────────────────────────────────

  group('setToken', () {
    test('valid token: isConnected = true, token written to storage', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      await service.setToken('valid-token');

      expect(service.state.isConnected, isTrue);
      expect(service.state.syncError, isNull);
      expect(storageStub._store[_pkTokenKey], 'valid-token');
      // Fresh connection gates auto-sync until mapping completes.
      expect(service.state.needsMapping, isTrue);
      expect(service.state.canAutoSync, isFalse);
    });

    test(
      'acknowledgeMapping clears needsMapping and unlocks auto-sync',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient();
        final service = _makeService(fakeClient: fakeClient, db: db);

        await service.setToken('valid-token');
        expect(service.state.canAutoSync, isFalse);

        await service.acknowledgeMapping();
        expect(service.state.needsMapping, isFalse);
        expect(service.state.canAutoSync, isTrue);

        // Survives reload.
        final reloaded = _makeService(fakeClient: fakeClient, db: db);
        await reloaded.loadState();
        expect(reloaded.state.needsMapping, isFalse);
        expect(reloaded.state.canAutoSync, isTrue);
      },
    );

    test('buildClientIfConnected returns null while mapping pending', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      await service.setToken('valid-token');
      expect(await service.buildClientIfConnected(), isNull);

      // But the mapping-aware path still gives a client.
      expect(await service.buildClientIgnoringMappingGate(), isNotNull);

      await service.acknowledgeMapping();
      expect(await service.buildClientIfConnected(), isNotNull);
    });

    test(
      '401 from getSystem: isConnected = false, token deleted from storage',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient()..throwAuthError = true;
        final service = _makeService(fakeClient: fakeClient, db: db);

        await service.setToken('bad-token');

        expect(service.state.isConnected, isFalse);
        expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
        expect(service.state.syncError, isNotNull);
      },
    );

    test(
      'network error from getSystem: isConnected = false, token deleted',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient()..throwNetworkError = true;
        final service = _makeService(fakeClient: fakeClient, db: db);

        await service.setToken('some-token');

        expect(service.state.isConnected, isFalse);
        expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
        expect(service.state.syncError, isNotNull);
      },
    );
  });

  // ── clearToken ───────────────────────────────────────────────────────────────

  group('clearToken', () {
    test(
      'resets state: isConnected = false, token gone, lastSyncDate = null',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient();
        final service = _makeService(fakeClient: fakeClient, db: db);

        // First connect
        await service.setToken('valid-token');
        expect(service.state.isConnected, isTrue);

        // Now clear
        await service.clearToken();

        expect(service.state.isConnected, isFalse);
        expect(service.state.lastSyncDate, isNull);
        expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
      },
    );

    test(
      'truncates pk_mapping_state + resets needsMapping (regression B3)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient();
        final service = _makeService(fakeClient: fakeClient, db: db);

        // Seed a mapping-state row — simulates a prior Skip decision the user
        // made against the previously-connected PK system.
        await db.pkMappingStateDao.upsert(
          PkMappingStateCompanion(
            id: const Value('local-123:pk-abc'),
            localMemberId: const Value('local-123'),
            pkMemberUuid: const Value('pk-abc'),
            pkMemberId: const Value('abc'),
            decisionType: const Value('skip'),
            status: const Value('applied'),
            createdAt: Value(DateTime(2026, 1, 1)),
            updatedAt: Value(DateTime(2026, 1, 1)),
          ),
        );

        await service.setToken('valid-token');
        expect(service.state.needsMapping, isTrue);

        // Precondition — row exists.
        final before = await db.pkMappingStateDao.getAll();
        expect(before, hasLength(1));

        await service.clearToken();

        // Mapping table is wiped so a future reconnect starts clean.
        final after = await db.pkMappingStateDao.getAll();
        expect(
          after,
          isEmpty,
          reason: 'clearToken must truncate pk_mapping_state (B3)',
        );

        // needsMapping / mappingAcknowledged are reset so a reconnect will
        // trigger the mapping flow again rather than silently inheriting
        // the prior acknowledgement.
        expect(service.state.needsMapping, isFalse);
        final row = await db.pluralKitSyncDao.getSyncState();
        expect(row.mappingAcknowledged, isFalse);
      },
    );
  });

  // ── _buildClient / token guards ──────────────────────────────────────────────

  group('buildClientIfConnected token guards', () {
    test('null in storage: returns null when isConnected = false', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);
      // isConnected defaults to false, nothing in storage

      final client = await service.buildClientIfConnected();
      expect(client, isNull);
    });

    test('empty string in storage: returns null (whitespace check)', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      // Manually seed empty string — bypasses setToken validation
      storageStub._store[_pkTokenKey] = '';

      // Force isConnected to true so buildClientIfConnected proceeds to _buildClient
      // We do this by having a valid getSystem succeed first then manually corrupt token
      // Instead, seed the DAO with isConnected=true and call loadState
      await db.pluralKitSyncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          isConnected: Value(true),
        ),
      );
      await service.loadState();

      final client = await service.buildClientIfConnected();
      expect(client, isNull);
    });

    test('whitespace-only string in storage: returns null', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      storageStub._store[_pkTokenKey] = '   ';

      await db.pluralKitSyncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          isConnected: Value(true),
        ),
      );
      await service.loadState();

      final client = await service.buildClientIfConnected();
      expect(client, isNull);
    });
  });

  group('pollFrontersOnly', () {
    test(
      'pulls only the live switch on a fresh connection instead of full importing',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        const switchId = '00000000-0000-0000-0000-0000000000bb';
        final switchTimestamp = DateTime.utc(2026, 5, 1, 12);
        final memberRepo = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-member-id',
              name: 'Local member',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: 'pk001',
              pluralkitUuid: 'uuid-pk001',
            ),
          ]);
        final sessionRepo = FakeFrontingSessionRepository();
        final fakeClient = FakePluralKitClient()
          ..currentFrontersToReturn = PKSwitch(
            id: switchId,
            timestamp: switchTimestamp,
            members: const ['pk001'],
          )
          ..membersToReturn = const [
            PKMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Remote member'),
          ]
          ..switchesToReturn = [
            PKSwitch(
              id: switchId,
              timestamp: switchTimestamp,
              members: const ['pk001'],
            ),
          ];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        expect(service.state.lastSyncDate, isNull);

        final pulled = await service.pollFrontersOnly();

        expect(pulled, isTrue);
        expect(
          fakeClient.getSwitchesCallCount,
          0,
          reason: 'Foreground polling must not fall into full import.',
        );
        expect(sessionRepo.sessions, hasLength(1));
        expect(sessionRepo.sessions.single.pluralkitUuid, switchId);
      },
    );

    test(
      'does not full-sync when current PK switch is a user tombstone already covered by cursor',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        const switchId = '00000000-0000-0000-0000-0000000000aa';
        final switchTimestamp = DateTime.utc(2026, 5, 1, 12);

        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            isConnected: const Value(true),
            mappingAcknowledged: const Value(true),
            lastSyncDate: Value(switchTimestamp),
            switchCursorTimestamp: Value(switchTimestamp),
            switchCursorId: const Value(switchId),
          ),
        );

        await db.frontingSessionsDao.insertSession(
          FrontingSessionsCompanion.insert(
            id: 'deleted-current-switch-row',
            startTime: switchTimestamp,
            memberId: const Value('local-member-id'),
            pluralkitUuid: const Value(switchId),
            isDeleted: const Value(true),
            deleteIntentEpoch: const Value(0),
          ),
        );

        final fakeClient = FakePluralKitClient()
          ..currentFrontersToReturn = PKSwitch(
            id: switchId,
            timestamp: switchTimestamp,
            members: const ['pk001'],
          )
          ..switchesToReturn = [
            PKSwitch(
              id: switchId,
              timestamp: switchTimestamp,
              members: const ['pk001'],
            ),
          ];

        final service = PluralKitSyncService(
          memberRepository: DriftMemberRepository(
            db.membersDao,
            null,
            pkSyncDao: db.pluralKitSyncDao,
          ),
          frontingSessionRepository: DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
            pkSyncDao: db.pluralKitSyncDao,
          ),
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          tokenOverride: 'test-token',
          clientFactory: (_) => fakeClient,
        );
        await service.loadState();

        final ranFullSync = await service.pollFrontersOnly();

        expect(ranFullSync, isFalse);
        expect(
          fakeClient.getSwitchesCallCount,
          0,
          reason: 'The tombstone means this current switch is already known.',
        );
      },
    );
  });

  group('syncLiveFrontersOnly', () {
    domain.Member member(String id, String pkId, String pkUuid) =>
        domain.Member(
          id: id,
          name: id,
          emoji: '❔',
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitId: pkId,
          pluralkitUuid: pkUuid,
        );

    domain.FrontingSession session(
      String id,
      String? memberId, {
      required DateTime startTime,
      String? pluralkitUuid,
      bool isDeleted = false,
      int? deleteIntentEpoch,
    }) => domain.FrontingSession(
      id: id,
      startTime: startTime,
      memberId: memberId,
      pluralkitUuid: pluralkitUuid,
      isDeleted: isDeleted,
      deleteIntentEpoch: deleteIntentEpoch,
    );

    PKSwitch currentSwitch(
      String id,
      DateTime timestamp,
      List<String> members, {
      List<PKMemberSummary> memberDetails = const [],
    }) => PKSwitch(
      id: id,
      timestamp: timestamp,
      members: members,
      memberDetails: memberDetails,
    );

    Future<
      ({
        PluralKitSyncService service,
        FakePluralKitClient client,
        FakeFrontingSessionRepository sessionRepo,
        AppDatabase db,
      })
    >
    setupLive({
      required List<domain.Member> members,
      List<domain.FrontingSession> sessions = const [],
      List<domain.FrontingSession> deletedLinkedSessions = const [],
      PKSwitch? current,
    }) async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = FakeMemberRepository()..seed(members);
      final sessionRepo = FakeFrontingSessionRepository()
        ..sessions.addAll(sessions)
        ..deletedLinkedSessions.addAll(deletedLinkedSessions);
      final fakeClient = FakePluralKitClient()
        ..currentFrontersToReturn = current;
      final service = _makeService(
        fakeClient: fakeClient,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );

      await service.setToken('valid-token');
      await service.acknowledgeMapping();
      await service.loadState();

      fakeClient.calls.clear();
      fakeClient.getSystemCallCount = 0;
      fakeClient.getSwitchesCallCount = 0;
      fakeClient.getMembersCallCount = 0;
      fakeClient.getGroupsCallCount = 0;
      fakeClient.getCurrentFrontersCallCount = 0;
      fakeClient.createSwitchCalls.clear();
      return (
        service: service,
        client: fakeClient,
        sessionRepo: sessionRepo,
        db: db,
      );
    }

    test(
      'unseen current creates current-front rows without history or profile fetches',
      () async {
        final ts = DateTime.utc(2026, 5, 1, 12);
        const switchId = '00000000-0000-0000-0000-000000000101';
        final harness = await setupLive(
          members: [
            member('local-a', 'pkA', 'uuid-a'),
            member('local-b', 'pkB', 'uuid-b'),
          ],
          current: currentSwitch(switchId, ts, const ['pkA', 'pkB']),
        );

        final summary = await harness.service.syncLiveFrontersOnly(
          direction: PkSyncDirection.pullOnly,
        );

        expect(summary!.switchesPulled, 1);
        expect(summary.switchesPushed, 0);
        expect(harness.sessionRepo.sessions, hasLength(2));
        expect(harness.sessionRepo.sessions.map((s) => s.memberId).toSet(), {
          'local-a',
          'local-b',
        });
        expect(
          harness.sessionRepo.sessions.every(
            (s) => s.pluralkitUuid == switchId && s.endTime == null,
          ),
          isTrue,
        );
        expect(harness.client.getCurrentFrontersCallCount, 1);
        expect(harness.client.getSwitchesCallCount, 0);
        expect(harness.client.getMembersCallCount, 0);
        expect(harness.client.getGroupsCallCount, 0);
      },
    );

    test('does not advance cursor or set lastSyncDate', () async {
      final ts = DateTime.utc(2026, 5, 1, 12);
      final cursorTs = DateTime.utc(2026, 4, 1, 12);
      final harness = await setupLive(
        members: [member('local-a', 'pkA', 'uuid-a')],
        current: currentSwitch(
          '00000000-0000-0000-0000-000000000102',
          ts,
          const ['pkA'],
        ),
      );
      await harness.db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: const Value(null),
          lastManualSyncDate: const Value(null),
          switchCursorTimestamp: Value(cursorTs),
          switchCursorId: const Value('existing-cursor'),
        ),
      );
      await harness.service.loadState();

      await harness.service.syncLiveFrontersOnly(
        direction: PkSyncDirection.pullOnly,
        isManual: true,
      );

      final row = await harness.db.pluralKitSyncDao.getSyncState();
      expect(row.switchCursorTimestamp?.toUtc(), cursorTs);
      expect(row.switchCursorId, 'existing-cursor');
      expect(row.lastSyncDate, isNull);
      expect(row.lastManualSyncDate, isNotNull);
      expect(harness.service.state.lastSyncDate, isNull);
      expect(harness.service.state.lastManualSyncDate, isNotNull);
    });

    test('existing live current no-ops', () async {
      final ts = DateTime.utc(2026, 5, 1, 12);
      const switchId = '00000000-0000-0000-0000-000000000103';
      final harness = await setupLive(
        members: [member('local-a', 'pkA', 'uuid-a')],
        sessions: [
          session(
            'existing-row',
            'local-a',
            startTime: ts,
            pluralkitUuid: switchId,
          ),
        ],
        current: currentSwitch(switchId, ts, const ['pkA']),
      );

      final summary = await harness.service.syncLiveFrontersOnly(
        direction: PkSyncDirection.pullOnly,
      );

      expect(summary!.switchesPulled, 0);
      expect(harness.sessionRepo.sessions, hasLength(1));
      expect(harness.sessionRepo.sessions.single.id, 'existing-row');
      expect(harness.client.getSwitchesCallCount, 0);
    });

    test('deleted current tombstone no-ops', () async {
      final ts = DateTime.utc(2026, 5, 1, 12);
      const switchId = '00000000-0000-0000-0000-000000000104';
      final deleted = session(
        'deleted-row',
        'local-a',
        startTime: ts,
        pluralkitUuid: switchId,
        isDeleted: true,
        deleteIntentEpoch: 1,
      );
      final harness = await setupLive(
        members: [member('local-a', 'pkA', 'uuid-a')],
        deletedLinkedSessions: [deleted],
        current: currentSwitch(switchId, ts, const ['pkA']),
      );

      final summary = await harness.service.syncLiveFrontersOnly(
        direction: PkSyncDirection.pullOnly,
      );

      expect(summary!.switchesPulled, 0);
      expect(harness.sessionRepo.sessions, isEmpty);
      expect(harness.client.getSwitchesCallCount, 0);
    });

    test(
      'mapped plus unmapped current skips whole switch with notice',
      () async {
        final ts = DateTime.utc(2026, 5, 1, 12);
        final harness = await setupLive(
          members: [member('local-a', 'pkA', 'uuid-a')],
          current: currentSwitch(
            '00000000-0000-0000-0000-000000000105',
            ts,
            const ['pkA', 'pkMissing'],
            memberDetails: const [
              PKMemberSummary(
                id: 'pkMissing',
                uuid: 'uuid-missing',
                name: 'Missing',
                displayName: 'Missing Display',
                avatarUrl: 'https://example.test/missing.png',
              ),
            ],
          ),
        );

        final summary = await harness.service.syncLiveFrontersOnly(
          direction: PkSyncDirection.pullOnly,
        );

        expect(summary!.switchesPulled, 0);
        expect(summary.staleLinkMessages, isEmpty);
        expect(summary.observedLiveFronters, isTrue);
        expect(summary.observedLiveFrontersDismissalKey, isNotEmpty);
        final notice = summary.liveUnmappedFronters;
        expect(notice, isNotNull);
        expect(notice!.systemId, 'sys-1');
        expect(notice.switchId, '00000000-0000-0000-0000-000000000105');
        expect(notice.sortedPkIds, ['pkA', 'pkMissing']);
        expect(notice.refs.single.pkId, 'pkMissing');
        expect(notice.refs.single.pkUuid, 'uuid-missing');
        expect(notice.refs.single.displayName, 'Missing Display');
        expect(
          notice.refs.single.avatarUrl,
          'https://example.test/missing.png',
        );
        expect(harness.service.state.syncStatus, contains('Review current'));
        expect(harness.service.state.syncError, isNull);
        expect(harness.sessionRepo.sessions, isEmpty);
      },
    );

    test(
      'pushOnly creates switch without fetching history/profile/group',
      () async {
        final harness = await setupLive(
          members: [member('local-a', 'pkA', 'uuid-a')],
          sessions: [
            session(
              'local-active',
              'local-a',
              startTime: DateTime.utc(2026, 5, 1, 12),
            ),
          ],
        );

        final summary = await harness.service.syncLiveFrontersOnly(
          direction: PkSyncDirection.pushOnly,
        );

        expect(summary!.switchesPulled, 0);
        expect(summary.switchesPushed, 1);
        expect(harness.client.createSwitchCalls, hasLength(1));
        expect(harness.client.createSwitchCalls.single.memberIds, ['pkA']);
        expect(
          harness.client.getCurrentFrontersCallCount,
          1,
          reason:
              'push reconciliation checks PK current state to avoid duplicates',
        );
        expect(harness.client.getSwitchesCallCount, 0);
        expect(harness.client.getMembersCallCount, 0);
        expect(harness.client.getGroupsCallCount, 0);
      },
    );

    test(
      'pushOnly stale link skips member refresh and reports stale summary',
      () async {
        final harness = await setupLive(
          members: [member('local-a', 'pkA', 'uuid-a')],
          sessions: [
            session(
              'local-active',
              'local-a',
              startTime: DateTime.utc(2026, 5, 1, 12),
            ),
          ],
        );
        harness.client.createSwitchIdGenerator = (_) {
          throw const PluralKitApiError(404, 'stale member');
        };

        final summary = await harness.service.syncLiveFrontersOnly(
          direction: PkSyncDirection.pushOnly,
        );

        expect(summary!.switchesPushed, 0);
        expect(summary.staleLinkMessages, isNotEmpty);
        expect(harness.client.getCurrentFrontersCallCount, 1);
        expect(harness.client.getSwitchesCallCount, 0);
        expect(
          harness.client.getMembersCallCount,
          0,
          reason: 'live-front-only sync must not refresh PK member profiles',
        );
        expect(harness.client.getGroupsCallCount, 0);
      },
    );

    test(
      'bidirectional pulls current before pushing differing local state',
      () async {
        final ts = DateTime.utc(2026, 5, 1, 12);
        final harness = await setupLive(
          members: [
            member('local-a', 'pkA', 'uuid-a'),
            member('local-b', 'pkB', 'uuid-b'),
          ],
          sessions: [
            session(
              'local-b-active',
              'local-b',
              startTime: DateTime.utc(2026, 5, 1, 11),
            ),
          ],
          current: currentSwitch(
            '00000000-0000-0000-0000-000000000107',
            ts,
            const ['pkA'],
          ),
        );

        final summary = await harness.service.syncLiveFrontersOnly(
          direction: PkSyncDirection.bidirectional,
        );

        expect(summary!.switchesPulled, 1);
        expect(summary.switchesPushed, 1);
        expect(harness.client.createSwitchCalls.single.memberIds, [
          'pkA',
          'pkB',
        ]);
        expect(harness.client.getCurrentFrontersCallCount, 1);
        expect(harness.client.calls, ['getCurrentFronters', 'createSwitch']);
      },
    );
  });

  group('repair reference fetch', () {
    test(
      'hasRepairToken reports stored and provided token availability',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final fakeClient = FakePluralKitClient();
        final service = _makeService(fakeClient: fakeClient, db: db);

        expect(await service.hasRepairToken(), isFalse);
        expect(
          await service.hasRepairToken(token: '  provided-token  '),
          isTrue,
        );
        expect(await service.hasRepairToken(token: '   '), isFalse);

        storageStub._store[_pkTokenKey] = 'stored-token';
        expect(await service.hasRepairToken(), isTrue);
      },
    );

    test(
      'fetchRepairReferenceData uses stored token and does not mutate storage or sync state',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        storageStub._store[_pkTokenKey] = 'stored-token';

        final fakeClient = FakePluralKitClient()
          ..systemToReturn = const PKSystem(
            id: 'sys-repair',
            name: 'Repair System',
          )
          ..membersToReturn = const [
            PKMember(id: 'pk001', uuid: 'member-uuid-1', name: 'Alice'),
          ]
          ..groupsToReturn = const [
            PKGroup(
              id: 'grp01',
              uuid: 'group-uuid-1',
              name: 'Cluster',
              memberIds: ['member-uuid-1'],
            ),
          ];
        final service = _makeService(fakeClient: fakeClient, db: db);

        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            systemId: const Value('persisted-system'),
            isConnected: const Value(true),
            mappingAcknowledged: const Value(false),
            lastSyncDate: Value(DateTime(2026, 2, 1)),
            lastManualSyncDate: Value(DateTime(2026, 2, 2)),
            linkedAt: Value(DateTime(2026, 1, 31)),
            linkEpoch: const Value(7),
          ),
        );
        await service.loadState();

        final beforeRow = await db.pluralKitSyncDao.getSyncState();
        final beforeReadCount = storageStub.readCount;
        final beforeWriteCount = storageStub.writeCount;
        final beforeDeleteCount = storageStub.deleteCount;
        final beforeConnected = service.state.isConnected;
        final beforeNeedsMapping = service.state.needsMapping;
        final beforeLastSyncDate = service.state.lastSyncDate;
        final beforeLastManualSyncDate = service.state.lastManualSyncDate;
        final beforeLinkedAt = service.state.linkedAt;
        final beforeSyncError = service.state.syncError;

        final data = await service.fetchRepairReferenceData();

        expect(data.system.id, 'sys-repair');
        expect(data.system.name, 'Repair System');
        expect(data.members.map((m) => m.uuid), ['member-uuid-1']);
        expect(data.groups.map((g) => g.uuid), ['group-uuid-1']);
        expect(data.groups.single.memberIds, ['member-uuid-1']);
        expect(fakeClient.getSystemCallCount, 1);
        expect(fakeClient.getMembersCallCount, 1);
        expect(fakeClient.getGroupsCallCount, 1);
        expect(fakeClient.disposeCallCount, 1);

        expect(storageStub._store[_pkTokenKey], 'stored-token');
        expect(storageStub.readCount, beforeReadCount + 1);
        expect(storageStub.writeCount, beforeWriteCount);
        expect(storageStub.deleteCount, beforeDeleteCount);

        final afterRow = await db.pluralKitSyncDao.getSyncState();
        expect(afterRow, equals(beforeRow));
        expect(service.state.isConnected, beforeConnected);
        expect(service.state.needsMapping, beforeNeedsMapping);
        expect(service.state.lastSyncDate, beforeLastSyncDate);
        expect(service.state.lastManualSyncDate, beforeLastManualSyncDate);
        expect(service.state.linkedAt, beforeLinkedAt);
        expect(service.state.syncError, beforeSyncError);
      },
    );

    test(
      'fetchRepairReferenceData accepts provided token without touching stored state',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final createdTokens = <String>[];
        final fakeClient = FakePluralKitClient()..groupsToReturn = const [];
        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          clientFactory: (token) {
            createdTokens.add(token);
            return fakeClient;
          },
        );

        final beforeReadCount = storageStub.readCount;
        final beforeWriteCount = storageStub.writeCount;
        final beforeDeleteCount = storageStub.deleteCount;

        final data = await service.fetchRepairReferenceData(
          token: '  provided-token  ',
        );

        expect(data.system.id, 'sys-1');
        expect(createdTokens, ['provided-token']);
        expect(
          storageStub.readCount,
          beforeReadCount,
          reason: 'provided repair token should bypass secure storage',
        );
        expect(storageStub.writeCount, beforeWriteCount);
        expect(storageStub.deleteCount, beforeDeleteCount);
        expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
        expect(service.state.isConnected, isFalse);
        expect(service.state.needsMapping, isFalse);
      },
    );

    test(
      'repair auth failure does not clear token or mutate connected sync state',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        storageStub._store[_pkTokenKey] = 'bad-token';

        final fakeClient = FakePluralKitClient()..throwAuthError = true;
        final service = _makeService(fakeClient: fakeClient, db: db);

        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            systemId: const Value('persisted-system'),
            isConnected: const Value(true),
            mappingAcknowledged: const Value(true),
            lastSyncDate: Value(DateTime(2026, 2, 1)),
            lastManualSyncDate: Value(DateTime(2026, 2, 2)),
            linkedAt: Value(DateTime(2026, 1, 31)),
            linkEpoch: const Value(4),
          ),
        );
        await service.loadState();

        final beforeRow = await db.pluralKitSyncDao.getSyncState();
        final beforeWriteCount = storageStub.writeCount;
        final beforeDeleteCount = storageStub.deleteCount;
        final beforeConnected = service.state.isConnected;
        final beforeNeedsMapping = service.state.needsMapping;
        final beforeLastSyncDate = service.state.lastSyncDate;
        final beforeLinkedAt = service.state.linkedAt;

        await expectLater(
          service.fetchRepairReferenceData(),
          throwsA(isA<PluralKitAuthError>()),
        );

        expect(storageStub._store[_pkTokenKey], 'bad-token');
        expect(storageStub.writeCount, beforeWriteCount);
        expect(storageStub.deleteCount, beforeDeleteCount);

        final afterRow = await db.pluralKitSyncDao.getSyncState();
        expect(afterRow, equals(beforeRow));
        expect(service.state.isConnected, beforeConnected);
        expect(service.state.needsMapping, beforeNeedsMapping);
        expect(service.state.lastSyncDate, beforeLastSyncDate);
        expect(service.state.linkedAt, beforeLinkedAt);
        expect(fakeClient.disposeCallCount, 1);
      },
    );
  });

  // ── canManualSync ─────────────────────────────────────────────────────────────

  group('canManualSync', () {
    test('null lastManualSyncDate: canManualSync is true', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);
      await service.loadState();

      expect(service.state.canManualSync, isTrue);
    });

    test('lastManualSyncDate 30s ago: canManualSync is false', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      final recentDate = DateTime.now().subtract(const Duration(seconds: 30));
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastManualSyncDate: Value(recentDate),
        ),
      );
      await service.loadState();

      expect(service.state.canManualSync, isFalse);
    });

    test('lastManualSyncDate 90s ago: canManualSync is true', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient();
      final service = _makeService(fakeClient: fakeClient, db: db);

      final oldDate = DateTime.now().subtract(const Duration(seconds: 90));
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastManualSyncDate: Value(oldDate),
        ),
      );
      await service.loadState();

      expect(service.state.canManualSync, isTrue);
    });
  });

  group('performOneTimeFullImport with explicit token', () {
    test('imports data without storing token or enabling sync', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = FakeMemberRepository();
      final fakeClient = FakePluralKitClient()
        ..systemToReturn = const PKSystem(id: 'sys-import', name: 'Import Me')
        ..membersToReturn = const [
          PKMember(id: 'abcde', uuid: 'pk-member-1', name: 'Alice'),
        ]
        ..switchesToReturn = const [];

      final service = _makeService(
        fakeClient: fakeClient,
        db: db,
        memberRepo: memberRepo,
      );

      final result = await service.performOneTimeFullImport(
        token: 'one-shot-token',
      );

      expect(result.system.name, 'Import Me');
      expect(result.members, hasLength(1));
      expect(result.switchesImported, 0);
      expect(memberRepo._members.values.single.pluralkitUuid, 'pk-member-1');
      expect(fakeClient.getSystemCallCount, 1);
      expect(fakeClient.getMembersCallCount, 1);
      expect(fakeClient.getSwitchesCallCount, 1);
      expect(storageStub.writeCount, 0);
      expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
      expect(service.state.isConnected, isFalse);
      expect(service.state.needsMapping, isFalse);
      expect(service.state.canAutoSync, isFalse);

      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.isConnected, isFalse);
      expect(row.mappingAcknowledged, isFalse);
      expect(row.lastSyncDate, isNotNull);
    });
  });

  // ── syncRecentData — null lastSyncDate triggers full import ──────────────────

  group('syncRecentData — null lastSyncDate', () {
    test('full import respects PK-side skip decisions from mapping', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = FakeMemberRepository();
      final frontRepo = FakeFrontingSessionRepository();
      final fakeClient = FakePluralKitClient()
        ..membersToReturn = const [
          PKMember(id: 'skipa', uuid: 'pk-skip', name: 'Skipped'),
          PKMember(id: 'keepa', uuid: 'pk-keep', name: 'Imported'),
        ]
        ..switchesToReturn = const [];
      final service = _makeService(
        fakeClient: fakeClient,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: frontRepo,
      );

      await service.setToken('valid-token');
      await PkMappingStateDao(db).upsert(
        PkMappingStateCompanion(
          id: const Value('skip:pk:pk-skip'),
          decisionType: const Value('skip'),
          pkMemberUuid: const Value('pk-skip'),
          status: const Value('applied'),
          createdAt: Value(DateTime.utc(2026, 1, 1)),
          updatedAt: Value(DateTime.utc(2026, 1, 1)),
        ),
      );
      await service.acknowledgeMapping();

      await service.syncRecentData();

      final members = await memberRepo.getAllMembers();
      expect(members.map((m) => m.pluralkitUuid), ['pk-keep']);
      expect(members.map((m) => m.name), ['Imported']);
    });

    test('pull-capable first sync triggers performFullImport', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient()
        ..membersToReturn = const []
        ..switchesToReturn = const [];

      final service = _makeService(fakeClient: fakeClient, db: db);

      // Connect the service (sets isConnected = true in state and storage)
      await service.setToken('valid-token');
      await service.acknowledgeMapping();
      expect(service.state.isConnected, isTrue);

      // lastSyncDate is null — syncRecentData should branch into performFullImport
      expect(service.state.lastSyncDate, isNull);

      await service.syncRecentData(direction: PkSyncDirection.pullOnly);

      // performFullImport calls getSwitches at least once
      expect(fakeClient.getSwitchesCallCount, greaterThan(0));
    });

    test(
      'push-only first sync does not pull full import data over local fields',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-linked',
              name: 'Local linked',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: 'pk001',
              pluralkitUuid: 'uuid-pk001',
              customColorEnabled: false,
            ),
          ]);
        final fakeClient = FakePluralKitClient()
          ..membersToReturn = const [
            PKMember(
              id: 'pk001',
              uuid: 'uuid-pk001',
              name: 'Remote linked',
              color: 'ff00aa',
            ),
          ]
          ..switchesToReturn = const [];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
        );

        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        expect(service.state.lastSyncDate, isNull);

        final summary = await service.syncRecentData(
          direction: PkSyncDirection.pushOnly,
        );

        final local = (await memberRepo.getAllMembers()).single;
        expect(summary?.membersPulled, 0);
        expect(local.customColorEnabled, isFalse);
        expect(local.customColorHex, isNull);
        expect(
          fakeClient.getSwitchesCallCount,
          0,
          reason: 'Push-only first sync must not call the full import path.',
        );
      },
    );

    test(
      'repairs short-id-only member before resolving switches in same pass',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-half-linked',
              name: 'Alice',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: 'pk001',
            ),
            domain.Member(
              id: 'local-complete',
              name: 'Bob',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: 'pk999',
              pluralkitUuid: 'uuid-pk999',
            ),
          ]);
        final sessionRepo = FakeFrontingSessionRepository();
        const switchId = '00000000-0000-0000-0000-000000000001';
        final fakeClient = FakePluralKitClient()
          ..membersToReturn = const [
            PKMember(id: 'pk001', uuid: 'uuid-pk001', name: 'Alice'),
            PKMember(id: 'pk999', uuid: 'uuid-pk999', name: 'Bob'),
          ]
          ..switchesPageQueue = [
            [
              PKSwitch(
                id: switchId,
                timestamp: DateTime.utc(2026, 2, 1, 12),
                members: ['pk001'],
              ),
            ],
            [],
          ];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1)),
          ),
        );
        await service.loadState();

        await service.syncRecentData(direction: PkSyncDirection.bidirectional);

        final repaired = await memberRepo.getMemberById('local-half-linked');
        expect(repaired!.pluralkitUuid, 'uuid-pk001');
        expect(sessionRepo.sessions, hasLength(1));
        expect(sessionRepo.sessions.single.memberId, 'local-half-linked');
        expect(sessionRepo.sessions.single.pluralkitUuid, switchId);
      },
    );

    test(
      'pull-only incremental sync pulls updated member proxy tags',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-linked',
              name: 'Alice',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: 'pk001',
              pluralkitUuid: 'uuid-pk001',
              proxyTagsJson: '[{"prefix":"OLD:","suffix":null}]',
            ),
          ]);
        final fakeClient = FakePluralKitClient()
          ..membersToReturn = const [
            PKMember(
              id: 'pk001',
              uuid: 'uuid-pk001',
              name: 'Alice',
              proxyTagsJson: '[{"prefix":"NEW:","suffix":null}]',
            ),
          ]
          ..switchesToReturn = const [];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
        );
        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1)),
          ),
        );
        await service.loadState();

        await service.syncRecentData(direction: PkSyncDirection.pullOnly);

        final local = await memberRepo.getMemberById('local-linked');
        expect(fakeClient.getMembersCallCount, 1);
        expect(local!.proxyTagsJson, '[{"prefix":"NEW:","suffix":null}]');
      },
    );
  });

  // ── switch import — empty-member switch skipped ───────────────────────────────

  group('switch import — empty-member switch', () {
    test(
      'switch with members = [] is skipped: no FrontingSession created',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final sessionRepo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();

        // A switch with no members
        final emptySwitch = PKSwitch(
          id: 'sw-empty',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          members: const [],
        );

        final fakeClient = FakePluralKitClient()
          ..membersToReturn = const []
          ..switchesToReturn = [emptySwitch];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        // lastSyncDate null → full import path
        await service.syncRecentData();

        // Switch has no members → primaryMemberId == null → no session created
        expect(sessionRepo.sessions, isEmpty);
      },
    );
  });

  // ── switch dedup — pagination early exit ─────────────────────────────────────

  group('switch dedup — pagination early exit', () {
    test(
      'all switches in first page are duplicates: getSwitches called only once',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final sessionRepo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();

        // Add a member to the repo so switches have a valid mapped member
        final localMember = domain.Member(
          id: 'local-1',
          name: 'Alice',
          emoji: '❔',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
          pluralkitId: 'pk001',
        );
        memberRepo.seed([localMember]);

        // Pre-seed 100 fronting sessions with known pluralkitUuids
        final knownSwitchIds = List.generate(
          100,
          (i) => 'sw-${i.toString().padLeft(3, '0')}',
        );
        for (final switchId in knownSwitchIds) {
          sessionRepo.sessions.add(
            domain.FrontingSession(
              id: 'session-$switchId',
              startTime: DateTime(
                2026,
                1,
                1,
              ).subtract(Duration(minutes: knownSwitchIds.indexOf(switchId))),
              memberId: 'local-1',
              pluralkitUuid: switchId,
            ),
          );
        }

        // Create 100 switches matching the known UUIDs (all duplicates).
        // Use the page queue so the pagination loop terminates after one call:
        // first call returns 100 items (full page), second call returns empty
        // list signalling no more data.
        final duplicateSwitches = knownSwitchIds
            .map(
              (id) => PKSwitch(
                id: id,
                timestamp: DateTime(2026, 1, 1),
                members: const ['pk001'],
              ),
            )
            .toList();

        final fakeClient = FakePluralKitClient()
          ..membersToReturn = const []
          ..switchesPageQueue = [duplicateSwitches, []];

        final service = _makeService(
          fakeClient: fakeClient,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await service.syncRecentData();

        // Processing 100 consecutive duplicates triggers early exit.
        // Pagination: first call returns 100 items (full page so loop continues),
        // second call returns empty (terminates). Then processing sees 100
        // consecutive duplicates and exits early.
        // getSwitches is called exactly twice (once for data, once empty terminator).
        expect(fakeClient.getSwitchesCallCount, equals(2));
      },
    );
  });

  // ── S3: stale-link surfacing into syncError ─────────────────────────────────

  group('syncRecentData stale-link surfacing (regression S3)', () {
    test(
      'pushPendingSwitches 404 populates syncError with user-facing message',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final sessionRepo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();

        // Linked member so the post-linkedAt session is eligible to push.
        memberRepo.seed([
          domain.Member(
            id: 'local-a',
            name: 'Alice',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            pluralkitId: 'pkA',
          ),
        ]);

        final fakeClient = _StaleCreateSwitchClient();

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: sessionRepo,
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => fakeClient,
        );

        await service.setToken('valid-token');
        await service.acknowledgeMapping();

        // Pin linkedAt to a known point and seed a lastSyncDate so syncRecentData
        // hits the recent-changes path (not performFullImport). The session
        // below must start AFTER linkedAt to be push-eligible.
        final linkedAt = DateTime(2026, 1, 15);
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            linkedAt: Value(linkedAt),
            lastSyncDate: Value(DateTime(2026, 1, 20)),
          ),
        );
        await service.loadState();

        // Session created after linkedAt — should be pushed.
        // Explicit `pkImportSourceFileApi` so the source-aware push gate
        // (WS3 step 10) treats this as push-eligible regardless of the
        // null-source adoption cutoff.
        sessionRepo.sessions.add(
          domain.FrontingSession(
            id: 's-new',
            startTime: DateTime(2026, 2, 1, 12),
            memberId: 'local-a',
            pkImportSource: pkImportSourceFileApi,
          ),
        );
        expect(service.state.needsMapping, isFalse);

        final summary = await service.syncRecentData(
          direction: PkSyncDirection.pushOnly,
        );

        // Stale message surfaced via the summary and the state.
        expect(summary, isNotNull);
        expect(summary!.staleLinkMessages, isNotEmpty);
        expect(service.state.syncError, isNotNull);
        expect(service.state.syncError!, contains('server'));
      },
    );
  });

  group('pushPendingSwitches snapshot push', () {
    domain.Member member(String id, String? pkId) => domain.Member(
      id: id,
      name: id,
      emoji: '❔',
      isActive: true,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitId: pkId,
    );

    domain.FrontingSession session(
      String id,
      String? memberId, {
      DateTime? startTime,
      String? pluralkitUuid,
      String? pkImportSource,
      bool isSleep = false,
      bool isDeleted = false,
      DateTime? endTime,
    }) => domain.FrontingSession(
      id: id,
      startTime: startTime ?? DateTime.utc(2026, 2, 1, 12),
      endTime: endTime,
      memberId: memberId,
      pluralkitUuid: pluralkitUuid,
      pkImportSource: pkImportSource,
      sessionType: isSleep
          ? domain.SessionType.sleep
          : domain.SessionType.normal,
      isDeleted: isDeleted,
    );

    PKSwitch pkSwitch(String id, List<String> members) => PKSwitch(
      id: id,
      timestamp: DateTime.utc(2026, 2, 1, 12),
      members: members,
    );

    Future<
      ({
        PluralKitSyncService service,
        _RecordingPushClient client,
        FakeFrontingSessionRepository sessionRepo,
      })
    >
    setupSnapshot({
      required List<domain.Member> members,
      required List<domain.FrontingSession> sessions,
      PKSwitch? current,
      _RecordingPushClient? client,
    }) async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = FakeMemberRepository()..seed(members);
      final sessionRepo = FakeFrontingSessionRepository()
        ..sessions.addAll(sessions);

      final fakeClient =
          client ??
          _RecordingPushClient(
            current: current,
            membersToReturn: [
              for (final member in members)
                if (member.pluralkitId != null)
                  PKMember(
                    id: member.pluralkitId!,
                    uuid: 'uuid-${member.id}',
                    name: member.name,
                  ),
            ],
          );
      final service = PluralKitSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: sessionRepo,
        syncDao: db.pluralKitSyncDao,
        bus: PkSyncEventBus(),
        secureStorage: const FlutterSecureStorage(),
        clientFactory: (_) => fakeClient,
      );
      await service.setToken('valid-token');
      await service.acknowledgeMapping();
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          linkedAt: Value(DateTime.utc(2026, 1, 15)),
          lastSyncDate: Value(DateTime.utc(2024, 1, 2)),
        ),
      );
      await service.loadState();
      return (service: service, client: fakeClient, sessionRepo: sessionRepo);
    }

    test('pushes nothing when PK matches local', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [
          session('s-a', 'a', pluralkitUuid: 'sw-current'),
          session('s-b', 'b', pluralkitUuid: 'sw-current'),
        ],
        current: pkSwitch('sw-current', const ['pkB', 'pkA']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 0);
      expect(result.repaired, 0);
      expect(harness.client.createSwitchCallCount, 0);
    });

    test('pushes new switch when adding co-fronter', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [
          session('s-a', 'a', pluralkitUuid: 'sw-old'),
          session('s-b', 'b'),
        ],
        current: pkSwitch('sw-old', const ['pkA']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 1);
      expect(harness.client.createSwitchMemberIds.single, ['pkA', 'pkB']);
      expect(
        harness.sessionRepo.sessions
            .firstWhere((s) => s.id == 's-a')
            .pluralkitUuid,
        'sw-old',
      );
      expect(
        harness.sessionRepo.sessions
            .firstWhere((s) => s.id == 's-b')
            .pluralkitUuid,
        'sw-1',
      );
    });

    test('pushes new switch when removing co-fronter', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [session('s-b', 'b', pluralkitUuid: 'sw-old')],
        current: pkSwitch('sw-old', const ['pkA', 'pkB']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 1);
      expect(harness.client.createSwitchMemberIds.single, ['pkB']);
      expect(
        harness.sessionRepo.sessions.single.pluralkitUuid,
        'sw-old',
        reason: 'Continuing members keep their entrant switch UUID.',
      );
    });

    test('pushes empty switch when last fronter ends', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [
          session(
            's-a',
            'a',
            pluralkitUuid: 'sw-old',
            endTime: DateTime.utc(2026, 2, 1, 13),
          ),
        ],
        current: pkSwitch('sw-old', const ['pkA']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 1);
      expect(harness.client.createSwitchMemberIds.single, isEmpty);
    });

    test('pushes initial switch when nothing on PK', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [session('s-a', 'a')],
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 1);
      expect(harness.client.createSwitchMemberIds.single, ['pkA']);
      expect(harness.sessionRepo.sessions.single.pluralkitUuid, 'sw-1');
    });

    test('excludes unlinked members from local set', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('u', null)],
        sessions: [session('s-a', 'a'), session('s-u', 'u')],
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchMemberIds.single, ['pkA']);
      expect(
        harness.sessionRepo.sessions
            .firstWhere((s) => s.id == 's-u')
            .pluralkitUuid,
        isNull,
      );
    });

    test('includes file-imported active sessions in snapshot', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [
          session('s-a', 'a', pkImportSource: pkImportSourceFile),
          session('s-b', 'b'),
        ],
        current: pkSwitch('sw-old', const ['pkA']),
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchMemberIds.single, ['pkA', 'pkB']);
    });

    test('excludes sleep sessions', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [session('s-sleep', 'a', isSleep: true), session('s-b', 'b')],
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchMemberIds.single, ['pkB']);
    });

    test('dedups duplicate active rows for same member in snapshot', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [
          session('s-a-1', 'a', startTime: DateTime.utc(2026, 2, 1, 11)),
          session('s-a-2', 'a', startTime: DateTime.utc(2026, 2, 1, 12)),
        ],
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchMemberIds.single, ['pkA']);
    });

    test('is idempotent under concurrent successful calls', () async {
      final client = _RecordingPushClient()..holdCreateSwitch = true;
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [session('s-a', 'a')],
        client: client,
      );

      final first = harness.service.pushPendingSwitches();
      final second = harness.service.pushPendingSwitches();
      await Future<void>.delayed(Duration.zero);
      client.releaseCreateSwitch();

      final results = await Future.wait([first, second]);
      expect(harness.client.createSwitchCallCount, 1);
      expect(results[0].pushed, 1);
      expect(results[1].pushed, 1);
    });

    test('concurrent callers receive the same push exception', () async {
      final client = _RecordingPushClient()
        ..holdCreateSwitch = true
        ..throwCreateError = Exception('boom');
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [session('s-a', 'a')],
        client: client,
      );

      final first = harness.service.pushPendingSwitches();
      final second = harness.service.pushPendingSwitches();
      await Future<void>.delayed(Duration.zero);
      client.releaseCreateSwitch();

      await expectLater(first, throwsA(isA<Exception>()));
      await expectLater(second, throwsA(isA<Exception>()));
      expect(harness.client.createSwitchCallCount, 1);
    });

    test('AppShell-triggered push bails when pull is in progress', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final memberRepo = FakeMemberRepository()..seed([member('a', 'pkA')]);
      final sessionRepo = FakeFrontingSessionRepository()
        ..sessions.add(session('s-a', 'a'));
      final client = _RecordingPushClient()..holdGetGroups = true;
      final service = PluralKitSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: sessionRepo,
        syncDao: db.pluralKitSyncDao,
        bus: PkSyncEventBus(),
        secureStorage: const FlutterSecureStorage(),
        clientFactory: (_) => client,
      );
      await service.setToken('valid-token');
      await service.acknowledgeMapping();
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          linkedAt: Value(DateTime.utc(2026, 1, 15)),
          lastSyncDate: Value(DateTime.utc(2026, 1, 20)),
        ),
      );
      await service.loadState();

      final sync = service.syncRecentData(direction: PkSyncDirection.pullOnly);
      while (!service.state.isSyncing) {
        await Future<void>.delayed(Duration.zero);
      }

      final result = await service.pushPendingSwitches();
      expect(result.pushed, 0);
      expect(client.createSwitchCallCount, 0);

      client.releaseGetGroups();
      await sync;
    });

    test("pull's phase-4 push proceeds during isSyncing", () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [session('s-a', 'a')],
      );

      final summary = await harness.service.syncRecentData(
        direction: PkSyncDirection.pushOnly,
      );

      expect(harness.client.createSwitchCallCount, 1);
      expect(summary!.switchesPushed, 1);
    });

    test('retries with filtered set on stale-link 404', () async {
      final client = _RecordingPushClient(
        membersToReturn: const [
          PKMember(id: 'pkA', uuid: 'uuid-a', name: 'A'),
          PKMember(id: 'pkB', uuid: 'uuid-b', name: 'B'),
        ],
      )..staleFailuresRemaining = 1;
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB'), member('c', 'pkC')],
        sessions: [
          session('s-a', 'a'),
          session('s-b', 'b'),
          session('s-c', 'c'),
        ],
        client: client,
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchCallCount, 2);
      expect(harness.client.createSwitchMemberIds[0], ['pkA', 'pkB', 'pkC']);
      expect(harness.client.createSwitchMemberIds[1], ['pkA', 'pkB']);
    });

    test('stale-link retry fails permanently after one retry', () async {
      final messages = <String>[];
      final client = _RecordingPushClient(
        membersToReturn: const [PKMember(id: 'pkA', uuid: 'uuid-a', name: 'A')],
      )..staleFailuresRemaining = 2;
      final harness = await setupSnapshot(
        members: [member('a', 'pkA'), member('b', 'pkB')],
        sessions: [session('s-a', 'a'), session('s-b', 'b')],
        client: client,
      );

      final result = await harness.service.pushPendingSwitches(
        onStaleLink: messages.add,
      );

      expect(result.pushed, 0);
      expect(harness.client.createSwitchCallCount, 2);
      expect(messages, isNotEmpty);
    });

    test('pre-link active session is included in current set', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [
          session(
            's-a',
            'a',
            startTime: DateTime.utc(
              2026,
              1,
              15,
            ).subtract(const Duration(hours: 1)),
          ),
        ],
      );

      await harness.service.pushPendingSwitches();

      expect(harness.client.createSwitchMemberIds.single, ['pkA']);
    });

    test('stamp-repair on no-op path', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [session('s-a', 'a')],
        current: pkSwitch('sw-current', const ['pkA']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.pushed, 0);
      expect(result.repaired, 1);
      expect(harness.client.createSwitchCallCount, 0);
      expect(harness.sessionRepo.sessions.single.pluralkitUuid, 'sw-current');
    });

    test('stamp collision on duplicate active rows', () async {
      final harness = await setupSnapshot(
        members: [member('a', 'pkA')],
        sessions: [
          session('s-a-old', 'a', startTime: DateTime.utc(2026, 2, 1, 10)),
          session(
            's-a-new',
            'a',
            startTime: DateTime.utc(2026, 2, 1, 11),
            pluralkitUuid: 'sw-current',
          ),
        ],
        current: pkSwitch('sw-current', const ['pkA']),
      );

      final result = await harness.service.pushPendingSwitches();

      expect(result.repaired, 1);
      expect(
        harness.sessionRepo.sessions
            .firstWhere((s) => s.id == 's-a-old')
            .pluralkitUuid,
        isNull,
      );
      expect(
        harness.sessionRepo.sessions
            .firstWhere((s) => s.id == 's-a-new')
            .pluralkitUuid,
        'sw-current',
      );
    });
  });
}

// Subclass that records createSwitch invocations and returns a unique switch
// id on each call. Used by the snapshot push tests above.
class _RecordingPushClient extends FakePluralKitClient {
  _RecordingPushClient({
    this.current,
    List<PKMember> membersToReturn = const [],
  }) {
    this.membersToReturn = membersToReturn;
  }

  PKSwitch? current;
  int createSwitchCallCount = 0;
  final List<List<String>> createSwitchMemberIds = [];
  bool holdCreateSwitch = false;
  Object? throwCreateError;
  int staleFailuresRemaining = 0;
  Completer<void>? _createSwitchCompleter;

  bool holdGetGroups = false;
  Completer<void>? _getGroupsCompleter;

  void releaseCreateSwitch() {
    _createSwitchCompleter?.complete();
  }

  void releaseGetGroups() {
    _getGroupsCompleter?.complete();
  }

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    getCurrentFrontersCallCount++;
    return current;
  }

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    if (holdCreateSwitch) {
      _createSwitchCompleter ??= Completer<void>();
      await _createSwitchCompleter!.future;
    }
    createSwitchCallCount++;
    createSwitchMemberIds.add(List.unmodifiable(memberIds));
    final error = throwCreateError;
    if (error != null) throw error;
    if (staleFailuresRemaining > 0) {
      staleFailuresRemaining--;
      throw const PluralKitApiError(404, 'stale');
    }
    return PKSwitch(
      id: 'sw-$createSwitchCallCount',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    getGroupsCallCount++;
    if (holdGetGroups) {
      _getGroupsCompleter ??= Completer<void>();
      await _getGroupsCompleter!.future;
    }
    return groupsToReturn;
  }
}

// Subclass of FakePluralKitClient that always 404s createSwitch, simulating
// PK having deleted the member/system referenced by a pending local switch.
class _StaleCreateSwitchClient extends FakePluralKitClient {
  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds, {DateTime? timestamp}) {
    throw const PluralKitApiError(404, 'stale');
  }
}

// Counting DAO that records each upsert that touches cursor columns —
// used to verify the "once per batch" cursor advance contract (WS3 step 7).
class _CountingPluralKitSyncDao extends PluralKitSyncDao {
  _CountingPluralKitSyncDao(super.db);
  int cursorWriteCount = 0;

  @override
  Future<void> upsertSyncState(PluralKitSyncStateCompanion state) {
    if (state.switchCursorTimestamp.present || state.switchCursorId.present) {
      cursorWriteCount++;
    }
    return super.upsertSyncState(state);
  }
}

// Pagination-controllable fake client. Returns pages strictly in order from
// [pages]; each call returns one page. Records every `before` value so tests
// can assert the paging key advances.
class _PaginatingFakeClient extends FakePluralKitClient {
  _PaginatingFakeClient(this.pages);
  final List<List<PKSwitch>> pages;
  final List<DateTime?> beforeValues = [];

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    getSwitchesCallCount++;
    beforeValues.add(before);
    if (pages.isEmpty) return const [];
    return pages.removeAt(0);
  }
}

// Pagination client that returns the same fixed page forever — used to
// drive both the no-progress guard (when consecutive pages don't advance
// `before`) and the page-cap guard (when the loop never terminates).
class _StuckPaginationFakeClient extends FakePluralKitClient {
  _StuckPaginationFakeClient(this.fixedPage);
  final List<PKSwitch> fixedPage;
  int callsServed = 0;

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    getSwitchesCallCount++;
    callsServed++;
    return fixedPage;
  }
}

void _registerWs3PrDTests() {
  // The outer `main()` already sets up the secure-storage stub before each
  // test, so this group only needs to register its own tests.
  group('WS3 PR D — cursor batching + pagination guards', () {
    test(
      'cursor advances once per batch, not once per switch (WS3 step 7)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final countingDao = _CountingPluralKitSyncDao(db);

        final memberRepo = FakeMemberRepository();
        memberRepo.seed([
          domain.Member(
            id: 'local-a',
            name: 'A',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            pluralkitId: 'pkA',
            pluralkitUuid: '00000000-0000-0000-0000-00000000000a',
          ),
        ]);

        // Three switches in one batch. Under the old per-switch cursor
        // advance this would trigger 3 cursor writes. With WS3 step 7 the
        // incremental sweep must write the cursor exactly once.
        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final sw2 = PKSwitch(
          id: 'sw-2',
          timestamp: DateTime.utc(2026, 1, 1, 11),
          members: const ['pkA'],
        );
        final sw3 = PKSwitch(
          id: 'sw-3',
          timestamp: DateTime.utc(2026, 1, 1, 12),
          members: const ['pkA'],
        );

        // Seed a prior cursor + lastSyncDate so syncRecentData runs the
        // incremental sweep (single cursor write at end-of-batch). The
        // performFullImport path resets the cursor up-front, which would
        // double the count for reasons unrelated to step 7.
        await countingDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            switchCursorTimestamp: Value(DateTime.utc(2025, 1, 1)),
            switchCursorId: const Value('ancient'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1)),
          ),
        );

        final fakeClient = FakePluralKitClient()
          ..switchesPageQueue = [
            [sw3, sw2, sw1], // newest-first
            [],
          ];

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: FakeFrontingSessionRepository(),
          syncDao: countingDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => fakeClient,
        );
        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await service.loadState();

        // Reset the counter so we only measure the sweep itself, not setup.
        countingDao.cursorWriteCount = 0;

        await service.syncRecentData();

        expect(
          countingDao.cursorWriteCount,
          1,
          reason:
              'incremental sweep must write the cursor exactly once per '
              'batch (was once per switch under the old code path).',
        );

        final state = await db.pluralKitSyncDao.getSyncState();
        expect(state.switchCursorId, 'sw-3', reason: 'newest in batch');
        expect(
          state.switchCursorTimestamp?.toUtc(),
          DateTime.utc(2026, 1, 1, 12),
        );
      },
    );

    test(
      'pagination no-progress guard: same `page.last.timestamp` on '
      'consecutive non-empty pages throws PkPaginationNoProgressError',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = FakeMemberRepository();
        memberRepo.seed([
          domain.Member(
            id: 'local-a',
            name: 'A',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            pluralkitId: 'pkA',
            pluralkitUuid: '00000000-0000-0000-0000-00000000000a',
          ),
        ]);

        // Two consecutive pages that share the same oldest timestamp —
        // naive `before = page.last.timestamp` would loop forever.
        final stuckTs = DateTime.utc(2026, 1, 1, 10);
        final fixedPage = List.generate(
          100,
          (i) => PKSwitch(
            id: 'sw-${i.toString().padLeft(3, '0')}',
            timestamp: stuckTs,
            members: const ['pkA'],
          ),
        );

        // Seed the cursor + lastSyncDate so syncRecentData enters the
        // incremental path (which is where the no-progress guard lives).
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            switchCursorTimestamp: Value(DateTime.utc(2025, 1, 1)),
            switchCursorId: const Value('cursor-id'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1, 9)),
          ),
        );

        final fakeClient = _StuckPaginationFakeClient(fixedPage);

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: FakeFrontingSessionRepository(),
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => fakeClient,
        );
        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await service.loadState();

        await expectLater(
          service.syncRecentData(),
          throwsA(isA<PkPaginationNoProgressError>()),
        );
      },
    );

    test(
      'page-cap guard: pagination beyond _maxIncrementalPages throws '
      'PkImportTooLargeError',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = FakeMemberRepository();
        memberRepo.seed([
          domain.Member(
            id: 'local-a',
            name: 'A',
            emoji: '❔',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            pluralkitId: 'pkA',
            pluralkitUuid: '00000000-0000-0000-0000-00000000000a',
          ),
        ]);

        // Build a paginating client that always returns a full page with a
        // strictly-decreasing oldest timestamp so the no-progress guard
        // never trips, but the page count grows without bound. We rely on
        // the page-cap guard (1000) to stop it.
        final pages = List.generate(
          PluralKitSyncService.maxIncrementalPagesForTesting + 5,
          (pageIdx) => List.generate(100, (rowIdx) {
            // Timestamps decrease with both page index and row index so the
            // page's "last" timestamp is unique across pages.
            final offset = pageIdx * 100 + rowIdx;
            return PKSwitch(
              id: 'p$pageIdx-r$rowIdx',
              timestamp: DateTime.utc(
                2026,
                1,
                1,
              ).subtract(Duration(seconds: offset)),
              members: const ['pkA'],
            );
          }),
        );

        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            switchCursorTimestamp: Value(DateTime.utc(2020, 1, 1)),
            switchCursorId: const Value('ancient'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1)),
          ),
        );

        final fakeClient = _PaginatingFakeClient(pages);

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: FakeFrontingSessionRepository(),
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => fakeClient,
        );
        await service.setToken('valid-token');
        await service.acknowledgeMapping();
        await service.loadState();

        await expectLater(
          service.syncRecentData(),
          throwsA(isA<PkImportTooLargeError>()),
        );
      },
      // Building 1000+ pages × 100 rows is mildly slow; bump the timeout.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
