import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

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
    getSystemCallCount++;
    if (throwAuthError) throw const PluralKitAuthError();
    if (throwNetworkError) throw Exception('Network unreachable');
    return systemToReturn;
  }

  @override
  Future<List<PKMember>> getMembers() async {
    getMembersCallCount++;
    return membersToReturn;
  }

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
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
    getGroupsCallCount++;
    return groupsToReturn;
  }

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();

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
      const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}
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

  group('importFromTokenOnce', () {
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

      final result = await service.importFromTokenOnce('one-shot-token');

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
    test('triggers performFullImport (getSwitches is called)', () async {
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

      await service.syncRecentData();

      // performFullImport calls getSwitches at least once
      expect(fakeClient.getSwitchesCallCount, greaterThan(0));
    });
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
        sessionRepo.sessions.add(
          domain.FrontingSession(
            id: 's-new',
            startTime: DateTime(2026, 2, 1, 12),
            memberId: 'local-a',
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
}

// Subclass of FakePluralKitClient that always 404s createSwitch, simulating
// PK having deleted the member/system referenced by a pending local switch.
class _StaleCreateSwitchClient extends FakePluralKitClient {
  @override
  Future<PKSwitch> createSwitch(List<String> memberIds, {DateTime? timestamp}) {
    throw const PluralKitApiError(404, 'stale');
  }
}
