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

void main() {
  group('PluralKitSyncState — truth table', () {
    // Full 8-row truth table for
    // (isConnected × directionConfirmed × mappingAcknowledged)
    // → (needsDirection, needsMapping, canAutoSync)
    //
    // Row 1: disconnected, nothing confirmed
    test('not connected, nothing confirmed → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 2: disconnected, directionConfirmed
    test('not connected, directionConfirmed=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 3: disconnected, mappingAcknowledged (hypothetical)
    test('not connected, mappingAcknowledged=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: false,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 4: disconnected, both confirmed
    test('not connected, both flags=true → all false', () {
      const state = PluralKitSyncState(
        isConnected: false,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 5: connected, nothing confirmed → needsDirection only
    test('connected, nothing confirmed → needsDirection=true, needsMapping=false, canAutoSync=false', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, true);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 6: connected, directionConfirmed, not mappingAcknowledged → needsMapping only
    test('connected, directionConfirmed=true, mappingAcknowledged=false → needsMapping=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, true);
      expect(state.canAutoSync, false);
    });

    // Row 7: connected, mappingAcknowledged without directionConfirmed
    // (hypothetical / migration edge case — should land in needsDirection)
    test('connected, mappingAcknowledged=true, directionConfirmed=false → needsDirection=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, true);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });

    // Row 8: connected, both confirmed → canAutoSync only
    test('connected, both flags=true → canAutoSync=true', () {
      const state = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, true);
    });
  });

  group('PluralKitSyncState — defaults', () {
    test('default constructor produces all-false state', () {
      const state = PluralKitSyncState();
      expect(state.isConnected, false);
      expect(state.directionConfirmed, false);
      expect(state.mappingAcknowledged, false);
      expect(state.needsDirection, false);
      expect(state.needsMapping, false);
      expect(state.canAutoSync, false);
    });
  });

  group('PluralKitSyncState — copyWith round-trips', () {
    test('copyWith preserves directionConfirmed', () {
      const base = PluralKitSyncState(isConnected: true, directionConfirmed: false);
      final updated = base.copyWith(directionConfirmed: true);
      expect(updated.directionConfirmed, true);
      expect(updated.isConnected, true);
    });

    test('copyWith preserves mappingAcknowledged', () {
      const base = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      final updated = base.copyWith(mappingAcknowledged: true);
      expect(updated.mappingAcknowledged, true);
      expect(updated.directionConfirmed, true);
      expect(updated.canAutoSync, true);
    });

    test('copyWith transitions needsDirection → needsMapping', () {
      const afterConnect = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      expect(afterConnect.needsDirection, true);

      final afterDirection = afterConnect.copyWith(directionConfirmed: true);
      expect(afterDirection.needsDirection, false);
      expect(afterDirection.needsMapping, true);
    });

    test('copyWith transitions needsMapping → canAutoSync', () {
      const afterDirection = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      expect(afterDirection.needsMapping, true);

      final afterMapping = afterDirection.copyWith(mappingAcknowledged: true);
      expect(afterMapping.needsMapping, false);
      expect(afterMapping.canAutoSync, true);
    });

    test('copyWith does not mutate source', () {
      const base = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: false,
        mappingAcknowledged: false,
      );
      base.copyWith(directionConfirmed: true, mappingAcknowledged: true);
      expect(base.directionConfirmed, false);
      expect(base.mappingAcknowledged, false);
    });
  });

  group('PluralKitSyncState — equality', () {
    test('identical states are equal', () {
      const a = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      const b = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('states differing in directionConfirmed are not equal', () {
      const a = PluralKitSyncState(isConnected: true, directionConfirmed: false);
      const b = PluralKitSyncState(isConnected: true, directionConfirmed: true);
      expect(a, isNot(equals(b)));
    });

    test('states differing in mappingAcknowledged are not equal', () {
      const a = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: false,
      );
      const b = PluralKitSyncState(
        isConnected: true,
        directionConfirmed: true,
        mappingAcknowledged: true,
      );
      expect(a, isNot(equals(b)));
    });
  });

  // Task 6: service-level transition tests for confirmDirection().
  _registerConfirmDirectionTests();
}

// ============================================================================
// Task 6: confirmDirection() service transition tests
//
// These are integration-style tests that drive the real PluralKitSyncService
// through the full connect → confirmDirection() → needsMapping transition.
// ============================================================================

// ---------------------------------------------------------------------------
// Secure-storage stub
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
// Minimal fakes
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  @override
  String get currentToken => 'fake';
  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test');
  @override
  Future<List<PKMember>> getMembers() async => const [];
  @override
  Future<PKMember> getMember(String r) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async =>
      const [];
  @override
  Future<PKSwitch?> getCurrentFronters() async => null;
  @override
  Future<PKMember> createMember(Map<String, dynamic> d) =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> d) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> createSwitch(List<String> m, {DateTime? timestamp}) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitch(String id, {required DateTime timestamp}) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(String id, List<String> m) =>
      throw UnimplementedError();
  @override
  Future<void> deleteSwitch(String id) => throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) async => const [];
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String g) async => const [];
  @override
  Future<void> addMembersToGroup(String g, List<String> m) =>
      throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(String g, List<String> m) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _FakeMemberRepo implements MemberRepository {
  
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {}
  
  Future<void> clearCreatePushStartedAt(String id) async {}
  @override
  Future<List<domain.Member>> getAllMembers() async => const [];
  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => const [];
  @override
  Future<domain.Member?> getMemberById(String id) async => null;
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      const [];
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(const []);
  @override
  Future<void> createMember(domain.Member m) async {}
  @override
  Future<void> updateMember(domain.Member m) async {}
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
  Future<void> stampDeletePushStartedAt(String id, int ts) async {}
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

class _FakeSessionRepo implements FrontingSessionRepository {
  @override
  Future<List<domain.FrontingSession>> getAllSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async => const [];
  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      const [];
  @override
  Future<domain.FrontingSession?> getActiveSession() async => null;
  @override
  Future<domain.FrontingSession?> getSessionById(String id) async => null;
  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(String m) async =>
      const [];
  @override
  Future<List<domain.FrontingSession>> getRecentSessions({int limit = 20}) async =>
      const [];
  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async => const [];
  @override
  Future<void> createSession(domain.FrontingSession s) async {}
  @override
  Future<void> updateSession(domain.FrontingSession s) async {}
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
  Future<void> stampDeletePushStartedAt(String id, int ts) async {}
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
// confirmDirection() transition tests
// ---------------------------------------------------------------------------

AppDatabase _makeTransitionDb() => AppDatabase(NativeDatabase.memory());

PluralKitSyncService _makeTransitionService(AppDatabase db) {
  return PluralKitSyncService(
    memberRepository: _FakeMemberRepo(),
    frontingSessionRepository: _FakeSessionRepo(),
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => _FakeClient(),
  );
}

void _registerConfirmDirectionTests() {
  final storageStub = _SecureStorageStub();

  group('confirmDirection() — service transition', () {
    setUp(storageStub.setup);
    tearDown(storageStub.teardown);

    test(
      'after fresh setToken → needsDirection=true; '
      'after confirmDirection → needsMapping=true, needsDirection=false',
      () async {
        final db = _makeTransitionDb();
        addTearDown(db.close);

        final service = _makeTransitionService(db);

        // Step 1: fresh connect.
        await service.setToken('some-token');
        expect(service.state.isConnected, isTrue);
        expect(service.state.needsDirection, isTrue,
            reason: 'fresh connection should need direction');
        expect(service.state.needsMapping, isFalse,
            reason: 'mapping gated behind direction');
        expect(service.state.canAutoSync, isFalse);

        // Step 2: confirm direction.
        await service.confirmDirection();
        expect(service.state.needsDirection, isFalse,
            reason: 'directionConfirmed=true clears needsDirection');
        expect(service.state.needsMapping, isTrue,
            reason: 'after direction confirmed, mapping is next');
        expect(service.state.canAutoSync, isFalse);

        // Persisted state reflects the change.
        final row = await db.pluralKitSyncDao.getSyncState();
        expect(row.directionConfirmed, isTrue);
        expect(row.mappingAcknowledged, isFalse);
      },
    );
  });
}

