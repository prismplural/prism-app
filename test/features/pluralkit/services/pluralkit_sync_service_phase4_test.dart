import 'dart:convert';

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
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock
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
// Fakes
// ---------------------------------------------------------------------------

class _Call {
  final String method;
  final List<dynamic> args;
  _Call(this.method, this.args);
}

class _FakeClient implements PluralKitClient {
  final List<_Call> calls = [];
  List<List<PKSwitch>> switchPages = [];
  List<PKSwitch> createSwitchResponses = [];
  bool throwStaleOnUpdateMember = false;
  bool throwStaleOnCreateSwitch = false;
  int _createSwitchIndex = 0;

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys', name: 'Test');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<List<PKSwitch>> getSwitches(
      {DateTime? before, int limit = 100}) async {
    calls.add(_Call('getSwitches', [before]));
    if (switchPages.isEmpty) return const [];
    return switchPages.removeAt(0);
  }

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    calls.add(_Call('updateMember', [id, data]));
    if (throwStaleOnUpdateMember) {
      throw const PluralKitApiError(404, 'not found');
    }
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
      {DateTime? timestamp}) async {
    calls.add(_Call('createSwitch', [memberIds, timestamp]));
    if (throwStaleOnCreateSwitch) {
      throw const PluralKitApiError(404, 'stale');
    }
    if (_createSwitchIndex < createSwitchResponses.length) {
      return createSwitchResponses[_createSwitchIndex++];
    }
    return PKSwitch(
      id: 'sw-${calls.length}',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

  @override
  Future<PKSwitch> updateSwitch(String switchId,
          {required DateTime timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
          String switchId, List<String> memberIds) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) async {
    calls.add(_Call('deleteSwitch', [switchId]));
  }

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  void dispose() {}
}

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> members = {};

  void seed(List<domain.Member> ms) {
    for (final m in ms) {
      members[m.id] = m;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async => members.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => members[id];

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => members[id]).whereType<domain.Member>().toList();

  @override
  Future<void> createMember(domain.Member m) async => members[m.id] = m;

  @override
  Future<void> updateMember(domain.Member m) async => members[m.id] = m;

  @override
  Future<void> deleteMember(String id) async => members.remove(id);

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
}

class _FakeSessionRepo implements FrontingSessionRepository {
  final List<domain.FrontingSession> sessions = [];

  @override
  Future<List<domain.FrontingSession>> getAllSessions() async =>
      List.of(sessions);

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
  Future<void> deleteSession(String id) async =>
      sessions.removeWhere((s) => s.id == id);

  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async =>
      sessions.where((s) => s.isActive && !s.isSleep).toList();

  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      sessions.where((s) => s.isActive).toList();

  @override
  Future<domain.FrontingSession?> getActiveSession() async {
    for (final s in sessions) {
      if (s.isActive && !s.isSleep) return s;
    }
    return null;
  }

  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async =>
      sessions.where((s) => !s.isSleep).toList();

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(String memberId) async =>
      sessions.where((s) => s.memberId == memberId).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({int limit = 20}) async =>
      sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({int limit = 10}) async =>
      sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
          DateTime start, DateTime end) async =>
      sessions
          .where((s) =>
              !s.startTime.isBefore(start) && !s.startTime.isAfter(end))
          .toList();

  @override
  Stream<List<domain.FrontingSession>> watchAllSessions() =>
      throw UnimplementedError();
  @override
  Stream<List<domain.FrontingSession>> watchActiveSessions() =>
      Stream.value(const []);
  @override
  Stream<domain.FrontingSession?> watchActiveSession() => Stream.value(null);
  @override
  Stream<domain.FrontingSession?> watchActiveSleepSession() => Stream.value(null);
  @override
  Stream<List<domain.FrontingSession>> watchAllSleepSessions() =>
      Stream.value(const []);
  @override
  Stream<domain.FrontingSession?> watchSessionById(String id) => Stream.value(null);
  @override
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(sessions.take(limit).toList());
  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({int limit = 30}) =>
      Stream.value(sessions.take(limit).toList());
  @override
  Future<int> getCount() async => sessions.length;
  @override
  Future<int> getFrontingCount() async => sessions.where((s) => !s.isSleep).length;
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

domain.Member _member(String id,
        {String? pluralkitId, String name = 'Alice'}) =>
    domain.Member(
      id: id,
      name: name,
      emoji: '❔',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      pluralkitId: pluralkitId,
    );

PluralKitSyncService _makeService({
  required _FakeClient client,
  required AppDatabase db,
  _FakeMemberRepo? memberRepo,
  _FakeSessionRepo? sessionRepo,
}) {
  return PluralKitSyncService(
    memberRepository: memberRepo ?? _FakeMemberRepo(),
    frontingSessionRepository: sessionRepo ?? _FakeSessionRepo(),
    syncDao: db.pluralKitSyncDao,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
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

  group('_importSwitch drop-bug fix', () {
    test(
        'switch whose first PK member is unmapped picks next mapped ID as primary',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-b', pluralkitId: 'pkB')]);
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient()
        ..switchPages = [
          [
            PKSwitch(
              id: 'sw-1',
              timestamp: DateTime(2026, 1, 1, 10),
              members: const ['pkA', 'pkB'], // pkA unmapped, pkB mapped
            ),
          ],
          [],
        ];

      final svc = _makeService(
          client: client, db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);

      await svc.setToken('t');
      await svc.acknowledgeMapping();
      await svc.importSwitchesAfterLink();

      expect(sessionRepo.sessions.length, 1);
      expect(sessionRepo.sessions.first.memberId, 'local-b');
      expect(sessionRepo.sessions.first.coFronterIds, isEmpty);
      // pkMemberIdsJson preserves original PK list
      expect(
        jsonDecode(sessionRepo.sessions.first.pkMemberIdsJson!),
        ['pkA', 'pkB'],
      );
    });

    test('switch with zero mapped members still persists with memberId=null',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo();
      final sessionRepo = _FakeSessionRepo();
      final client = _FakeClient()
        ..switchPages = [
          [
            PKSwitch(
              id: 'sw-orphan',
              timestamp: DateTime(2026, 1, 1, 10),
              members: const ['pkX', 'pkY'],
            ),
          ],
          [],
        ];

      final svc = _makeService(
          client: client, db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);
      await svc.setToken('t');
      await svc.acknowledgeMapping();
      await svc.importSwitchesAfterLink();

      expect(sessionRepo.sessions.length, 1);
      expect(sessionRepo.sessions.first.memberId, isNull);
      expect(sessionRepo.sessions.first.pkMemberIdsJson, isNotNull);
      expect(jsonDecode(sessionRepo.sessions.first.pkMemberIdsJson!),
          ['pkX', 'pkY']);
    });
  });

  group('reattributeSwitches', () {
    test('re-resolves primary+cofronters after new link', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo();
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's1',
          startTime: DateTime(2026, 1, 1, 10),
          memberId: null, // was headless at import time
          pluralkitUuid: 'sw-1',
          pkMemberIdsJson: jsonEncode(['pkA', 'pkB', 'pkC']),
        ));

      // Only pkB is linked at first
      memberRepo.seed([_member('local-b', pluralkitId: 'pkB')]);

      final svc = _makeService(
          client: _FakeClient(), db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);
      final firstPass = await svc.reattributeSwitches();
      expect(firstPass, 1);
      expect(sessionRepo.sessions.first.memberId, 'local-b');
      expect(sessionRepo.sessions.first.coFronterIds, isEmpty);

      // Second pass with no changes: idempotent.
      final secondPass = await svc.reattributeSwitches();
      expect(secondPass, 0);

      // Link pkA; reattribute should now promote local-a to primary.
      memberRepo.seed([_member('local-a', pluralkitId: 'pkA', name: 'A')]);
      final thirdPass = await svc.reattributeSwitches();
      expect(thirdPass, 1);
      expect(sessionRepo.sessions.first.memberId, 'local-a');
      expect(sessionRepo.sessions.first.coFronterIds, ['local-b']);
    });

    test('sessions without pkMemberIdsJson are untouched', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-x', pluralkitId: 'pkX')]);
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's-local',
          startTime: DateTime(2026, 1, 1),
          memberId: 'local-x',
          // no pkMemberIdsJson — a pure local session
        ));

      final svc = _makeService(
          client: _FakeClient(), db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);
      final n = await svc.reattributeSwitches();
      expect(n, 0);
      expect(sessionRepo.sessions.first.memberId, 'local-x');
    });
  });

  group('pushPendingSwitches — scoped push', () {
    test('pushes only sessions started after linkedAt with mapped members',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-a', pluralkitId: 'pkA')]);

      final sessionRepo = _FakeSessionRepo()
        ..sessions.addAll([
          // Before link → skipped
          domain.FrontingSession(
            id: 's-old',
            startTime: DateTime(2025, 1, 1),
            memberId: 'local-a',
          ),
          // After link, eligible → pushed
          domain.FrontingSession(
            id: 's-new',
            startTime: DateTime(2026, 2, 1, 10),
            endTime: DateTime(2026, 2, 1, 12),
            memberId: 'local-a',
          ),
          // After link, unlinked local → skipped
          domain.FrontingSession(
            id: 's-unlinked',
            startTime: DateTime(2026, 2, 1, 14),
            memberId: 'local-unknown',
          ),
          // Already pushed → skipped
          domain.FrontingSession(
            id: 's-already',
            startTime: DateTime(2026, 2, 1, 16),
            memberId: 'local-a',
            pluralkitUuid: 'existing-sw',
          ),
        ]);

      final client = _FakeClient();
      final svc = _makeService(
          client: client, db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);

      // Manually seed linkedAt to a known point.
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          isConnected: const Value(true),
          mappingAcknowledged: const Value(true),
          linkedAt: Value(DateTime(2026, 1, 15)),
        ),
      );
      await svc.loadState();

      // Pre-seed the token so _buildClient succeeds.
      await const FlutterSecureStorage()
          .write(key: 'prism_pluralkit_token', value: 't');
      // Use the stub via the SecureStorageStub:
      // the FlutterSecureStorage write above goes through our mock handler.

      final pushed = await svc.pushPendingSwitches(
        pushService: PkPushService(queue: PkRequestQueue()),
      );

      expect(pushed, 1);
      // s-new: one create for start, one empty-members create for end
      final creates = client.calls.where((c) => c.method == 'createSwitch').toList();
      expect(creates.length, 2);
      expect(creates[0].args[0], ['pkA']);
      expect(creates[0].args[1], DateTime(2026, 2, 1, 10));
      expect(creates[1].args[0], <String>[]);
      expect(creates[1].args[1], DateTime(2026, 2, 1, 12));

      // Session records the returned PK switch ID.
      final updated = sessionRepo.sessions.firstWhere((s) => s.id == 's-new');
      expect(updated.pluralkitUuid, isNotNull);
    });

    test(
        'linkedAt == session.startTime boundary — session still pushed '
        '(setToken stamps linkedAt 1ms before now)', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-a', pluralkitId: 'pkA')]);

      // Simulate "session created in the same tick as setToken." We stamp
      // linkedAt = startTime - 1ms to match what setToken does; the session
      // at exactly `startTime` must pass the isAfter boundary.
      final startTime = DateTime(2026, 3, 1, 12, 0, 0, 500);
      final linkedAt = startTime.subtract(const Duration(milliseconds: 1));

      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's-boundary',
          startTime: startTime,
          memberId: 'local-a',
        ));

      final client = _FakeClient();
      final svc = _makeService(
          client: client,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo);

      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          isConnected: const Value(true),
          mappingAcknowledged: const Value(true),
          linkedAt: Value(linkedAt),
        ),
      );
      await svc.loadState();
      await const FlutterSecureStorage()
          .write(key: 'prism_pluralkit_token', value: 't');

      final pushed = await svc.pushPendingSwitches(
        pushService: PkPushService(queue: PkRequestQueue()),
      );
      expect(pushed, 1, reason: 'session at linkedAt+1ms must be pushed');
    });

    test(
        'rolls back first push when switch-out fails, leaves pluralkitUuid '
        'null for retry', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-a', pluralkitId: 'pkA')]);

      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's-rollback',
          startTime: DateTime(2026, 2, 1, 10),
          endTime: DateTime(2026, 2, 1, 12),
          memberId: 'local-a',
        ));

      // First createSwitch succeeds and returns a known id; second one throws
      // a non-404 error so we go down the generic rollback path (not stale).
      final client = _ThrowOnSecondCreateClient(firstReturnedId: 'sw-start');
      final svc = _makeService(
          client: client,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo);

      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          isConnected: const Value(true),
          mappingAcknowledged: const Value(true),
          linkedAt: Value(DateTime(2026, 1, 15)),
        ),
      );
      await svc.loadState();
      await const FlutterSecureStorage()
          .write(key: 'prism_pluralkit_token', value: 't');

      final pushed = await svc.pushPendingSwitches(
        pushService: PkPushService(queue: PkRequestQueue()),
      );

      // Session remained pending (not marked with UUID).
      expect(pushed, 0);
      final session = sessionRepo.sessions.single;
      expect(session.pluralkitUuid, isNull,
          reason: 'failed switch-out must leave session retriable');

      // Rollback attempted: we should have seen createSwitch x2 + deleteSwitch.
      final methods = client.calls.map((c) => c.method).toList();
      expect(methods.where((m) => m == 'createSwitch').length, 2);
      expect(methods.contains('deleteSwitch'), isTrue,
          reason: 'rollback should call deleteSwitch on the start uuid');
      final del =
          client.calls.firstWhere((c) => c.method == 'deleteSwitch');
      expect(del.args[0], 'sw-start');
    });

    test('returns 0 and pushes nothing when linkedAt is null', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-a', pluralkitId: 'pkA')]);
      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's',
          startTime: DateTime(2026, 3, 1),
          memberId: 'local-a',
        ));

      final client = _FakeClient();
      final svc = _makeService(
          client: client, db: db, memberRepo: memberRepo, sessionRepo: sessionRepo);

      await db.pluralKitSyncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          isConnected: Value(true),
          mappingAcknowledged: Value(true),
        ),
      );
      await svc.loadState();
      await const FlutterSecureStorage()
          .write(key: 'prism_pluralkit_token', value: 't');

      final pushed = await svc.pushPendingSwitches(
        pushService: PkPushService(queue: PkRequestQueue()),
      );
      expect(pushed, 0);
      expect(client.calls.where((c) => c.method == 'createSwitch'), isEmpty);
    });
  });

  group('stale link 404 handling', () {
    test('pushMember 404 throws PkStaleLinkException', () async {
      final client = _FakeClient()..throwStaleOnUpdateMember = true;
      final push = PkPushService(queue: PkRequestQueue());

      final member = domain.Member(
        id: 'local-a',
        name: 'Alice',
        emoji: '❔',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        pluralkitId: 'pkA',
      );

      expect(
        () => push.pushMember(member, client),
        throwsA(isA<PkStaleLinkException>()
            .having((e) => e.localId, 'localId', 'local-a')
            .having((e) => e.pkId, 'pkId', 'pkA')
            .having((e) => e.kind, 'kind', PkStaleLinkKind.member)),
      );
    });

    test(
        'pushPendingSwitches invokes onStaleLink callback on 404 '
        '(regression S3)',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo()
        ..seed([_member('local-a', pluralkitId: 'pkA')]);

      final sessionRepo = _FakeSessionRepo()
        ..sessions.add(domain.FrontingSession(
          id: 's-stale',
          startTime: DateTime(2026, 2, 1, 10),
          memberId: 'local-a',
        ));

      final client = _FakeClient()..throwStaleOnCreateSwitch = true;
      final svc = _makeService(
          client: client,
          db: db,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo);

      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          isConnected: const Value(true),
          mappingAcknowledged: const Value(true),
          linkedAt: Value(DateTime(2026, 1, 15)),
        ),
      );
      await svc.loadState();
      await const FlutterSecureStorage()
          .write(key: 'prism_pluralkit_token', value: 't');

      final messages = <String>[];
      final pushed = await svc.pushPendingSwitches(
        pushService: PkPushService(queue: PkRequestQueue()),
        onStaleLink: messages.add,
      );

      expect(pushed, 0);
      expect(messages, isNotEmpty,
          reason: 'stale-link 404 must surface via onStaleLink callback (S3)');
      expect(messages.single,
          contains('switch target was removed on the server'));
    });

    test('non-404 PK errors are not wrapped as stale', () async {
      final client = _FakeClient();
      // 500 error via a helper: override updateMember
      final push = PkPushService(queue: PkRequestQueue());
      final member = domain.Member(
        id: 'local-b',
        name: 'Bob',
        emoji: '❔',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        pluralkitId: 'pkB',
      );
      // Monkey-patching not available; we instead use a client that throws 500
      // via a subclass below.
      final throwing500Client = _Throw500Client();
      expect(
        () => push.pushMember(member, throwing500Client),
        throwsA(isA<PluralKitApiError>()
            .having((e) => e is PkStaleLinkException, 'isStale', false)),
      );
      // silence unused-var lints
      expect(client.calls, isEmpty);
    });
  });
}

class _Throw500Client extends _FakeClient {
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    throw const PluralKitApiError(500, 'boom');
  }
}

/// First createSwitch returns a known id; every subsequent createSwitch
/// throws. Used to exercise the two-push rollback path in pushPendingSwitches.
class _ThrowOnSecondCreateClient extends _FakeClient {
  final String firstReturnedId;
  int _n = 0;
  _ThrowOnSecondCreateClient({required this.firstReturnedId});

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
      {DateTime? timestamp}) async {
    calls.add(_Call('createSwitch', [memberIds, timestamp]));
    _n++;
    if (_n == 1) {
      return PKSwitch(
        id: firstReturnedId,
        timestamp: timestamp ?? DateTime.now(),
        members: memberIds,
      );
    }
    throw const PluralKitApiError(500, 'switch-out failed');
  }
}
