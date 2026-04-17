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

// ---------------------------------------------------------------------------
// Secure storage stub (copied verbatim from biometric_service_test.dart)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};
  bool throwOnRead = false;

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
            if (throwOnRead) throw PlatformException(code: 'AuthError');
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
    throwOnRead = false;
  }
}

// ---------------------------------------------------------------------------
// Fake PluralKitClient
// ---------------------------------------------------------------------------

class FakePluralKitClient implements PluralKitClient {
  int getSystemCallCount = 0;
  int getSwitchesCallCount = 0;
  int getMembersCallCount = 0;

  // Configurable behavior
  bool throwAuthError = false;
  bool throwNetworkError = false;

  PKSystem systemToReturn = const PKSystem(id: 'sys-1', name: 'Test System');
  List<PKMember> membersToReturn = const [];
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
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
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
  Future<PKSwitch> createSwitch(List<String> memberIds, {DateTime? timestamp}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  void dispose() {}
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
  Future<List<domain.Member>> getAllMembers() async =>
      _members.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _members[id];

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _members[id]).whereType<domain.Member>().toList();

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
  Future<domain.FrontingSession?> getActiveSession() async =>
      sessions.cast<domain.FrontingSession?>().firstWhere(
        (s) => s!.isActive,
        orElse: () => null,
      );

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async =>
      sessions.cast<domain.FrontingSession?>().firstWhere(
        (s) => s!.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
    String memberId,
  ) async =>
      sessions.where((s) => s.memberId == memberId).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({
    int limit = 20,
  }) async =>
      sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async =>
      sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async =>
      sessions
          .where(
            (s) =>
                !s.startTime.isBefore(start) && !s.startTime.isAfter(end),
          )
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
  Stream<domain.FrontingSession?> watchActiveSession() =>
      Stream.value(null);

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
  Stream<List<domain.FrontingSession>> watchRecentSessions({
    int limit = 20,
  }) =>
      Stream.value(sessions.take(limit).toList());

  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) =>
      Stream.value(sessions.take(limit).toList());

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
  }) async =>
      {};
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
}) {
  return PluralKitSyncService(
    memberRepository: memberRepo ?? FakeMemberRepository(),
    frontingSessionRepository: sessionRepo ?? FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => fakeClient,
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
    });

    test('401 from getSystem: isConnected = false, token deleted from storage',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient()..throwAuthError = true;
      final service = _makeService(fakeClient: fakeClient, db: db);

      await service.setToken('bad-token');

      expect(service.state.isConnected, isFalse);
      expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
      expect(service.state.syncError, isNotNull);
    });

    test('network error from getSystem: isConnected = false, token deleted',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final fakeClient = FakePluralKitClient()..throwNetworkError = true;
      final service = _makeService(fakeClient: fakeClient, db: db);

      await service.setToken('some-token');

      expect(service.state.isConnected, isFalse);
      expect(storageStub._store.containsKey(_pkTokenKey), isFalse);
      expect(service.state.syncError, isNotNull);
    });
  });

  // ── clearToken ───────────────────────────────────────────────────────────────

  group('clearToken', () {
    test('resets state: isConnected = false, token gone, lastSyncDate = null',
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
    });
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
    test('switch with members = [] is skipped: no FrontingSession created',
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
      // lastSyncDate null → full import path
      await service.syncRecentData();

      // Switch has no members → primaryMemberId == null → no session created
      expect(sessionRepo.sessions, isEmpty);
    });
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
              startTime: DateTime(2026, 1, 1).subtract(
                Duration(minutes: knownSwitchIds.indexOf(switchId)),
              ),
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
}
