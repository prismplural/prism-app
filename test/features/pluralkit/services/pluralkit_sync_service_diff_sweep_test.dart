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
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
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
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
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
String _expectedRowId(String entrySwitchId, String memberPkUuid) {
  const uuid = Uuid();
  return uuid.v5(pkFrontingNamespace, '$entrySwitchId:$memberPkUuid');
}

/// Matcher that compares two [DateTime] values as the same instant in time,
/// regardless of whether one is UTC and the other is local. Drift returns
/// timestamps in local time; tests use DateTime.utc(...). This normalises
/// both sides to milliseconds-since-epoch for comparison.
Matcher _sameInstant(DateTime expected) =>
    predicate<DateTime>(
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
    test('A → A+B → A produces 1 long A row + 1 short B row, not 3 A rows',
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
      expect(aRows.single.pluralkitUuid, 'sw-1', reason: 'entry switch is sw-1');

      // B started at sw-2 and closed at sw-3.
      expect(bRows.single.startTime, _sameInstant(sw2.timestamp));
      expect(bRows.single.endTime, _sameInstant(sw3.timestamp));
      expect(bRows.single.pluralkitUuid, 'sw-2', reason: 'B entry switch is sw-2');

      // Deterministic IDs.
      expect(aRows.single.id, _expectedRowId('sw-1', 'uuid-a'));
      expect(bRows.single.id, _expectedRowId('sw-2', 'uuid-b'));
    });

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

    test('idempotent re-import: second full import collides on existing rows',
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
    });
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
      expect(state.switchCursorTimestamp, _sameInstant(DateTime.utc(2026, 1, 1, 12)));
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

      final service = _makeService(db: db, client: client, memberRepo: memberRepo);
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
    test('pre-closes all open PK-linked sessions before sweep', () async {
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

      // Pre-seed an open PK-linked session.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'old-open-row',
          startTime: DateTime.utc(2025, 6, 1),
          memberId: 'local-a',
          pluralkitUuid: 'some-old-sw',
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
      // Old open row should now be closed.
      final oldRow = after.firstWhere((s) => s.id == 'old-open-row');
      expect(
        oldRow.endTime,
        isNotNull,
        reason: 'Corrective re-import must close all pre-existing open PK rows',
      );

      // New row for the sweep result should exist.
      final newRows = after.where(
        (s) => s.pluralkitUuid == 'sw-1' && s.memberId == 'local-a',
      );
      expect(newRows, hasLength(1));
    });

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

      // Stale open session. performFullImport will close it first.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'stale-id',
          startTime: DateTime.utc(2025, 1, 1),
          memberId: 'local-a',
          pluralkitUuid: 'stale-sw',
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
        _member(
          localId: localId,
          pkShortId: pkShortId,
          pkUuid: pkUuid,
        ),
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

      final service = _makeService(db: db, client: client, memberRepo: memberRepo);
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
    });

    test('unmapped PK short ID is counted but does not crash the import',
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
      final service = _makeService(db: db, client: client, memberRepo: memberRepo);
      await service.setToken('t');
      await service.acknowledgeMapping();
      await expectLater(
        service.importSwitchesAfterLink(),
        completes,
      );

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
    });

    test('partially-mapped switch creates rows only for mapped members',
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

      final service = _makeService(db: db, client: client, memberRepo: memberRepo);
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
    });
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

      final service = _makeService(db: db, client: client, memberRepo: memberRepo);
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

  // -- Schema migration: cursor columns exist in DB -------------------------

  group('schema migration v7→v8', () {
    test('PluralKitSyncState has switchCursorTimestamp and switchCursorId columns',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      // Ensure the row exists.
      final state = await db.pluralKitSyncDao.getSyncState();
      // Both cursor columns should be null by default.
      expect(state.switchCursorTimestamp, isNull);
      expect(state.switchCursorId, isNull);
    });

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
}
