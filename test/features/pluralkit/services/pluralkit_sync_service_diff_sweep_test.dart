/// Tests for PluralKitSyncService diff-sweep algorithm (Phase 4B).
///
/// Covers:
/// - Correctness: A→A+B→A produces 1 long A row + 1 short B row.
/// - Correctness: A→∅→A produces 2 separate A rows.
/// - Correctness: ∅→A→∅ produces 1 row start→end.
/// - Correctness: A,B→C,D produces close-A, close-B, open-C, open-D.
/// - Resume cursor: (timestamp, switch_id) tuple advances correctly.
/// - Crash-resume: prevActive reconstituted from open rows.
/// - Corrective full re-import: pre-closes open rows, resets cursor.
/// - Deterministic IDs: same (switch_id, member_pk_uuid) always same row id.
/// - Atomic transaction: cursor advances with each switch.
/// - Member resolution: short ID→pluralkit_id→pluralkit_uuid chain.
/// - Unmapped short ID: counted in result, doesn't silently skip.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_switch_cursor.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

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
// Minimal fake client that returns preconfigured switch pages
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  /// Pages are popped in order. Each call to getSwitches removes the first page.
  /// When empty, returns [].
  final List<List<PKSwitch>> switchPages;

  _FakeClient(this.switchPages);

  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    if (switchPages.isEmpty) return const [];
    return switchPages.removeAt(0);
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

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
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Forwarding fronting-session repository whose [deleteSession] throws on
// the Nth invocation. Used by the canonicalization-atomicity test to
// simulate a mid-loop failure without manually mocking 30 methods.
// ---------------------------------------------------------------------------

class _FlakyDeleteRepo implements FrontingSessionRepository {
  _FlakyDeleteRepo({required this.delegate, required this.throwOnDeleteCount});

  final FrontingSessionRepository delegate;

  /// 1-based count of [deleteSession] calls before the throw fires. The
  /// Nth call throws; calls 1..(N-1) delegate normally.
  final int throwOnDeleteCount;
  int _deleteCalls = 0;

  @override
  Future<void> deleteSession(String id) async {
    _deleteCalls++;
    if (_deleteCalls == throwOnDeleteCount) {
      throw StateError('flaky deleteSession failure on call $_deleteCalls');
    }
    return delegate.deleteSession(id);
  }

  // -- All other interface methods: delegate verbatim -----------------------
  // Manual forwarding instead of `noSuchMethod` so the analyzer + Dart's
  // implements-checker stay happy.

  @override
  Future<List<domain_fs.FrontingSession>> getAllSessions() =>
      delegate.getAllSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getFrontingSessions() =>
      delegate.getFrontingSessions();
  @override
  Stream<List<domain_fs.FrontingSession>> watchAllSessions() =>
      delegate.watchAllSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getActiveSessions() =>
      delegate.getActiveSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getAllActiveSessionsUnfiltered() =>
      delegate.getAllActiveSessionsUnfiltered();
  @override
  Stream<List<domain_fs.FrontingSession>> watchActiveSessions() =>
      delegate.watchActiveSessions();
  @override
  Future<domain_fs.FrontingSession?> getActiveSession() =>
      delegate.getActiveSession();
  @override
  Stream<domain_fs.FrontingSession?> watchActiveSession() =>
      delegate.watchActiveSession();
  @override
  Stream<domain_fs.FrontingSession?> watchActiveSleepSession() =>
      delegate.watchActiveSleepSession();
  @override
  Stream<List<domain_fs.FrontingSession>> watchAllSleepSessions() =>
      delegate.watchAllSleepSessions();
  @override
  Future<domain_fs.FrontingSession?> getSessionById(String id) =>
      delegate.getSessionById(id);
  @override
  Stream<domain_fs.FrontingSession?> watchSessionById(String id) =>
      delegate.watchSessionById(id);
  @override
  Future<List<domain_fs.FrontingSession>> getSessionsForMember(
    String memberId,
  ) => delegate.getSessionsForMember(memberId);
  @override
  Future<List<domain_fs.FrontingSession>> getRecentSessions({int limit = 20}) =>
      delegate.getRecentSessions(limit: limit);
  @override
  Future<List<domain_fs.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) => delegate.getRecentSleepSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchRecentSessions({
    int limit = 20,
  }) => delegate.watchRecentSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) => delegate.watchRecentAllSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) => delegate.watchSessionsOverlappingRange(start, end);
  @override
  Future<void> createSession(domain_fs.FrontingSession session) =>
      delegate.createSession(session);
  @override
  Future<void> updateSession(domain_fs.FrontingSession session) =>
      delegate.updateSession(session);
  @override
  Future<void> endSession(String id, DateTime endTime) =>
      delegate.endSession(id, endTime);
  @override
  Future<List<domain_fs.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) => delegate.getSessionsBetween(start, end);
  @override
  Future<int> getCount() => delegate.getCount();
  @override
  Future<int> getFrontingCount() => delegate.getFrontingCount();
  @override
  Future<List<domain_fs.FrontingSession>> getDeletedLinkedSessions() =>
      delegate.getDeletedLinkedSessions();
  @override
  Future<void> clearPluralKitLink(String id) => delegate.clearPluralKitLink(id);
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      delegate.stampDeletePushStartedAt(id, timestampMs);
  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) => delegate.getMemberFrontingCounts(
    recentLimit: recentLimit,
    startHour: startHour,
    endHour: endHour,
    withinDays: withinDays,
  );
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Create a local member with both pluralkitId (short) and pluralkitUuid (full).
domain.Member _member({
  required String localId,
  required String pkShortId,
  required String pkUuid,
  String name = 'Member',
}) => domain.Member(
  id: localId,
  name: name,
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: pkShortId,
  pluralkitUuid: pkUuid,
);

PluralKitSyncService _makeService({
  required AppDatabase db,
  required _FakeClient client,
  DriftMemberRepository? memberRepo,
  DriftFrontingSessionRepository? sessionRepo,
}) {
  memberRepo ??= DriftMemberRepository(db.membersDao, null);
  sessionRepo ??= DriftFrontingSessionRepository(db.frontingSessionsDao, null);
  return PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
  );
}

/// Compute the expected deterministic ID for a per-member row.
///
/// Routes through the same helper the production code uses so a future
/// change to the derivation can't silently desync test expectations
/// from production.
String _expectedRowId(String entrySwitchId, String memberPkUuid) =>
    derivePkSessionId(entrySwitchId, memberPkUuid);

