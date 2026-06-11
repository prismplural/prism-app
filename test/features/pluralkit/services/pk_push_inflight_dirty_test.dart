/// 2026-06 PK audit M9 — `pushPendingSwitches` must not drop the trailing
/// change. When a push is in flight and a new trigger arrives (rapid A→B→C
/// switching), the in-flight future captured the OLD state, so returning it
/// would leave the latest state unpushed. The dirty-flag schedules EXACTLY one
/// follow-up run after the current push, and mid-flight callers await it.
///
/// Contract verified here:
///  * a trigger arriving mid-flight causes exactly ONE follow-up run;
///  * no follow-up runs when no trigger arrived mid-flight;
///  * the chain terminates (no infinite loop) when state stays stable.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
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
// Client whose FIRST getCurrentFronters call blocks on a gate, so a second
// pushPendingSwitches trigger can arrive while the first run is in flight.
// Counts createSwitch + getCurrentFronters calls.
// ---------------------------------------------------------------------------

class _GatedClient implements PluralKitClient {
  _GatedClient({
    Completer<void>? firstFrontersGate,
    this.uuidToShortId = const {},
  }) : _firstFrontersGate = firstFrontersGate;

  final Completer<void>? _firstFrontersGate;
  int getCurrentFrontersCalls = 0;
  final List<List<String>> createdSwitches = [];

  /// Maps the uuid wire refs createSwitch receives back to PK SHORT ids, so
  /// getCurrentFronters echoes short ids exactly like the real API (the push
  /// comparison runs in short-id space — feeding uuids back would wrongly look
  /// like a member-set change and force a spurious follow-up push).
  final Map<String, String> uuidToShortId;

  /// What getCurrentFronters returns each call (PK's current front, SHORT ids).
  PKSwitch? currentFronters;

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    getCurrentFrontersCalls++;
    if (getCurrentFrontersCalls == 1 && _firstFrontersGate != null) {
      await _firstFrontersGate.future;
    }
    return currentFronters;
  }

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds,
      {DateTime? timestamp}) async {
    createdSwitches.add(memberIds);
    // PK echoes the new front as SHORT ids.
    final shortIds = [for (final ref in memberIds) uuidToShortId[ref] ?? ref];
    currentFronters = PKSwitch(
      id: 'sw-${createdSwitches.length}',
      timestamp: timestamp ?? DateTime.now().toUtc(),
      members: shortIds,
    );
    return currentFronters!;
  }

  @override
  String get currentToken => 'fake-token';

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unused by M9 dirty-flag tests: ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<PluralKitSyncService> _readyService({
  required AppDatabase db,
  required _GatedClient client,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
}) async {
  final service = PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    // tokenOverride avoids a getSystem() round-trip in setToken — this client
    // only models the push path. canAutoSync + linkedAt are seeded directly.
    tokenOverride: 'fake-token',
    clientFactory: (_) => client,
  );
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      // pushPendingSwitches requires a non-null linkedAt.
      linkedAt: Value(DateTime.utc(2026, 1, 1)),
    ),
  );
  await service.loadState();
  expect(service.state.canAutoSync, isTrue);
  return service;
}

