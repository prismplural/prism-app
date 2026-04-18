// Plan 02 — PK deletion push integration tests.
//
// Exercises [PluralKitSyncService.syncRecentData] end-to-end with fake repos
// that track the R3 "clear pluralkit link" call, fake PluralKitClient that
// records DELETE calls, and a real Drift [PluralKitSyncDao] for
// link_epoch / sync_state persistence.
//
// Scenarios:
//   A — basic: one tombstoned linked member + session → both DELETEs happen.
//   B — idempotent rerun: a second syncRecentData emits zero DELETEs.
//   C — 404 swallowed: client returns 404 → still counted as success, link
//       cleared.
//   D — push-disabled then enabled: no DELETE under pullOnly; replayed once
//       direction flips to bidirectional.
//   R1 — connect to a different system → epoch bumps → older tombstones do
//       NOT emit DELETE.
//   R2 — CRDT-style resurrection: fresh re-read finds isDeleted=false →
//       abort.
//   R5 — live local session still references PK on the member → member
//       DELETE skipped with a user-facing message.
//   R3 — successful DELETE clears the local pluralkit link (observed via
//       fake repo hook).

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
// Secure-storage mock (keyed the same as phase4 fake)
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
// Fake PluralKitClient
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  final String systemId;
  final List<String> deletedMembers = [];
  final List<String> deletedSwitches = [];
  /// Status to return from deleteMember/deleteSwitch. `null` = 204 success.
  int? memberDeleteStatus;
  int? switchDeleteStatus;

  // ignore: unused_element_parameter
  _FakeClient({this.systemId = 'sys-1'});

  @override
  Future<PKSystem> getSystem() async => PKSystem(id: systemId, name: 'Test');

  @override
  Future<void> deleteMember(String id) async {
    deletedMembers.add(id);
    final status = memberDeleteStatus;
    if (status != null) {
      throw PluralKitApiError(status, 'err');
    }
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    deletedSwitches.add(switchId);
    final status = switchDeleteStatus;
    if (status != null) {
      throw PluralKitApiError(status, 'err');
    }
  }

  // -- unused-but-required stubs --------------------------------------------
  @override
  Future<List<PKMember>> getMembers() async => const [];
  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches(
          {DateTime? before, int limit = 100}) async =>
      const [];
  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
          {DateTime? timestamp}) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitch(String switchId,
          {required DateTime timestamp}) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(
          String switchId, List<String> memberIds) =>
      throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) async => const [];
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Fake repos with deletion-path support
// ---------------------------------------------------------------------------

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> members = {};
  final List<String> linkCleared = [];
  final List<String> stampedPushStart = [];

  void seed(List<domain.Member> ms) {
    for (final m in ms) {
      members[m.id] = m;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      members.values.where((m) => !m.isDeleted).toList();
  @override
  Future<domain.Member?> getMemberById(String id) async => members[id];
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async => ids
      .map((id) => members[id])
      .whereType<domain.Member>()
      .toList();
  @override
  Future<void> createMember(domain.Member m) async => members[m.id] = m;
  @override
  Future<void> updateMember(domain.Member m) async => members[m.id] = m;
  @override
  Future<void> deleteMember(String id) async {
    final m = members[id];
    if (m != null) members[id] = m.copyWith(isDeleted: true);
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
  Future<int> getCount() async => members.length;

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => members.values
      .where((m) =>
          m.isDeleted && m.pluralkitId != null && m.deleteIntentEpoch != null)
      .toList();

  @override
  Future<void> clearPluralKitLink(String id) async {
    linkCleared.add(id);
    final m = members[id];
    if (m != null) {
      members[id] = m.copyWith(pluralkitId: null, pluralkitUuid: null);
    }
  }

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {
    stampedPushStart.add(id);
    final m = members[id];
    if (m != null) {
      members[id] = m.copyWith(deletePushStartedAt: timestampMs);
    }
  }
}

class _FakeSessionRepo implements FrontingSessionRepository {
  final List<domain.FrontingSession> sessions = [];
  final List<String> linkCleared = [];
  final List<String> stampedPushStart = [];

  @override
  Future<List<domain.FrontingSession>> getAllSessions() async =>
      sessions.where((s) => !s.isDeleted).toList();
  @override
  Future<void> createSession(domain.FrontingSession s) async => sessions.add(s);
  @override
  Future<void> updateSession(domain.FrontingSession s) async {
    final i = sessions.indexWhere((x) => x.id == s.id);
    if (i >= 0) sessions[i] = s;
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    final i = sessions.indexWhere((s) => s.id == id);
    if (i >= 0) sessions[i] = sessions[i].copyWith(endTime: endTime);
  }

  @override
  Future<void> deleteSession(String id) async {
    final i = sessions.indexWhere((s) => s.id == id);
    if (i >= 0) sessions[i] = sessions[i].copyWith(isDeleted: true);
  }

  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async =>
      sessions.where((s) => s.isActive && !s.isSleep && !s.isDeleted).toList();
  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      sessions.where((s) => s.isActive && !s.isDeleted).toList();
  @override
  Future<domain.FrontingSession?> getActiveSession() async {
    for (final s in sessions) {
      if (s.isActive && !s.isSleep && !s.isDeleted) return s;
    }
    return null;
  }

  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async =>
      sessions.where((s) => !s.isSleep && !s.isDeleted).toList();

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
          String memberId) async =>
      sessions
          .where((s) => s.memberId == memberId && !s.isDeleted)
          .toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSessions(
          {int limit = 20}) async =>
      sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions(
          {int limit = 10}) async =>
      sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
          DateTime start, DateTime end) async =>
      sessions.where((s) => !s.startTime.isBefore(start)).toList();

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
  Stream<List<domain.FrontingSession>> watchRecentAllSessions(
          {int limit = 30}) =>
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

  @override
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions() async =>
      sessions
          .where((s) =>
              s.isDeleted &&
              s.pluralkitUuid != null &&
              s.deleteIntentEpoch != null)
          .toList();

  @override
  Future<void> clearPluralKitLink(String id) async {
    linkCleared.add(id);
    final i = sessions.indexWhere((s) => s.id == id);
    if (i >= 0) sessions[i] = sessions[i].copyWith(pluralkitUuid: null);
  }

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {
    stampedPushStart.add(id);
    final i = sessions.indexWhere((s) => s.id == id);
    if (i >= 0) {
      sessions[i] = sessions[i].copyWith(deletePushStartedAt: timestampMs);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

domain.Member _member(
  String id, {
  String name = 'Alice',
  String? pluralkitId,
  String? pluralkitUuid,
  bool isDeleted = false,
  int? deleteIntentEpoch,
  int? deletePushStartedAt,
}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      pluralkitId: pluralkitId,
      pluralkitUuid: pluralkitUuid,
      isDeleted: isDeleted,
      deleteIntentEpoch: deleteIntentEpoch,
      deletePushStartedAt: deletePushStartedAt,
    );

domain.FrontingSession _session(
  String id, {
  required DateTime startTime,
  DateTime? endTime,
  String? memberId,
  String? pluralkitUuid,
  bool isDeleted = false,
  int? deleteIntentEpoch,
  int? deletePushStartedAt,
}) =>
    domain.FrontingSession(
      id: id,
      startTime: startTime,
      endTime: endTime,
      memberId: memberId,
      pluralkitUuid: pluralkitUuid,
      isDeleted: isDeleted,
      deleteIntentEpoch: deleteIntentEpoch,
      deletePushStartedAt: deletePushStartedAt,
    );

/// Build a service AND initialize the sync-state row so syncRecentData
/// will run the bidirectional path (not performFullImport).
///
/// Seeds [lastSyncDate] well in the past so recent-pull sees no PK
/// switches (fake client returns `[]` anyway).
Future<({PluralKitSyncService svc, int epoch})> _makeService({
  required _FakeClient client,
  required AppDatabase db,
  required _FakeMemberRepo memberRepo,
  required _FakeSessionRepo sessionRepo,
  required String systemId,
  int initialEpoch = 0,
}) async {
  // Seed sync_state to mimic a prior link + completed mapping.
  await db.pluralKitSyncDao.upsertSyncState(PluralKitSyncStateCompanion(
    id: const Value('pk_config'),
    systemId: Value(systemId),
    isConnected: const Value(true),
    mappingAcknowledged: const Value(true),
    linkedAt: Value(DateTime(2026, 1, 1)),
    lastSyncDate: Value(DateTime(2026, 1, 2)),
    linkEpoch: Value(initialEpoch),
  ));

  final svc = PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
  );
  // Hydrate _state from the DB row we just wrote.
  await svc.loadState();
  return (svc: svc, epoch: initialEpoch);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(() {
    storageStub.setup();
    // Pre-seed the PK token since _buildClient reads it from secure storage.
    storageStub._store['prism_pluralkit_token'] = 'test-token';
  });
  tearDown(storageStub.teardown);

  group('scenario A — basic deletion', () {
    test('tombstoned linked member + session → both DELETEs happen', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(_session(
          's1',
          startTime: DateTime(2026, 2, 1),
          endTime: DateTime(2026, 2, 1, 1),
          pluralkitUuid: 'uuid-s1',
          isDeleted: true,
          deleteIntentEpoch: 0,
        ));

      final client = _FakeClient();
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      final summary = await svc.syncRecentData(
        direction: PkSyncDirection.bidirectional,
      );

      expect(epoch, 0);
      expect(client.deletedSwitches, ['uuid-s1']);
      expect(client.deletedMembers, ['pkA']);
      expect(summary?.switchesDeletedOnPk, 1);
      expect(summary?.membersDeletedOnPk, 1);
      // R3: link cleared on both.
      expect(memberRepo.linkCleared, ['local-a']);
      expect(sessionRepo.linkCleared, ['s1']);
    });
  });

  group('scenario B — idempotent rerun', () {
    test('second pass emits zero DELETEs', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(_session('s1',
            startTime: DateTime(2026, 2, 1),
            pluralkitUuid: 'uuid-s1',
            isDeleted: true,
            deleteIntentEpoch: 0));
      final client = _FakeClient();
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);
      final deletedMembersAfterFirst = List.of(client.deletedMembers);
      final deletedSwitchesAfterFirst = List.of(client.deletedSwitches);

      // Second run — link should already be cleared, so
      // getDeletedLinkedMembers/Sessions return nothing new.
      final summary2 = await svc.syncRecentData(
        direction: PkSyncDirection.bidirectional,
      );

      expect(client.deletedMembers, deletedMembersAfterFirst);
      expect(client.deletedSwitches, deletedSwitchesAfterFirst);
      expect(summary2?.membersDeletedOnPk, 0);
      expect(summary2?.switchesDeletedOnPk, 0);
      expect(epoch, 0);
    });
  });

  group('scenario C — 404 swallowed', () {
    test('PK 404 still clears the link and counts as success', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient()..memberDeleteStatus = 404;

      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      final summary = await svc.syncRecentData(
        direction: PkSyncDirection.bidirectional,
      );

      expect(client.deletedMembers, ['pkA']);
      expect(summary?.membersDeletedOnPk, 1);
      expect(memberRepo.linkCleared, ['local-a']);
    });
  });

  group('scenario D — push-disabled then enabled', () {
    test('no DELETE in pullOnly; replayed on bidirectional', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient();

      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      await svc.syncRecentData(direction: PkSyncDirection.pullOnly);
      expect(client.deletedMembers, isEmpty);
      expect(memberRepo.linkCleared, isEmpty);

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);
      expect(client.deletedMembers, ['pkA']);
      expect(memberRepo.linkCleared, ['local-a']);
    });
  });

  group('R1 — stale epoch is skipped', () {
    test('tombstone stamped with old epoch not DELETEd after epoch bump',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              // stamped in a prior epoch (0)
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient();
      // current epoch = 5 (tombstone intent epoch = 0 → stale)
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
        initialEpoch: 5,
      );

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);
      expect(client.deletedMembers, isEmpty);
      expect(memberRepo.linkCleared, isEmpty);
    });
  });

  group('R2 — CRDT-style resurrection aborts the push', () {
    test('re-read flips isDeleted=false → no DELETE call', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _ResurrectingMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient();
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);
      expect(client.deletedMembers, isEmpty);
      expect(memberRepo.linkCleared, isEmpty);
    });
  });

  group('R5 — cascade guard: live linked session blocks member DELETE', () {
    test('skips DELETE and emits a user-facing message', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      // Live (not-deleted) session still references member + has a PK uuid.
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(_session(
          's-live',
          startTime: DateTime(2026, 2, 1),
          memberId: 'local-a',
          pluralkitUuid: 'uuid-live',
        ));
      final client = _FakeClient();
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);
      expect(client.deletedMembers, isEmpty);
      expect(memberRepo.linkCleared, isEmpty);
      // Service's state should carry a syncError describing the skip.
      expect(svc.state.syncError, isNotNull);
    });
  });

  group('R3 — successful DELETE clears the local PK link', () {
    test('clearPluralKitLink is invoked with the local id', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([
          _member('local-a',
              pluralkitId: 'pkA',
              isDeleted: true,
              deleteIntentEpoch: 0),
        ]);
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(_session(
          's1',
          startTime: DateTime(2026, 2, 1),
          pluralkitUuid: 'uuid-s1',
          isDeleted: true,
          deleteIntentEpoch: 0,
        ));
      final client = _FakeClient();
      final (:svc, :epoch) = await _makeService(
        client: client,
        db: db,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
        systemId: 'sys-1',
      );

      await svc.syncRecentData(direction: PkSyncDirection.bidirectional);

      expect(memberRepo.linkCleared, ['local-a']);
      expect(sessionRepo.linkCleared, ['s1']);
      // Stamp observed on both (R6 lease claimed once, inline).
      expect(memberRepo.stampedPushStart, ['local-a']);
      expect(sessionRepo.stampedPushStart, ['s1']);
    });
  });
}

// ---------------------------------------------------------------------------
// Specialty fakes
// ---------------------------------------------------------------------------

/// Member repo where `getMemberById` (the R2 re-read) pretends the row was
/// resurrected (isDeleted=false), while the initial
/// `getDeletedLinkedMembers` pass still returned the tombstone. This models
/// a CRDT merge landing between the scan and the DELETE call.
class _ResurrectingMemberRepo extends _FakeMemberRepo {
  @override
  Future<domain.Member?> getMemberById(String id) async {
    final m = members[id];
    return m?.copyWith(isDeleted: false);
  }
}