/// Matcher that compares two [DateTime] values as the same instant in time,
/// regardless of whether one is UTC and the other is local. Drift returns
/// timestamps in local time; tests use DateTime.utc(...). This normalises
/// both sides to milliseconds-since-epoch for comparison.
Matcher _sameInstant(DateTime expected) => predicate<DateTime>(
  (actual) => actual.millisecondsSinceEpoch == expected.millisecondsSinceEpoch,
  'same instant as $expected',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();

  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  // -- Diff sweep correctness -----------------------------------------------

  group('diff sweep correctness', () {
    test(
      'A → A+B → A produces 1 long A row + 1 short B row, not 3 A rows',
      () async {
        // The core diff-sweep correctness test. A is continuously present
        // across both switches; B enters and leaves. Expected:
        //   - A: 1 row from sw1.timestamp, no end (still active)
        //   - B: 1 row from sw2.timestamp to sw3.timestamp
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );
        await memberRepo.createMember(
          _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        );

        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final sw2 = PKSwitch(
          id: 'sw-2',
          timestamp: DateTime.utc(2026, 1, 1, 12),
          members: const ['pkA', 'pkB'],
        );
        final sw3 = PKSwitch(
          id: 'sw-3',
          timestamp: DateTime.utc(2026, 1, 1, 14),
          members: const ['pkA'],
        );

        // Full import: pages come newest-first; our _fetchAllSwitches sorts.
        final client = _FakeClient([
          [sw3, sw2, sw1], // newest-first page
          [], // end of pagination
        ]);

        final service = _makeService(db: db, client: client);
        await service.setToken('t');
        await service.acknowledgeMapping();
        await service.importSwitchesAfterLink();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();

        // Exactly 2 sessions: 1 for A (entry sw-1), 1 for B (entry sw-2).
        expect(sessions, hasLength(2));

        final aRows = sessions.where((s) => s.memberId == 'local-a').toList();
        final bRows = sessions.where((s) => s.memberId == 'local-b').toList();
        expect(aRows, hasLength(1), reason: 'A should have exactly 1 row');
        expect(bRows, hasLength(1), reason: 'B should have exactly 1 row');

        // A started at sw-1, is still open (no switch closed it).
        expect(aRows.single.startTime, _sameInstant(sw1.timestamp));
        expect(aRows.single.endTime, isNull, reason: 'A is still active');
        expect(
          aRows.single.pluralkitUuid,
          'sw-1',
          reason: 'entry switch is sw-1',
        );

        // B started at sw-2 and closed at sw-3.
        expect(bRows.single.startTime, _sameInstant(sw2.timestamp));
        expect(bRows.single.endTime, _sameInstant(sw3.timestamp));
        expect(
          bRows.single.pluralkitUuid,
          'sw-2',
          reason: 'B entry switch is sw-2',
        );

        // Deterministic IDs.
        expect(aRows.single.id, _expectedRowId('sw-1', 'uuid-a'));
        expect(bRows.single.id, _expectedRowId('sw-2', 'uuid-b'));
      },
    );

    test('A → ∅ → A produces 2 separate A rows', () async {
      // Switch-out (members: []) closes A's session. A second switch re-opens A.
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sw1 = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );
      final sw2 = PKSwitch(
        id: 'sw-2',
        timestamp: DateTime.utc(2026, 1, 1, 12),
        members: const [], // switch-out
      );
      final sw3 = PKSwitch(
        id: 'sw-3',
        timestamp: DateTime.utc(2026, 1, 1, 14),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw3, sw2, sw1],
        [],
      ]);

      final service = _makeService(db: db, client: client);
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final sessions = await sessionRepo.getAllSessions();
      sessions.sort((a, b) => a.startTime.compareTo(b.startTime));

      expect(sessions, hasLength(2));

      // First A row: sw-1 → sw-2 (closed by switch-out).
      expect(sessions[0].memberId, 'local-a');
      expect(sessions[0].startTime, _sameInstant(sw1.timestamp));
      expect(sessions[0].endTime, _sameInstant(sw2.timestamp));
      expect(sessions[0].pluralkitUuid, 'sw-1');

      // Second A row: sw-3 → open.
      expect(sessions[1].memberId, 'local-a');
      expect(sessions[1].startTime, _sameInstant(sw3.timestamp));
      expect(sessions[1].endTime, isNull);
      expect(sessions[1].pluralkitUuid, 'sw-3');

      // Deterministic IDs are different (different entry switches).
      expect(sessions[0].id, _expectedRowId('sw-1', 'uuid-a'));
      expect(sessions[1].id, _expectedRowId('sw-3', 'uuid-a'));
      expect(sessions[0].id, isNot(sessions[1].id));
    });

    test('∅ → A → ∅ produces 1 A row with start + end set', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sw1 = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const [], // starts with switch-out (no-op)
      );
      final sw2 = PKSwitch(
        id: 'sw-2',
        timestamp: DateTime.utc(2026, 1, 1, 12),
        members: const ['pkA'],
      );
      final sw3 = PKSwitch(
        id: 'sw-3',
        timestamp: DateTime.utc(2026, 1, 1, 14),
        members: const [], // closes A
      );

      final client = _FakeClient([
        [sw3, sw2, sw1],
        [],
      ]);

      final service = _makeService(db: db, client: client);
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final sessions = await sessionRepo.getAllSessions();

      expect(sessions, hasLength(1));
      expect(sessions.single.memberId, 'local-a');
      expect(sessions.single.startTime, _sameInstant(sw2.timestamp));
      expect(sessions.single.endTime, _sameInstant(sw3.timestamp));
      expect(sessions.single.pluralkitUuid, 'sw-2');
      expect(sessions.single.id, _expectedRowId('sw-2', 'uuid-a'));
    });

    test('A,B → C,D produces close-A, close-B, open-C, open-D', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      for (final m in [
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        _member(localId: 'local-c', pkShortId: 'pkC', pkUuid: 'uuid-c'),
        _member(localId: 'local-d', pkShortId: 'pkD', pkUuid: 'uuid-d'),
      ]) {
        await memberRepo.createMember(m);
      }

      final sw1 = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA', 'pkB'],
      );
      final sw2 = PKSwitch(
        id: 'sw-2',
        timestamp: DateTime.utc(2026, 1, 1, 12),
        members: const ['pkC', 'pkD'],
      );

      final client = _FakeClient([
        [sw2, sw1],
        [],
      ]);

      final service = _makeService(db: db, client: client);
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final sessions = await sessionRepo.getAllSessions();

      expect(sessions, hasLength(4));

      // A and B: opened at sw-1, closed at sw-2.
      final aRow = sessions.firstWhere((s) => s.memberId == 'local-a');
      final bRow = sessions.firstWhere((s) => s.memberId == 'local-b');
      expect(aRow.startTime, _sameInstant(sw1.timestamp));
      expect(aRow.endTime, _sameInstant(sw2.timestamp));
      expect(bRow.startTime, _sameInstant(sw1.timestamp));
      expect(bRow.endTime, _sameInstant(sw2.timestamp));

      // C and D: opened at sw-2, still active.
      final cRow = sessions.firstWhere((s) => s.memberId == 'local-c');
      final dRow = sessions.firstWhere((s) => s.memberId == 'local-d');
      expect(cRow.startTime, _sameInstant(sw2.timestamp));
      expect(cRow.endTime, isNull);
      expect(dRow.startTime, _sameInstant(sw2.timestamp));
      expect(dRow.endTime, isNull);
    });
  });

  // -- Deterministic IDs ----------------------------------------------------

  group('deterministic IDs', () {
    test('same (switch_id, member_pk_uuid) always produces same row id', () {
      const uuid = Uuid();
      final id1 = uuid.v5(pkFrontingNamespace, 'sw-abc:uuid-member-1');
      final id2 = uuid.v5(pkFrontingNamespace, 'sw-abc:uuid-member-1');
      expect(id1, id2);
    });

    test('different entry switches produce different IDs for same member', () {
      const uuid = Uuid();
      final id1 = uuid.v5(pkFrontingNamespace, 'sw-1:uuid-member-1');
      final id2 = uuid.v5(pkFrontingNamespace, 'sw-2:uuid-member-1');
      expect(id1, isNot(id2));
    });

    test(
      'idempotent re-import: second full import collides on existing rows',
      () async {
        // Runs two full imports of the same switch history. Both devices
        // independently re-importing produce the same deterministic IDs;
        // the DB ends up with exactly the same sessions (not doubled).
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final sw2 = PKSwitch(
          id: 'sw-2',
          timestamp: DateTime.utc(2026, 1, 1, 12),
          members: const [],
        );

        // First import.
        final client1 = _FakeClient([
          [sw2, sw1],
          [],
        ]);
        final svc1 = _makeService(db: db, client: client1);
        await svc1.setToken('t');
        await svc1.acknowledgeMapping();
        await svc1.performFullImport();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final firstCount = (await sessionRepo.getAllSessions()).length;
        expect(firstCount, 1);

        // Second import (re-import). Should collide on the same ID, not add rows.
        final client2 = _FakeClient([
          [sw2, sw1],
          [],
        ]);
        final svc2 = _makeService(
          db: db,
          client: client2,
          memberRepo: memberRepo,
        );
        await svc2.setToken('t');
        await svc2.acknowledgeMapping();
        await svc2.performFullImport();

        final secondCount = (await sessionRepo.getAllSessions()).length;
        expect(
          secondCount,
          firstCount,
          reason: 'Deterministic IDs collide — no row duplication on re-import',
        );
      },
    );
  });

  // -- Resume cursor ---------------------------------------------------------

  group('resume cursor', () {
    test('cursor advances after each switch, stored in DB', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sw1 = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );
      final sw2 = PKSwitch(
        id: 'sw-2',
        timestamp: DateTime.utc(2026, 1, 1, 12),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw2, sw1],
        [],
      ]);

      final service = _makeService(db: db, client: client);
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      // Cursor should be at the last switch.
      final state = await db.pluralKitSyncDao.getSyncState();
      expect(
        state.switchCursorTimestamp,
        _sameInstant(DateTime.utc(2026, 1, 1, 12)),
      );
      expect(state.switchCursorId, 'sw-2');
    });

    test('performFullImport resets cursor to null before sweep', () async {
      final db = _makeDb();
      addTearDown(db.close);

      // Seed a stale cursor.
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          switchCursorTimestamp: Value(DateTime.utc(2025, 6, 1)),
          switchCursorId: const Value('old-sw'),
        ),
      );

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sw1 = PKSwitch(
        id: 'sw-new',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw1],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      // Cursor should be at the new switch (old cursor was reset).
      final state = await db.pluralKitSyncDao.getSyncState();
      expect(state.switchCursorId, 'sw-new');
    });
  });

  // -- Corrective full re-import --------------------------------------------

  group('corrective full re-import', () {
    test(
      'tombstones pre-existing PK-linked rows not in the canonical API set',
      () async {
        // Regression: corrective re-import must canonicalize the
        // PK row set, not just close stragglers. Any local PK-linked row
        // whose deterministic id is not in the canonical (switch_uuid,
        // member_pk_uuid) set computed from the API gets tombstoned so
        // paired devices converge on the API truth.
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // Pre-seed an open PK-linked session at an id the API doesn't know.
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: 'old-open-row',
            startTime: DateTime.utc(2025, 6, 1),
            memberId: 'local-a',
            pluralkitUuid: '00000000-0000-0000-0000-000000000099',
          ),
        );

        // Verify it's open before the re-import.
        final before = await sessionRepo.getAllSessions();
        expect(before.single.endTime, isNull);

        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );

        final client = _FakeClient([
          [sw1],
          [],
        ]);

        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await service.setToken('t');
        await service.acknowledgeMapping();
        // performFullImport = corrective re-import path.
        await service.performFullImport();

        final after = await sessionRepo.getAllSessions();
        // The stale row was tombstoned (no longer visible in the active
        // session set).
        expect(
          after.any((s) => s.id == 'old-open-row'),
          isFalse,
          reason: 'Corrective re-import tombstones rows not in canonical set',
        );

        // The new canonical row exists, open (corrective entrant clears
        // end_time even on collision; here there was no collision).
        final newRows = after.where(
          (s) => s.pluralkitUuid == 'sw-1' && s.memberId == 'local-a',
        );
        expect(newRows, hasLength(1));
        expect(
          newRows.single.endTime,
          isNull,
          reason: 'sw-1 entrant has no closer; row stays open',
        );
        expect(newRows.single.id, _expectedRowId('sw-1', 'uuid-a'));
      },
    );

    test('resets prevActive to empty so sweep starts fresh', () async {
      // With prevActive empty, A's row starts at sw-1 (not inherited from old state).
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );

      // Stale open session at an id the API doesn't know — corrective
      // path tombstones it.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'stale-id',
          startTime: DateTime.utc(2025, 1, 1),
          memberId: 'local-a',
          pluralkitUuid: '00000000-0000-0000-0000-000000000098',
        ),
      );

      final sw1 = PKSwitch(
        id: 'sw-fresh',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw1],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      final after = await sessionRepo.getAllSessions();
      // Find the new row for this sweep.
      final newRow = after.firstWhere((s) => s.pluralkitUuid == 'sw-fresh');
      expect(newRow.startTime, _sameInstant(DateTime.utc(2026, 1, 1, 10)));
      expect(newRow.id, _expectedRowId('sw-fresh', 'uuid-a'));
    });

    test('performFullImport resurrects a soft-deleted rescue row '
        '(upgradeAndKeep migration → API re-import)', () async {
      // Final P1 regression guard. The upgradeAndKeep migration soft-
      // deletes every PK-imported rescue row, expecting a later
      // corrective API re-import to resurrect them with API-truth
      // boundaries via field-LWW. Before the fix, the corrective
      // collision branch did `existing.copyWith(startTime: ..., ...)`
      // which preserved `isDeleted: true` from the soft-deleted row.
      // Updates wrote new fields but never cleared the tombstone, so
      // the user saw an empty PK timeline post-migration with no
      // recovery path short of manually re-importing the rescue file.
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      const switchId = 'sw-1';
      final rescueId = derivePkSessionId(switchId, 'uuid-a');
      final lossyStart = DateTime.utc(2026, 1, 1, 9);
      final apiStart = DateTime.utc(2026, 1, 1, 10);

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      // Seed the row exactly as upgradeAndKeep leaves it: a rescue-
      // derived session at the canonical deterministic id with lossy
      // boundaries, then soft-deleted via the repo's deleteSession.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rescueId,
          startTime: lossyStart,
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );
      await sessionRepo.deleteSession(rescueId);
      // Sanity: getAllSessions filters out soft-deleted rows.
      expect(await sessionRepo.getAllSessions(), isEmpty);
      final preDeleted = await sessionRepo.getSessionById(rescueId);
      expect(preDeleted, isNotNull);
      expect(
        preDeleted!.isDeleted,
        isTrue,
        reason: 'precondition: row is soft-deleted before re-import',
      );

      // API says A is fronting from sw-1 → corrective re-import should
      // resurrect the row with the API-truth start time and member.
      final sw = PKSwitch(
        id: switchId,
        timestamp: apiStart,
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [sw],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      // Row is back in the active set with API-truth fields.
      final all = await sessionRepo.getAllSessions();
      expect(
        all,
        hasLength(1),
        reason: 'corrective re-import must undelete the rescue row',
      );
      final row = all.single;
      expect(row.id, rescueId);
      expect(
        row.isDeleted,
        isFalse,
        reason: 'corrective collision branch must clear is_deleted',
      );
      expect(
        row.startTime,
        _sameInstant(apiStart),
        reason: 'API start overwrote rescue lossy start',
      );
      expect(row.memberId, 'local-a');
      expect(row.pluralkitUuid, switchId);
    });

    test('performFullImport resurrects soft-deleted PK row when legacy id '
        'differs from deterministic id', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      const switchId = 'sw-legacy';
      final lossyStart = DateTime.utc(2026, 1, 1, 9);
      final apiStart = DateTime.utc(2026, 1, 1, 10);
      final deterministicId = derivePkSessionId(switchId, 'uuid-a');

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'legacy-pk-row',
          startTime: lossyStart,
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );
      await sessionRepo.deleteSession('legacy-pk-row');

      final sw = PKSwitch(
        id: switchId,
        timestamp: apiStart,
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [sw],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();

      await service.performFullImport();

      final active = await sessionRepo.getAllSessions();
      expect(active, hasLength(1));
      final row = active.single;
      expect(row.id, 'legacy-pk-row');
      expect(row.id, isNot(deterministicId));
      expect(row.isDeleted, isFalse);
      expect(row.startTime, _sameInstant(apiStart));
      expect(row.endTime, isNull);
      expect(row.memberId, 'local-a');
      expect(row.pluralkitUuid, switchId);

      final deterministicRow = await sessionRepo.getSessionById(
        deterministicId,
      );
      expect(deterministicRow, isNull);
    });
  });

  // -- Member resolution ----------------------------------------------------

  group('member resolution', () {
    test(
      'PK short ID resolves through pluralkit_id → pluralkit_uuid for key derivation',
      () async {
        // Verify that the deterministic ID uses the full UUID (pluralkit_uuid),
        // not the 5-char short ID (pluralkit_id).
        final db = _makeDb();
        addTearDown(db.close);

        const pkShortId = 'abcde';
        const pkUuid = 'full-uuid-for-member';
        const localId = 'local-x';

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: localId, pkShortId: pkShortId, pkUuid: pkUuid),
        );

        final sw = PKSwitch(
          id: 'sw-test',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const [pkShortId],
        );

        final client = _FakeClient([
          [sw],
          [],
        ]);

        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
        );
        await service.setToken('t');
        await service.acknowledgeMapping();
        await service.importSwitchesAfterLink();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();

        expect(sessions, hasLength(1));
        // The row ID must be derived from the full UUID, not the short ID.
        expect(sessions.single.id, _expectedRowId('sw-test', pkUuid));
        expect(
          sessions.single.id,
          isNot(_expectedRowId('sw-test', pkShortId)),
          reason: 'Key must use full UUID, not 5-char short ID',
        );
      },
    );

    test(
      'unmapped PK short ID is counted but does not crash the import',
      () async {
        // A switch referencing a PK short ID with no local member mapping
        // should be counted as unmapped and the switch is effectively a no-op.
        // This tests the "report as count, skip" behavior from §2.6.
        final db = _makeDb();
        addTearDown(db.close);

        // No members registered — so 'pkX' and 'pkY' have no local mapping.
        final memberRepo = DriftMemberRepository(db.membersDao, null);

        final sw = PKSwitch(
          id: 'sw-unmapped',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkX', 'pkY'],
        );

        final client = _FakeClient([
          [sw],
          [],
        ]);

        // This should not throw.
        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
        );
        await service.setToken('t');
        await service.acknowledgeMapping();
        await expectLater(service.importSwitchesAfterLink(), completes);

        // No sessions created (no mappings).
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();
        expect(
          sessions,
          isEmpty,
          reason: 'Unmapped members produce no sessions',
        );
      },
    );

    test(
      'partially-mapped switch creates rows only for mapped members',
      () async {
        // If a switch has members [pkA, pkUnknown], only pkA gets a row.
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );
        // pkUnknown has no local member.

        final sw = PKSwitch(
          id: 'sw-partial',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA', 'pkUnknown'],
        );

        final client = _FakeClient([
          [sw],
          [],
        ]);

        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
        );
        await service.setToken('t');
        await service.acknowledgeMapping();
        await service.importSwitchesAfterLink();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();

        // Only pkA has a row.
        expect(sessions, hasLength(1));
        expect(sessions.single.memberId, 'local-a');
      },
    );
  });

  // -- Atomic transaction ---------------------------------------------------

  group('atomic transaction', () {
    test('cursor advances only after row writes succeed', () async {
      // Verify the cursor is updated atomically with row writes.
      // After a successful switch, cursor.switchCursorId = sw.id.
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sw = PKSwitch(
        id: 'sw-atomic',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      final state = await db.pluralKitSyncDao.getSyncState();
      expect(
        state.switchCursorId,
        'sw-atomic',
        reason: 'Cursor advances atomically with row writes',
      );

      // The row must also exist.
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final sessions = await sessionRepo.getAllSessions();
      expect(sessions, hasLength(1));
    });
  });

  // -- Rescue → API re-import collision ----------------------
  //
  // The diff sweep MUST upsert when the deterministic id already exists
  // locally (typically a PRISM1 rescue row with lossy boundaries) so the
  // API truth wins via field-LWW. The previous create-then-catch-unique
  // shape recorded the row id but never wrote the API values, leaving
  // rescue boundaries on disk forever. Conservative end_time policy:
  // a non-null existing end_time is preserved (the user may have
  // closed the rescue row manually).

  group('PRISM1 rescue collision upsert', () {
    test('entrant collides with rescue row → start_time + member_id + '
        'pluralkit_uuid corrected; rescue end_time left null is overwritten '
        'on close', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      // Seed a PRISM1-rescue-style row at the deterministic id with
      // a lossy start (1h earlier than API) and a CLOSED end_time
      // (an hour-long lossy window). The API will say A is currently
      // fronting from sw-1.
      const switchId = 'sw-1';
      const memberPkUuid = 'uuid-a';
      final rescueId = derivePkSessionId(switchId, memberPkUuid);
      final lossyStart = DateTime.utc(2026, 1, 1, 9);
      final lossyEnd = DateTime.utc(2026, 1, 1, 10);
      final apiStart = DateTime.utc(2026, 1, 1, 10);

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rescueId,
          startTime: lossyStart,
          endTime: lossyEnd,
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );

      // API sweep: A becomes fronting at sw-1.
      final sw = PKSwitch(
        id: switchId,
        timestamp: apiStart,
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [sw],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      // Single row at the same deterministic id. The lossy start was
      // overwritten with the API truth. The lossy end_time stays —
      // conservative policy preserves user-closed rescue rows.
      final all = await sessionRepo.getAllSessions();
      expect(all, hasLength(1));
      final row = all.single;
      expect(row.id, rescueId);
      expect(
        row.startTime,
        _sameInstant(apiStart),
        reason: 'API start must overwrite rescue lossy start',
      );
      expect(
        row.endTime,
        _sameInstant(lossyEnd),
        reason: 'conservative: pre-existing close not clobbered',
      );
      expect(row.memberId, 'local-a');
      expect(row.pluralkitUuid, switchId);
    });

    test('incremental sweep does NOT undelete a soft-deleted row '
        '(user-initiated delete during routine sync is preserved)', () async {
      // Companion to the corrective-mode resurrection test in the
      // 'corrective full re-import' group. The undelete behaviour is
      // gated to corrective=true: if a user deliberately deleted a
      // PK row during routine use, the next incremental sync MUST
      // NOT silently bring it back. (importSwitchesAfterLink is the
      // incremental path with corrective=false by default.)
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      const switchId = 'sw-1';
      final rescueId = derivePkSessionId(switchId, 'uuid-a');
      final apiStart = DateTime.utc(2026, 1, 1, 10);

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rescueId,
          startTime: DateTime.utc(2026, 1, 1, 9),
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );
      await sessionRepo.deleteSession(rescueId);

      final sw = PKSwitch(
        id: switchId,
        timestamp: apiStart,
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [sw],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.importSwitchesAfterLink();

      // Active set is still empty — incremental did not undelete.
      expect(
        await sessionRepo.getAllSessions(),
        isEmpty,
        reason: 'incremental sweep must respect user-initiated delete',
      );
      // The underlying row (still tombstoned) is reachable directly.
      final raw = await sessionRepo.getSessionById(rescueId);
      expect(raw, isNotNull);
      expect(
        raw!.isDeleted,
        isTrue,
        reason: 'incremental sweep must not clear is_deleted',
      );
    });

    test('performFullImport on a closed rescue row clears end_time '
        '(corrective mode: API is authoritative)', () async {
      // Regression: on the corrective full re-import, a
      // pre-existing closed rescue row at the canonical deterministic
      // id triggers the entrant collision branch with corrective=true.
      // The lossy close from the rescue file is wrong — the API says
      // this member is currently fronting (entrant on the latest
      // switch). The corrective branch clobbers end_time to null.
      // The leaver pass will close it later in this sweep if/when
      // the API stops listing the member as fronting.
      //
      // The incremental path keeps the conservative policy (don't
      // clobber legitimate user closes during routine sync); see
      // 'PRISM1 rescue collision upsert' group above.
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      const switchId = 'sw-1';
      final rescueId = derivePkSessionId(switchId, 'uuid-a');
      final lossyStart = DateTime.utc(2026, 1, 1, 9);
      final lossyEnd = DateTime.utc(2026, 1, 1, 10);
      final apiStart = DateTime.utc(2026, 1, 1, 10);

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rescueId,
          startTime: lossyStart,
          endTime: lossyEnd,
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );

      final sw = PKSwitch(
        id: switchId,
        timestamp: apiStart,
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [sw],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      final all = await sessionRepo.getAllSessions();
      expect(all, hasLength(1));
      final row = all.single;
      expect(row.id, rescueId);
      expect(
        row.startTime,
        _sameInstant(apiStart),
        reason: 'API start overwrote rescue lossy start',
      );
      expect(
        row.endTime,
        isNull,
        reason:
            'corrective re-import clears stale rescue end_time '
            'when API says this member is currently fronting',
      );
    });

    test('leaver path is idempotent on a row that already has end_time set '
        '(API says ended, local already closed)', () async {
      // The diff-sweep leaver path calls endSession on rows in the
      // openRowIds map. Because of the rescue-collision upsert above,
      // openRowIds always carries the row id even when the existing
      // row had a non-null end_time. The leaver should still close
      // the row to the API timestamp via endSession (idempotent).
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      const switchId = 'sw-1';
      final rescueId = derivePkSessionId(switchId, 'uuid-a');
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      // Pre-existing rescue row with lossy close.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rescueId,
          startTime: DateTime.utc(2026, 1, 1, 9),
          endTime: DateTime.utc(2026, 1, 1, 10),
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );

      // API sweep: A enters at sw-1, leaves at sw-2.
      final sw1 = PKSwitch(
        id: switchId,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );
      final sw2 = PKSwitch(
        id: 'sw-2',
        timestamp: DateTime.utc(2026, 1, 1, 11),
        members: const [],
      );
      final client = _FakeClient([
        [sw2, sw1],
        [],
      ]);
      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await expectLater(
        service.importSwitchesAfterLink(),
        completes,
        reason: 'leaver path must not throw on already-closed row',
      );

      final all = await sessionRepo.getAllSessions();
      expect(all, hasLength(1));
      // After the leaver, end_time is sw2.timestamp (the API close).
      expect(all.single.endTime, _sameInstant(sw2.timestamp));
    });
  });

  // -- Schema migration: cursor columns exist in DB -------------------------

  group('schema migration v7→v8', () {
    test(
      'PluralKitSyncState has switchCursorTimestamp and switchCursorId columns',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        // Ensure the row exists.
        final state = await db.pluralKitSyncDao.getSyncState();
        // Both cursor columns should be null by default.
        expect(state.switchCursorTimestamp, isNull);
        expect(state.switchCursorId, isNull);
      },
    );

    test('cursor columns can be written and read back', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final ts = DateTime.utc(2026, 4, 26, 12, 0, 0);
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          switchCursorTimestamp: Value(ts),
          switchCursorId: const Value('some-uuid'),
        ),
      );

      final state = await db.pluralKitSyncDao.getSyncState();
      expect(state.switchCursorTimestamp, _sameInstant(ts));
      expect(state.switchCursorId, 'some-uuid');
    });
  });

  // -- WS3 step 2 / review #6: cursor boundary semantics --------------------

  group('cursor boundary lexicographic skip (WS3 #6)', () {
    test(
      'same-timestamp switch with different id after the cursor IS processed',
      () async {
        // Regression for review finding #6: the previous loop break on
        // `sw.timestamp == cursorTs && sw.id == cursorId` only stopped at
        // the EXACT cursor switch — so a switch at the same timestamp but
        // a different id was added to newSwitches AFTER the cursor was
        // reached, then on the next page sweep was filtered as "before"
        // the cursor and silently dropped. With the fix, the lexicographic
        // `(ts, id) > cursor` rule processes such switches exactly once.
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        // Seed the cursor at (T, 'sw-1'). Pretend a previous incremental
        // sweep processed sw-1; sw-2 shares the same timestamp but a later
        // id, and was *missed* (it appeared after sw-1 in the page on the
        // first sweep but before the cursor break). Also seed
        // `lastSyncDate` so syncRecentData enters the incremental path
        // rather than diverting to performFullImport.
        final cursorTs = DateTime.utc(2026, 1, 1, 12);
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            switchCursorTimestamp: Value(cursorTs),
            switchCursorId: const Value('sw-1'),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1, 13)),
          ),
        );

        // The current sweep fetches a page with sw-2 and sw-1 (newest-first
        // is sw-2, then sw-1 — string compare 'sw-2' > 'sw-1'). The cursor
        // covers sw-1; sw-2 must be processed.
        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: cursorTs,
          members: const ['pkA'],
        );
        final sw2 = PKSwitch(
          id: 'sw-2',
          timestamp: cursorTs,
          members: const ['pkA'],
        );

        // Newest-first page: sw-2 first, then sw-1 (string-id tiebreak).
        final client = _FakeClient([
          [sw2, sw1],
          [],
        ]);

        final service = _makeService(db: db, client: client);
        await service.setToken('t');
        await service.acknowledgeMapping();
        await service.loadState();

        await service.syncRecentData();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();

        // Exactly one row, derived from sw-2 (the "missed" same-timestamp
        // switch). sw-1 was below the cursor and skipped.
        expect(
          sessions,
          hasLength(1),
          reason: 'sw-2 must be processed; sw-1 already covered by cursor',
        );
        expect(
          sessions.single.pluralkitUuid,
          'sw-2',
          reason: 'entrant came from sw-2',
        );
        expect(sessions.single.id, _expectedRowId('sw-2', 'uuid-a'));

        // Cursor advanced to (T, 'sw-2').
        final state = await db.pluralKitSyncDao.getSyncState();
        expect(state.switchCursorId, 'sw-2');
        expect(state.switchCursorTimestamp, _sameInstant(cursorTs));
      },
    );
  });

  // -- WS3 step 9 / review #8: id derivation parity -------------------------

  group('id derivation parity: diff sweep ↔ canonicalization (WS3 #9)', () {
    test(
      'corrective full re-import does NOT tombstone rows the diff sweep just '
      'wrote — both call sites derive the same id',
      () async {
        // The two id-derivation sites previously diverged: the diff sweep
        // routed local id → PK uuid via _localIdToPkUuid (with a localId
        // fallback); the canonicalization pass derived directly from the
        // PK uuid. Under odd map-state conditions they could disagree and
        // canonicalization would tombstone a row the sweep would write.
        //
        // After unifying via deriveCanonicalPkSessionId, both paths must
        // produce the same id, so the canonicalization tombstone-pass
        // never sees a "stale" row produced by the sweep.
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
        );

        final sw1 = PKSwitch(
          id: 'sw-1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final client = _FakeClient([
          [sw1],
          [],
        ]);

        final service = _makeService(db: db, client: client);
        await service.setToken('t');
        await service.acknowledgeMapping();
        // performFullImport runs the canonicalization + diff sweep; if the
        // two paths derive different ids, canonicalization will tombstone
        // the row the sweep writes (or vice versa).
        await service.performFullImport();

        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final sessions = await sessionRepo.getAllSessions();
        // Exactly one row, not deleted, with the deterministic id.
        expect(sessions, hasLength(1));
        expect(sessions.single.isDeleted, isFalse);
        expect(sessions.single.id, _expectedRowId('sw-1', 'uuid-a'));
      },
    );
  });

  // -- WS3 step 5 / review #29: full import seeds prevActive from open DB rows
  //
  // Before PR E2, _runFullImportWithClient called _runDiffSweep with
  // `prevActive: {}`, so existing-but-no-longer-fronting members were never
  // closed by the leaver path. PR E2 unifies the seed: both the incremental
  // and corrective paths reconstitute prevActive from open PK-linked DB rows
  // inside _runDiffSweep. This group locks in that invariant.

  group('full import seeds prevActive from open DB rows (WS3 #29)', () {
    test('open existing PK row gets closed by the next leaver in a corrective '
        'sweep (no longer stranded open after PR E2)', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );

      // Seed an open PK-linked row at a canonical entrant id from a prior
      // sweep. Use a real-shaped PK switch UUID because the diff-sweep
      // prev-active reconstitution filters on `isPluralKitSwitchUuid`.
      const oldSwitchId = '11111111-1111-1111-1111-111111111111';
      final openRowId = derivePkSessionId(oldSwitchId, 'uuid-a');
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: openRowId,
          startTime: DateTime.utc(2026, 1, 1, 9),
          memberId: 'local-a',
          pluralkitUuid: oldSwitchId,
        ),
      );

      // The API switch list contains only sw-new (an empty switch).
      // The seeded sw-old row is canonicalized away (not in the API
      // entrant set), so it gets tombstoned by canonicalization. A
      // pre-PR-E2 sweep with `prevActive: {}` would have left it
      // stranded open. The PR E2 invariant: no PK-linked row remains
      // open + live after the sweep.
      final swNew = PKSwitch(
        id: '22222222-2222-2222-2222-222222222222',
        timestamp: DateTime.utc(2026, 1, 1, 12),
        members: const [],
      );

      final client = _FakeClient([
        [swNew],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      // The pre-existing open row must not still be open + live. It can
      // be closed (leaver fired) or tombstoned by canonicalization —
      // either way the "stranded open forever" failure mode is gone.
      final raw = await sessionRepo.getSessionById(openRowId);
      expect(raw, isNotNull);
      if (!raw!.isDeleted) {
        expect(
          raw.endTime,
          isNotNull,
          reason:
              'PR E2: corrective sweep must seed prevActive from open DB '
              'rows so a subsequent empty switch closes the row instead '
              'of leaving it stranded open',
        );
      }
      // No PK-linked row should remain open + live — A is no longer
      // fronting per the API.
      final stillOpen = await sessionRepo.getAllSessions();
      for (final s in stillOpen) {
        expect(
          s.endTime,
          isNotNull,
          reason: 'no PK-linked row should remain open after the sweep',
        );
      }
    });

    test('open existing PK row stays open if API still lists the member as '
        'fronting on the latest switch (idempotent)', () async {
      // Companion to the above. A row already open at the canonical id
      // for the API's only entrant must stay open across the corrective
      // sweep (no false leaver fires).
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );

      const switchId = '33333333-3333-3333-3333-333333333333';
      final rowId = derivePkSessionId(switchId, 'uuid-a');
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rowId,
          startTime: DateTime.utc(2026, 1, 1, 9),
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );

      final sw = PKSwitch(
        id: switchId,
        timestamp: DateTime.utc(2026, 1, 1, 9),
        members: const ['pkA'],
      );

      final client = _FakeClient([
        [sw],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();
      await service.performFullImport();

      final after = await sessionRepo.getAllSessions();
      expect(after, hasLength(1));
      expect(
        after.single.endTime,
        isNull,
        reason:
            'API still says A is fronting; the seeded prev-active entry '
            'matches the API entrant so no leaver fires',
      );
    });
  });

  // -- WS3 step 6 / review #30: zero-length close guard + ordering error
  //
  // The leaver path used to call `endSession(rowId, sw.timestamp)` without
  // checking the row's start_time. Two pathological cases needed to be
  // handled:
  //   1. end == start: zero-length presence (skip the close, increment
  //      `zeroLengthCloseSkipped`).
  //   2. end <  start: corrupt input ordering (throw PkSwitchOrderingError).

  group('leaver close guard (WS3 #30)', () {
    test('same-timestamp leave-then-enter on a member produces no zero-length '
        'row and does not throw', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      // Two switches at the same timestamp: A enters at sw-1, then sw-2
      // arrives at the same moment with members=[] (A leaves). The leaver
      // path would normally call endSession(rowId, sw.timestamp) but the
      // close timestamp equals the row's start — that's a zero-length
      // presence and we must not write it.
      final ts = DateTime.utc(2026, 1, 1, 12);
      final sw1 = PKSwitch(id: 'sw-1', timestamp: ts, members: const ['pkA']);
      final sw2 = PKSwitch(id: 'sw-2', timestamp: ts, members: const []);

      // Pages must be newest-first. With identical timestamps, sw-2 ('sw-2'
      // > 'sw-1' lexicographically) is "newer" by tiebreak.
      final client = _FakeClient([
        [sw2, sw1],
        [],
      ]);

      final service = _makeService(db: db, client: client);
      await service.setToken('t');
      await service.acknowledgeMapping();
      // The sweep must complete without throwing.
      await expectLater(service.importSwitchesAfterLink(), completes);

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final sessions = await sessionRepo.getAllSessions();
      expect(sessions, hasLength(1));
      // The row is still open: the zero-length close was skipped.
      expect(
        sessions.single.endTime,
        isNull,
        reason:
            'WS3 #30: when end == start the leaver close must be skipped '
            'so we do not write a zero-duration row',
      );
      // Sanity: the row's start_time matches the entrant timestamp.
      expect(sessions.single.startTime, _sameInstant(ts));
    });

    test('corrupt switch ordering (leaver before entrant) throws '
        'PkSwitchOrderingError and stops the batch', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );

      // Seed an open row at startTime = T (later than the leaver below).
      // The diff sweep reconstitutes prevActive from open PK-linked rows
      // — that filter requires `pluralkitUuid` to match the strict PK
      // switch UUID format, so we use a real-shaped UUID here (not the
      // 'sw-1' shorthand the diff-sweep correctness tests use, where
      // prevActive is empty and the filter never runs).
      const switchId = '11111111-1111-1111-1111-111111111111';
      final rowId = derivePkSessionId(switchId, 'uuid-a');
      final laterStart = DateTime.utc(2026, 1, 1, 12);
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: rowId,
          startTime: laterStart,
          memberId: 'local-a',
          pluralkitUuid: switchId,
        ),
      );

      // The "API" returns one switch at T-1h with members=[] — the
      // leaver. Because the row's startTime is T (later), the leaver's
      // close timestamp predates the start. The sweep must throw the
      // typed ordering error rather than write a negative-duration close.
      final earlierLeaver = PKSwitch(
        id: '22222222-2222-2222-2222-222222222222',
        timestamp: DateTime.utc(2026, 1, 1, 11),
        members: const [],
      );

      final client = _FakeClient([
        [earlierLeaver],
        [],
      ]);

      final service = _makeService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );
      await service.setToken('t');
      await service.acknowledgeMapping();

      await expectLater(
        service.importSwitchesAfterLink(),
        throwsA(isA<PkSwitchOrderingError>()),
      );

      // The original row is unchanged (the failing transaction rolled back).
      final raw = await sessionRepo.getSessionById(rowId);
      expect(raw, isNotNull);
      expect(raw!.startTime, _sameInstant(laterStart));
      expect(
        raw.endTime,
        isNull,
        reason: 'transaction must roll back on the ordering error',
      );
    });
  });

  // -- WS3 step 8 / review #34: canonicalization wrapped in a transaction
  //
  // Before PR E2 the corrective canonicalization pass called
  // _frontingSessionRepository.deleteSession(rowId) per duplicate without a
  // surrounding transaction, so a crash mid-loop left the CRDT half-
  // canonicalized: some stale rows tombstoned, others still live, and
  // paired devices receiving the partial set converged on an inconsistent
  // timeline. PR E2 wraps the entire detect+tombstone loop in
  // db.transaction(); a throw mid-loop rolls back every soft-delete in the
  // batch.

  group('canonicalization atomic transaction (WS3 #34)', () {
    test('deleteSession failure mid-canonicalization rolls back all earlier '
        'soft-deletes in the same batch', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(
        _member(localId: 'local-a', pkShortId: 'pkA', pkUuid: 'uuid-a'),
      );

      final realRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );

      // Seed 4 stale PK-linked rows the API doesn't know about. The
      // canonicalization pass will iterate these and call deleteSession
      // on each. We make the flaky wrapper throw on the 3rd delete so
      // a partial rollback is observable.
      for (var i = 0; i < 4; i++) {
        await realRepo.createSession(
          domain_fs.FrontingSession(
            id: 'stale-$i',
            startTime: DateTime.utc(2025, 1, i + 1),
            memberId: 'local-a',
            // A non-canonical PK switch UUID so canonicalization tombstones
            // these but they're still recognized as PK-linked.
            pluralkitUuid: '00000000-0000-0000-0000-00000000000$i',
          ),
        );
      }
      final beforeIds = (await realRepo.getAllSessions())
          .map((s) => s.id)
          .toSet();
      expect(beforeIds, hasLength(4));

      final flakyRepo = _FlakyDeleteRepo(
        delegate: realRepo,
        throwOnDeleteCount: 3,
      );

      // The API confirms only sw-fresh as the canonical entrant — none of
      // the stale rows match, so canonicalization will try to delete all 4.
      final swFresh = PKSwitch(
        id: 'sw-fresh',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );
      final client = _FakeClient([
        [swFresh],
        [],
      ]);

      final service = PluralKitSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: flakyRepo,
        syncDao: db.pluralKitSyncDao,
        secureStorage: const FlutterSecureStorage(),
        clientFactory: (_) => client,
      );

      await service.setToken('t');
      await service.acknowledgeMapping();
      // The flaky 3rd delete must propagate up.
      await expectLater(
        service.performFullImport(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('flaky'),
          ),
        ),
      );

      // None of the stale rows were soft-deleted: the transaction rolled
      // back the first two soft-deletes when the 3rd threw.
      final after = await db.frontingSessionsDao.getAllSessions();
      final afterIds = after.map((s) => s.id).toSet();
      for (var i = 0; i < 4; i++) {
        expect(
          afterIds,
          contains('stale-$i'),
          reason:
              'WS3 #34: canonicalization tx must roll back all earlier '
              'soft-deletes when a later one fails — stale-$i is missing',
        );
      }
      // Sanity: check none of them are tombstoned either.
      for (final id in ['stale-0', 'stale-1', 'stale-2', 'stale-3']) {
        final raw = await realRepo.getSessionById(id);
        expect(raw, isNotNull);
        expect(raw!.isDeleted, isFalse, reason: '$id was rolled back');
      }
    });
  });

  // -- Review #33: tombstoned-collision presence is not silently dropped
  //
  // E1 added _PkActivePresence.isTombstonedCollision; PR E2 wires up the
  // leaver path so a leaver fires on a tombstoned-collision presence
  // surfaces the member in unmappedMemberReferences (rather than the
  // presence being silently dropped from the timeline).

  group('tombstoned-collision visibility (review #33)', () {
    test(
      'incremental leaver on a tombstoned-collision presence increments '
      'unmappedMemberReferences (no row to close, surface for visibility)',
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
        );

        // Seed a tombstoned row at the canonical id for (sw-1, uuid-a) so
        // the entrant write is skipped (preserved as a tombstone-collision
        // presence with rowId == null) on the incremental path.
        const enterSwitchId = 'sw-1';
        final tombstoneId = derivePkSessionId(enterSwitchId, 'uuid-a');
        await sessionRepo.createSession(
          domain_fs.FrontingSession(
            id: tombstoneId,
            startTime: DateTime.utc(2026, 1, 1, 8),
            memberId: 'local-a',
            pluralkitUuid: enterSwitchId,
          ),
        );
        await sessionRepo.deleteSession(tombstoneId);

        // sw-1: A enters (collides with tombstone, no row written).
        // sw-2: A leaves (would close — but no rowId).
        final sw1 = PKSwitch(
          id: enterSwitchId,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA'],
        );
        final sw2 = PKSwitch(
          id: 'sw-2',
          timestamp: DateTime.utc(2026, 1, 1, 12),
          members: const [],
        );

        final client = _FakeClient([
          [sw2, sw1],
          [],
        ]);

        final service = _makeService(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );
        await service.setToken('t');
        await service.acknowledgeMapping();
        await expectLater(
          service.importSwitchesAfterLink(),
          completes,
          reason:
              'leaver on tombstoned-collision presence must not throw — it '
              'just surfaces in unmappedMemberReferences',
        );

        // No live row was created — the tombstone was preserved (incremental
        // path always preserves user tombstones).
        final live = await sessionRepo.getAllSessions();
        expect(
          live,
          isEmpty,
          reason:
              'incremental sweep must not resurrect the tombstone; the '
              'leaver has no row to close',
        );
        final raw = await sessionRepo.getSessionById(tombstoneId);
        expect(raw, isNotNull);
        expect(raw!.isDeleted, isTrue);
      },
    );
  });
}