domain.Member _member(String id, String pkId, String pkUuid) => domain.Member(
  id: id,
  name: id,
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: pkId,
  pluralkitUuid: pkUuid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  test(
    'M9: a trigger arriving mid-flight causes EXACTLY one follow-up run',
    () async {
      final db = _makeDb();
      addTearDown(db.close);
      final memberRepo = DriftMemberRepository(db.membersDao, null);
      await memberRepo.createMember(_member('local-a', 'pkA', 'uuid-a'));
      await memberRepo.createMember(_member('local-b', 'pkB', 'uuid-b'));
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
        pkSyncDao: db.pluralKitSyncDao,
      );
      // Start: A is fronting locally (PK has nobody → first push creates A).
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'row-a',
          startTime: DateTime.utc(2026, 1, 1, 10),
          memberId: 'local-a',
        ),
      );

      final gate = Completer<void>();
      final client = _GatedClient(firstFrontersGate: gate, uuidToShortId: const {'uuid-a': 'pkA', 'uuid-b': 'pkB'});
      final service = await _readyService(
        db: db,
        client: client,
        memberRepo: memberRepo,
        sessionRepo: sessionRepo,
      );

      // Trigger #1 — blocks inside getCurrentFronters on the gate.
      final first = service.pushPendingSwitches();
      // Let it reach the gate.
      await Future<void>.delayed(Duration.zero);

      // While #1 is in flight, the local state advances (B joins) and a NEW
      // trigger arrives. It must be served by a SINGLE follow-up, not dropped.
      await sessionRepo.createSession(
        domain_fs.FrontingSession(
          id: 'row-b',
          startTime: DateTime.utc(2026, 1, 1, 11),
          memberId: 'local-b',
        ),
      );
      final second = service.pushPendingSwitches();

      // Unblock the first run; both futures should resolve.
      gate.complete();
      await first;
      await second;
      // Let any scheduled follow-up complete.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Exactly TWO createSwitch calls: the original (A) and ONE follow-up that
      // picked up the trailing change (A,B). Not three (no runaway loop), not
      // one (the trailing change was not dropped).
      expect(client.createdSwitches, hasLength(2),
          reason: 'one original push + exactly one follow-up for the trailing '
              'change (2026-06 PK audit M9)');
      // The follow-up pushed the LATEST set including B.
      expect(client.createdSwitches.last.toSet(),
          {'uuid-a', 'uuid-b'},
          reason: 'follow-up reflects the trailing state (A,B), uuid-first');
    },
  );

  test('M9: no trigger mid-flight → no follow-up run', () async {
    final db = _makeDb();
    addTearDown(db.close);
    final memberRepo = DriftMemberRepository(db.membersDao, null);
    await memberRepo.createMember(_member('local-a', 'pkA', 'uuid-a'));
    final sessionRepo = DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
      pkSyncDao: db.pluralKitSyncDao,
    );
    await sessionRepo.createSession(
      domain_fs.FrontingSession(
        id: 'row-a',
        startTime: DateTime.utc(2026, 1, 1, 10),
        memberId: 'local-a',
      ),
    );

    // No gate — the single push runs to completion uninterrupted.
    final client = _GatedClient(uuidToShortId: const {'uuid-a': 'pkA'});
    final service = await _readyService(
      db: db,
      client: client,
      memberRepo: memberRepo,
      sessionRepo: sessionRepo,
    );

    await service.pushPendingSwitches();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(client.createdSwitches, hasLength(1),
        reason: 'no mid-flight trigger → exactly one run, no follow-up');
  });

  test('M9: a mid-flight trigger on STABLE state terminates (no infinite loop)',
      () async {
    // Here the local state does NOT change between the two triggers. The
    // follow-up must run at most once and then short-circuit (state already in
    // sync), never re-trigger itself indefinitely.
    final db = _makeDb();
    addTearDown(db.close);
    final memberRepo = DriftMemberRepository(db.membersDao, null);
    await memberRepo.createMember(_member('local-a', 'pkA', 'uuid-a'));
    final sessionRepo = DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
      pkSyncDao: db.pluralKitSyncDao,
    );
    await sessionRepo.createSession(
      domain_fs.FrontingSession(
        id: 'row-a',
        startTime: DateTime.utc(2026, 1, 1, 10),
        memberId: 'local-a',
      ),
    );

    final gate = Completer<void>();
    final client = _GatedClient(firstFrontersGate: gate, uuidToShortId: const {'uuid-a': 'pkA'});
    final service = await _readyService(
      db: db,
      client: client,
      memberRepo: memberRepo,
      sessionRepo: sessionRepo,
    );

    final first = service.pushPendingSwitches();
    await Future<void>.delayed(Duration.zero);
    // Second trigger, but NO state change — follow-up will find PK already in
    // sync after the first push and must not loop.
    final second = service.pushPendingSwitches();

    gate.complete();
    await first;
    await second;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // At most one follow-up; the original created A, the follow-up finds PK
    // already current and short-circuits (no second createSwitch).
    expect(client.createdSwitches, hasLength(1),
        reason: 'stable state → follow-up short-circuits, no second push, no '
            'infinite loop');
  });
}
