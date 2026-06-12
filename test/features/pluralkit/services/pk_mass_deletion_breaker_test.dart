/// Mass-deletion circuit breaker: unattended syncs refuse an over-threshold
/// batch of PK deletions (migration residuals are indistinguishable from
/// real deletes); the confirmed manual destructive-push path proceeds.
/// Drives the `debugPushPending*Deletions` seams against REAL Drift repos.
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock (same shape as pk_shared_switch_deletion_test.dart).
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
// Recording client: counts deleteMember/deleteSwitch/getSwitch/PATCH calls so
// we can prove zero PK mutations occurred when the breaker trips. For the
// switch-deletion pass-through, [getSwitch] serves sole-fronter snapshots
// (members = the departing member's short id) so the H2 path takes its DELETE
// branch.
// ---------------------------------------------------------------------------

class _CountingClient implements PluralKitClient {
  final List<String> deletedMembers = [];
  final List<String> deletedSwitches = [];
  final List<String> getSwitchCalls = [];
  final List<String> patchedSwitches = [];

  /// PK-side switch snapshots served by [getSwitch], keyed by switch uuid.
  final Map<String, PKSwitch> switchSnapshots = {};

  @override
  Future<void> deleteMember(String id) async {
    deletedMembers.add(id);
  }

  @override
  Future<PKSwitch> getSwitch(String switchRef) async {
    final ref = switchRef.trim();
    getSwitchCalls.add(ref);
    final snapshot = switchSnapshots[ref];
    if (snapshot == null) {
      throw const PluralKitApiError(404, '{"code":20007}', code: 20007);
    }
    return snapshot;
  }

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    patchedSwitches.add(switchId);
    return PKSwitch(
      id: switchId,
      timestamp: DateTime.utc(2026, 1, 1),
      members: memberIds,
    );
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    deletedSwitches.add(switchId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unused by mass-deletion breaker tests: '
          '${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

domain.Member _member(int i) => domain.Member(
  id: 'local-$i',
  name: 'Member $i',
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: 'pk$i',
  pluralkitUuid: 'uuid-$i',
);

PluralKitSyncService _makeService({
  required AppDatabase db,
  required _CountingClient client,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
  required PkSyncEventBus bus,
}) => PluralKitSyncService(
  memberRepository: memberRepo,
  frontingSessionRepository: sessionRepo,
  syncDao: db.pluralKitSyncDao,
  bus: bus,
  secureStorage: const FlutterSecureStorage(),
  clientFactory: (_) => client,
);

/// Builds a service + a synchronous event capture. `PkSyncEventBus.emit` only
/// delivers when this isolate is flagged as the main isolate (see
/// `markPkBusMainIsolate`), and the capture records emits synchronously so the
/// breaker event is observable without awaiting the broadcast stream.
({PluralKitSyncService service, List<PkSyncEvent> events}) _serviceWithCapture({
  required AppDatabase db,
  required _CountingClient client,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
}) {
  final capture = PkSyncEventBusCapture();
  final service = _makeService(
    db: db,
    client: client,
    memberRepo: memberRepo,
    sessionRepo: sessionRepo,
    bus: capture.bus,
  );
  return (service: service, events: capture.events);
}

/// Seed [count] deleted, PK-linked members whose delete intent matches the
/// current epoch (so each is an ELIGIBLE deletion candidate).
Future<void> _seedDeletedLinkedMembers(
  DriftMemberRepository memberRepo,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    await memberRepo.createMember(_member(i));
  }
  for (var i = 0; i < count; i++) {
    // deleteMember stamps deleteIntentEpoch = currentEpoch (pkSyncDao wired).
    await memberRepo.deleteMember('local-$i');
  }
}

/// Valid PK-switch-uuid-shaped id for candidate row [i].
String _switchUuid(int i) =>
    '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';

/// Seed [count] deleted, PK-linked fronting sessions (each linked to its own
/// sole-fronter switch) whose delete intent matches the current epoch — each
/// is an ELIGIBLE switch-deletion candidate. Also serves a sole-fronter
/// snapshot for each switch on [client] so the ≤threshold pass-through takes
/// the H2 DELETE branch (no co-fronters to PATCH down to).
Future<void> _seedDeletedLinkedSessions({
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
  required _CountingClient client,
  required int count,
}) async {
  for (var i = 0; i < count; i++) {
    // Members stay LIVE (only their sessions are deleted) — the deletion
    // pusher resolves the departing member's PK refs from the live row.
    await memberRepo.createMember(_member(i));
    await sessionRepo.createSession(
      domain_fs.FrontingSession(
        id: 'row-$i',
        startTime: DateTime.utc(2026, 1, 1, 8).add(Duration(minutes: i)),
        endTime: DateTime.utc(2026, 1, 1, 9).add(Duration(minutes: i)),
        memberId: 'local-$i',
        pluralkitUuid: _switchUuid(i),
      ),
    );
    client.switchSnapshots[_switchUuid(i)] = PKSwitch(
      id: _switchUuid(i),
      timestamp: DateTime.utc(2026, 1, 1, 8).add(Duration(minutes: i)),
      members: ['pk$i'], // sole fronter → DELETE path
    );
  }
  for (var i = 0; i < count; i++) {
    // deleteSession stamps deleteIntentEpoch = currentEpoch on the linked row
    // (pkSyncDao wired) — exactly the C1-class residual the breaker guards.
    await sessionRepo.deleteSession('row-$i');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(() {
    storageStub.setup();
    // The bus drops emits unless this isolate is flagged as the main isolate.
    markPkBusMainIsolate();
  });
  tearDown(() {
    storageStub.teardown();
    // Reset the global so the flag doesn't leak into sibling test files.
    resetPkBusMainIsolateForTest();
  });

  group('mass-deletion breaker (member deletions)', () {
    test(
      'over-threshold candidates on an AUTOMATIC sync → zero PK deletes + '
      'PkMassDeletionBlocked emitted',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        // One above the threshold.
        await _seedDeletedLinkedMembers(
          memberRepo,
          kPkMassDeletionAutoThreshold + 1,
        );

        final client = _CountingClient();
        final (:service, :events) = _serviceWithCapture(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final staleMessages = <String>[];
        final deleted = await service.debugPushPendingMemberDeletions(
          client: client,
          onStaleLink: staleMessages.add,
          allowMassDeletion: false, // unattended/automatic
        );

        expect(deleted, 0, reason: 'breaker bails before any delete');
        expect(client.deletedMembers, isEmpty,
            reason: 'no PK DELETE may fire on an over-threshold auto batch');
        expect(staleMessages, isNotEmpty,
            reason: 'the user is told via the stale-link channel');
        final blocked = events.whereType<PkMassDeletionBlocked>().toList();
        expect(blocked, hasLength(1));
        expect(blocked.single.kind, 'members');
        expect(blocked.single.threshold, kPkMassDeletionAutoThreshold);
        expect(
          blocked.single.candidateCount,
          kPkMassDeletionAutoThreshold + 1,
        );
      },
    );

    test(
      'at-or-below threshold on an AUTOMATIC sync → normal deletion proceeds',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        // Exactly at the threshold → still allowed (breaker is strict `>`).
        await _seedDeletedLinkedMembers(memberRepo, kPkMassDeletionAutoThreshold);

        final client = _CountingClient();
        final (:service, :events) = _serviceWithCapture(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final deleted = await service.debugPushPendingMemberDeletions(
          client: client,
          allowMassDeletion: false,
        );

        expect(deleted, kPkMassDeletionAutoThreshold,
            reason: 'a batch at the threshold deletes normally');
        expect(client.deletedMembers, hasLength(kPkMassDeletionAutoThreshold));
        expect(events.whereType<PkMassDeletionBlocked>(), isEmpty);
      },
    );

    test(
      'over-threshold candidates on a user-confirmed MANUAL sync → proceeds',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        await _seedDeletedLinkedMembers(
          memberRepo,
          kPkMassDeletionAutoThreshold + 5,
        );

        final client = _CountingClient();
        final (:service, :events) = _serviceWithCapture(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        // allowMassDeletion: true models the consent path (isManual: true
        // after `_confirmPluralKitDeleteRisk`).
        final deleted = await service.debugPushPendingMemberDeletions(
          client: client,
          allowMassDeletion: true,
        );

        expect(deleted, kPkMassDeletionAutoThreshold + 5,
            reason: 'confirmed manual destructive push deletes the whole batch');
        expect(
          client.deletedMembers,
          hasLength(kPkMassDeletionAutoThreshold + 5),
        );
        expect(events.whereType<PkMassDeletionBlocked>(), isEmpty);
      },
    );
  });

  group('mass-deletion breaker (switch deletions)', () {
    test(
      'over-threshold candidates on an AUTOMATIC sync → zero PK calls + '
      'PkMassDeletionBlocked(kind: switches) emitted',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final client = _CountingClient();
        // One above the threshold.
        await _seedDeletedLinkedSessions(
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          client: client,
          count: kPkMassDeletionAutoThreshold + 1,
        );

        final (:service, :events) = _serviceWithCapture(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final staleMessages = <String>[];
        final deleted = await service.debugPushPendingSwitchDeletions(
          client: client,
          onStaleLink: staleMessages.add,
          allowMassDeletion: false, // unattended/automatic
        );

        expect(deleted, 0, reason: 'breaker bails before any PK mutation');
        // ZERO PK calls of any kind — not even the pre-deletion snapshot GET.
        expect(client.deletedSwitches, isEmpty);
        expect(client.patchedSwitches, isEmpty);
        expect(client.getSwitchCalls, isEmpty,
            reason: 'the breaker fires before the per-candidate loop');
        expect(staleMessages, isNotEmpty,
            reason: 'the user is told via the stale-link channel');
        final blocked = events.whereType<PkMassDeletionBlocked>().toList();
        expect(blocked, hasLength(1));
        expect(blocked.single.kind, 'switches');
        expect(blocked.single.threshold, kPkMassDeletionAutoThreshold);
        expect(
          blocked.single.candidateCount,
          kPkMassDeletionAutoThreshold + 1,
        );
      },
    );

    test(
      'at-or-below threshold on an AUTOMATIC sync → normal deletion proceeds',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        final client = _CountingClient();
        // Exactly at the threshold → still allowed (breaker is strict `>`).
        await _seedDeletedLinkedSessions(
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          client: client,
          count: kPkMassDeletionAutoThreshold,
        );

        final (:service, :events) = _serviceWithCapture(
          db: db,
          client: client,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
        );

        final deleted = await service.debugPushPendingSwitchDeletions(
          client: client,
          allowMassDeletion: false,
        );

        expect(deleted, kPkMassDeletionAutoThreshold,
            reason: 'a batch at the threshold deletes normally (sole-fronter '
                'snapshots → H2 DELETE branch)');
        expect(
          client.deletedSwitches,
          hasLength(kPkMassDeletionAutoThreshold),
        );
        expect(events.whereType<PkMassDeletionBlocked>(), isEmpty);
      },
    );
  });
}
