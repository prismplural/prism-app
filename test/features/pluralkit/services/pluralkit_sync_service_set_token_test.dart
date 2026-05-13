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
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Secure-storage stub (same pattern as pluralkit_sync_service_test.dart)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                _store[key] = value;
                return null;
              case 'read':
                final key = call.arguments['key'] as String;
                return _store[key];
              case 'delete':
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
  }
}

// ---------------------------------------------------------------------------
// Minimal fake PluralKitClient
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  _FakeClient(this._systemId);

  final String _systemId;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async =>
      PKSystem(id: _systemId, name: 'Test System');

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
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

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
}
