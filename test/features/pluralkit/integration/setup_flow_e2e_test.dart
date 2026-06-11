// End-to-end integration test for the PluralKit setup flow.
//
// Exercises the full state-machine transition chain and controller-to-service
// handoff using:
//   - In-memory Drift DB (real DAO writes)
//   - Real PluralKitSyncService (real setToken, confirmDirection, acknowledgeMapping)
//   - Real PkMappingController (real apply, applyFronterResolution, deferBootstrap)
//   - Fake PluralKitClient (HTTP layer only)
//   - SharedPreferences mock
//
// Four scenarios:
//   (a) Fresh install, fully through wizard (no disagreement)
//   (b) Fresh install with active-fronter disagreement
//   (c) Same-system reconnect (token rotation)
//   (d) Decide-later path
//
// ignore_for_file: prefer_const_constructors

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as fronting;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_prefs_keys.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Secure-storage stub
// ---------------------------------------------------------------------------

void _installSecureStorageStub() {
  final store = <String, String?>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          switch (call.method) {
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String?;
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'containsKey':
              return store.containsKey(call.arguments['key'] as String);
            default:
              return null;
          }
        },
      );
}

// ---------------------------------------------------------------------------
// Fake PluralKitClient
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  final String _systemId;
  final List<PKMember> _members;

  int createSwitchCallCount = 0;
  List<String>? lastCreateSwitchMemberIds;
  String createSwitchReturnId = 'override-switch-id';

  PKSwitch? currentFrontersResult;

  _FakeClient(this._systemId, {List<PKMember> members = const []})
      : _members = members;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async => PKSystem(id: _systemId, name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => _members;

  @override
  Future<PKSwitch?> getCurrentFronters() async => currentFrontersResult;

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    createSwitchCallCount++;
    lastCreateSwitchMemberIds = List.of(memberIds);
    return PKSwitch(
      id: createSwitchReturnId,
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async =>
      const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
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
// Fake MemberRepository
// ---------------------------------------------------------------------------

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> _byId = {};

  _FakeMemberRepo(Iterable<domain.Member> seed) {
    for (final m in seed) {
      _byId[m.id] = m;
    }
  }

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      _byId.values.where((m) => !m.isDeleted).toList();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _byId.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _byId[id];

  @override
  Future<void> createMember(domain.Member m) async => _byId[m.id] = m;

  @override
  Future<void> updateMember(domain.Member m) async => _byId[m.id] = m;

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  @override
  Future<int> applyPluralKitLink(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _byId[id];
    if (existing == null || existing.isDeleted) return 0;
    _byId[id] = existing.copyWith(
      pluralkitUuid:
          patch['pluralkit_uuid'] as String? ?? existing.pluralkitUuid,
      pluralkitId: patch['pluralkit_id'] as String? ?? existing.pluralkitId,
      pluralkitDisplayName:
          patch['pluralkit_display_name'] as String? ??
              existing.pluralkitDisplayName,
      pluralkitSyncIgnored: false,
    );
    return 1;
  }

  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final existing = _byId[id];
    if (existing == null || existing.isDeleted) return 0;
    _byId[id] = existing.copyWith(
      pluralkitUuid:
          patch['pluralkit_uuid'] as String? ?? existing.pluralkitUuid,
      pluralkitId: patch['pluralkit_id'] as String? ?? existing.pluralkitId,
      pluralkitDisplayName:
          patch['pluralkit_display_name'] as String? ??
              existing.pluralkitDisplayName,
    );
    return 1;
  }

  @override
  Future<int> excludePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null || existing.isDeleted) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: true);
    return 1;
  }

  @override
  Future<int> resumePluralKitSync(String id) async {
    final existing = _byId[id];
    if (existing == null || existing.isDeleted) return 0;
    _byId[id] = existing.copyWith(pluralkitSyncIgnored: false);
    return 1;
  }

  @override
  Future<void> deleteMember(String id) async => _byId.remove(id);

  @override
  Future<int> getCount() async => _byId.length;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _byId[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(ids.map((id) => _byId[id]).whereType<domain.Member>().toList());

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_byId.values.where((m) => m.isActive).toList());

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(_byId.values.where((m) => !m.isDeleted).toList());

  @override
  Stream<domain.Member?> watchMemberById(String id) => Stream.value(_byId[id]);

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
// Tracking FrontingSessionRepository (records mutations)
// ---------------------------------------------------------------------------

class _TrackingFrontingSessionRepo implements FrontingSessionRepository {
  final List<fronting.FrontingSession> _sessions;

  final List<String> endedSessionIds = [];
  final List<fronting.FrontingSession> createdSessions = [];

  _TrackingFrontingSessionRepo(List<fronting.FrontingSession> initial)
      : _sessions = List.of(initial);

  @override
  Future<List<fronting.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      _sessions.where((s) => s.endTime == null && !s.isDeleted).toList();

  @override
  Future<List<fronting.FrontingSession>> getActiveSessions() async =>
      _sessions.where((s) => s.endTime == null && !s.isDeleted).toList();

  @override
  Future<List<fronting.FrontingSession>> getAllSessions() async => List.of(_sessions);

  @override
  Future<List<fronting.FrontingSession>> getFrontingSessions() async => const [];

  @override
  Future<List<fronting.FrontingSession>> getDeletedLinkedSessions() async =>
      const [];

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    endedSessionIds.add(id);
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      _sessions[idx] = _sessions[idx].copyWith(endTime: endTime);
    }
  }

  @override
  Future<void> createSession(fronting.FrontingSession session) async {
    createdSessions.add(session);
    _sessions.add(session);
  }

  @override
  Future<void> updateSession(fronting.FrontingSession session) async {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) _sessions[idx] = session;
  }

  @override
  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<fronting.FrontingSession?> getSessionById(String id) async =>
      _sessions.firstWhere((s) => s.id == id, orElse: () => throw StateError('not found'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_TrackingFrontingSessionRepo: ${invocation.memberName} not stubbed',
  );
}

// ---------------------------------------------------------------------------
// Bootstrap-counting PluralKitSyncService subclass
// ---------------------------------------------------------------------------

/// Wraps the real PluralKitSyncService but overrides the bootstrap methods so
/// we can count calls without actually executing the full sync pipeline.
class _BootstrapCountingSyncService extends PluralKitSyncService {
  _BootstrapCountingSyncService({
    required super.memberRepository,
    required super.frontingSessionRepository,
    required super.syncDao,
    required super.bus,
    required super.clientFactory,
    required super.tokenOverride,
  });

  int importSwitchesCallCount = 0;
  int pushSwitchesCallCount = 0;
  int liveFrontsOnlyCallCount = 0;
  int pushOverrideSwitchCallCount = 0;
  int advanceCursorCallCount = 0;

  List<String>? lastPushOverrideMemberIds;
  // Default return: a switch whose timestamp is deliberately different from
  // the caller-supplied `now` so the media heal cursor-advance test can assert PK's
  // stored timestamp is used (not the local clock).
  PKSwitch? pushOverrideSwitchReturn = PKSwitch(
    id: 'override-switch-id',
    timestamp: DateTime.utc(2026, 1, 1, 12),
    members: const [],
  );
  ({String switchId, DateTime timestamp})? lastAdvanceCursorArgs;

  @override
  Future<void> importSwitchesAfterLink({
    void Function(double fraction, String status)? onProgress,
  }) async {
    importSwitchesCallCount++;
  }

  @override
  Future<PkPushSwitchesResult> pushPendingSwitches({
    PkPushService? pushService,
    void Function(String message)? onStaleLink,
    bool allowDuringSync = false,
    PKSwitch? knownCurrentFronters,
    bool refreshMembersOnStaleLink = true,
  }) async {
    pushSwitchesCallCount++;
    return const PkPushSwitchesResult();
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    required PkSyncDirection direction,
    bool isManual = false,
    PKSwitch? knownCurrentFronters,
  }) async {
    liveFrontsOnlyCallCount++;
    return null;
  }

  @override
  Future<PKSwitch?> pushOverrideSwitch(
    List<String> localMemberIds,
    DateTime at,
  ) async {
    pushOverrideSwitchCallCount++;
    lastPushOverrideMemberIds = List.of(localMemberIds);
    return pushOverrideSwitchReturn;
  }

  @override
  Future<void> advanceImportCursorPast({
    required String switchId,
    required DateTime timestamp,
  }) async {
    advanceCursorCallCount++;
    lastAdvanceCursorArgs = (switchId: switchId, timestamp: timestamp);
  }

  bool get bootstrapRan =>
      importSwitchesCallCount > 0 ||
      pushSwitchesCallCount > 0 ||
      liveFrontsOnlyCallCount > 0;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

domain.Member _localMember(
  String id,
  String name, {
  String? pkUuid,
  String? pkId,
}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
      pluralkitId: pkId,
    );

fronting.FrontingSession _activeSession(String id, String memberId) =>
    fronting.FrontingSession(
      id: id,
      memberId: memberId,
      startTime: DateTime(2026, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _installSecureStorageStub();
  });

  // =========================================================================
  // Scenario (a): Fresh install, fully through wizard, no disagreement
  // =========================================================================

  test(
    '(a) fresh install → setToken needsDirection → confirmDirection needsMapping → acknowledgeMapping canAutoSync',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo([
        _localMember('l1', 'Alice', pkUuid: 'pk-uuid-alice', pkId: 'aaaaa'),
      ]);

      // PK has Alice fronting; Prism also has Alice fronting — sets agree, no
      // disagreement sheet.
      final client = _FakeClient(
        'S1',
        members: [
          const PKMember(id: 'aaaaa', uuid: 'pk-uuid-alice', name: 'Alice'),
        ],
      );
      client.currentFrontersResult = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const ['aaaaa'], // Alice
      );

      final frontingRepo = _TrackingFrontingSessionRepo([
        _activeSession('sess-alice', 'l1'),
      ]);

      final svc = _BootstrapCountingSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'test-token',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
          frontingMutationServiceProvider.overrideWithValue(
            FrontingMutationService(
              repository: frontingRepo,
              mutationRunner: MutationRunner.forDatabase(db),
              memberRepository: memberRepo,
            ),
          ),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Step 1: setToken
      await svc.setToken('test-token');
      expect(svc.state.needsDirection, isTrue,
          reason: 'After setToken with fresh system, needsDirection must be true');
      expect(svc.state.canAutoSync, isFalse);

      // Step 2: confirmDirection
      await svc.confirmDirection();
      expect(svc.state.needsMapping, isTrue,
          reason: 'After confirmDirection, needsMapping must be true');
      expect(svc.state.needsDirection, isFalse);
      expect(svc.state.canAutoSync, isFalse);

      // Step 3: acknowledgeMapping (simulates the mapping screen's apply
      // completion path when sets match → PkMappingApplyOutcomeApplied)
      await svc.acknowledgeMapping();
      expect(svc.state.canAutoSync, isTrue,
          reason: 'After acknowledgeMapping, canAutoSync must be true');
      expect(svc.state.needsMapping, isFalse);
      expect(svc.state.needsDirection, isFalse);

      // Verify state is persisted to DAO.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.directionConfirmed, isTrue);
      expect(row.mappingAcknowledged, isTrue);
      expect(row.isConnected, isTrue);
    },
  );

  // =========================================================================
  // Scenario (b): Fresh install with active-fronter disagreement
  // =========================================================================

  test(
    '(b) fresh install with disagreement → applyFronterResolution writes local sessions, pushes to PK, advances cursor, runs bootstrap',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Local members WITHOUT pre-existing PK links — simulates a fresh install
      // where the user hasn't yet gone through mapping. The mapping controller's
      // build() auto-suggests PkLinkDecision for exact name matches and
      // PkImportDecision for others. After apply() the applier writes the PK
      // UUID/ID onto the local member so applyFronterResolution can resolve them
      // back to PK short IDs for the override push.
      final memberRepo = _FakeMemberRepo([
        _localMember('l1', 'Alice'),
        _localMember('l2', 'Bob'),
      ]);

      // Prism: Alice (l1) is fronting. PK: Bob (bbbbb) is fronting.
      // This creates a disagreement after mapping (Alice vs Bob).
      final client = _FakeClient(
        'S1',
        members: [
          const PKMember(id: 'aaaaa', uuid: 'pk-uuid-alice', name: 'Alice'),
          const PKMember(id: 'bbbbb', uuid: 'pk-uuid-bob', name: 'Bob'),
        ],
      );
      // PK currently has Bob fronting.
      client.currentFrontersResult = PKSwitch(
        id: 'sw-pk-bob',
        timestamp: DateTime(2026, 1, 1),
        members: const ['bbbbb'], // Bob only in PK (short ID)
      );

      // Local: Alice is active.
      final frontingRepo = _TrackingFrontingSessionRepo([
        _activeSession('sess-alice', 'l1'),
      ]);

      final svc = _BootstrapCountingSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'test-token',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
          frontingMutationServiceProvider.overrideWithValue(
            FrontingMutationService(
              repository: frontingRepo,
              mutationRunner: MutationRunner.forDatabase(db),
              memberRepository: memberRepo,
            ),
          ),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Step 1: setToken + confirmDirection (puts us into needsMapping)
      await svc.setToken('test-token');
      await svc.confirmDirection();
      expect(svc.state.needsMapping, isTrue,
          reason: 'Precondition: must be in needsMapping after confirmDirection');

      // Set bidirectional direction so disagreement is actionable.
      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);

      // Load controller state — build() fetches PK members and auto-suggests
      // PkLinkDecision for Alice (exact name match) and Bob (exact name match).
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      // Step 2: apply() — runs the mapping applier (links Alice→aaaaa and
      // Bob→bbbbb), then detects disagreement (Alice local vs Bob PK) and
      // returns NeedsFronterResolution.
      final outcome = await ctrl.apply();
      expect(
        outcome,
        isA<PkMappingApplyOutcomeNeedsFronterResolution>(),
        reason: 'Disagreement (Alice local vs Bob PK) must produce NeedsFronterResolution',
      );
      expect(svc.bootstrapRan, isFalse,
          reason: 'Bootstrap must NOT run before fronter resolution');

      final resolution = outcome as PkMappingApplyOutcomeNeedsFronterResolution;
      // Local set has Alice (l1) fronting.
      expect(resolution.localFronterMemberIds, contains('l1'));
      // PK projected set: bbbbb → Bob (l2) via the just-applied PkLinkDecision.
      expect(resolution.pkFronterMemberIds, contains('l2'),
          reason: 'bbbbb must map to l2 through the Bob PkLinkDecision');
      expect(resolution.direction, PkSyncDirection.bidirectional);

      // Step 3: applyFronterResolution — user picks co-front (both Alice + Bob).
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1', 'l2'},
        direction: resolution.direction,
        mode: resolution.mode,
        pkCurrentSwitch: resolution.pkCurrentSwitch,
      );

      // Assert: Alice session NOT ended (she's in the chosen set).
      expect(
        frontingRepo.endedSessionIds,
        isNot(contains('sess-alice')),
        reason: 'Alice is in chosen set — her session must not be ended',
      );

      // Assert: Bob has a new open session.
      expect(
        frontingRepo.createdSessions.any((s) => s.memberId == 'l2'),
        isTrue,
        reason: 'Bob was not fronting → a new session must be created for l2',
      );

      // Assert: exactly one open session per chosen member at end.
      final finalActive = await frontingRepo.getAllActiveSessionsUnfiltered();
      final activeMemberIds = finalActive.map((s) => s.memberId).toSet();
      expect(activeMemberIds, containsAll(['l1', 'l2']),
          reason: 'Both Alice and Bob must have exactly one open session');

      // Assert: PK push happened (pushOverrideSwitch was called).
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(1),
        reason: 'pushOverrideSwitch must be called once for bidirectional + non-empty chosen set',
      );
      expect(
        svc.lastPushOverrideMemberIds,
        containsAll(['l1', 'l2']),
        reason: 'pushOverrideSwitch must receive both chosen local member IDs',
      );

      // Assert: import cursor advanced after successful push.
      expect(
        svc.advanceCursorCallCount,
        equals(1),
        reason: 'advanceImportCursorPast must be called once after successful push',
      );
      expect(
        svc.lastAdvanceCursorArgs?.switchId,
        equals('override-switch-id'),
        reason: 'Cursor must be advanced to the new switch ID',
      );
      // media heal: cursor timestamp must be PK's stored timestamp, NOT the local
      // `DateTime.now()` the caller passed into createSwitch. The fake
      // returns a switch whose timestamp is deliberately fixed at
      // 2026-01-01T12:00:00Z so we can assert that exact value flows
      // through advanceImportCursorPast.
      expect(
        svc.lastAdvanceCursorArgs?.timestamp,
        equals(DateTime.utc(2026, 1, 1, 12)),
        reason: "Cursor timestamp must be PK's stored timestamp, not local "
            'DateTime.now(). See bug media heal.',
      );

      // Assert: bootstrap ran after resolution.
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap must run after fronter resolution',
      );

      // Assert: state is now canAutoSync (mapping was acknowledged by apply()).
      expect(svc.state.canAutoSync, isTrue,
          reason: 'apply() acknowledged mapping → canAutoSync after resolution');
    },
  );

  // =========================================================================
  // Scenario (c): Same-system reconnect (token rotation)
  // =========================================================================

  test(
    '(c) same-system token rotation → state immediately canAutoSync, linkedAt unchanged, flags preserved',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final t0 = DateTime(2025, 6, 1, 12, 0, 0).toUtc();

      // Seed the DAO with a fully set-up row for system S1.
      await db.pluralKitSyncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          systemId: const Value('S1'),
          isConnected: const Value(true),
          directionConfirmed: const Value(true),
          mappingAcknowledged: const Value(true),
          linkedAt: Value(t0),
        ),
      );

      final memberRepo = _FakeMemberRepo([]);
      final frontingRepo = _TrackingFrontingSessionRepo([]);

      // Client returns the SAME system id (S1).
      final client = _FakeClient('S1');

      final svc = _BootstrapCountingSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'new-token-same-system',
      );

      // Action: setToken with a new token that resolves to the same system.
      await svc.setToken('new-token-same-system');

      // Assert: state immediately canAutoSync (no wizard needed).
      expect(svc.state.isConnected, isTrue);
      expect(svc.state.directionConfirmed, isTrue);
      expect(svc.state.mappingAcknowledged, isTrue);
      expect(svc.state.canAutoSync, isTrue,
          reason: 'Same-system reconnect must skip the wizard and be canAutoSync immediately');
      expect(svc.state.needsDirection, isFalse);
      expect(svc.state.needsMapping, isFalse);

      // Assert: linkedAt unchanged.
      expect(
        svc.state.linkedAt?.millisecondsSinceEpoch,
        equals(t0.millisecondsSinceEpoch),
        reason: 'linkedAt must be preserved on same-system token rotation',
      );

      // Verify DAO row matches.
      final row = await db.pluralKitSyncDao.getSyncState();
      expect(row.directionConfirmed, isTrue);
      expect(row.mappingAcknowledged, isTrue);
      expect(
        row.linkedAt?.millisecondsSinceEpoch,
        equals(t0.millisecondsSinceEpoch),
      );
    },
  );

  // =========================================================================
  // Scenario (d): Decide-later path
  // =========================================================================

  test(
    '(d) decide-later: deferBootstrap sets SharedPreferences flag, canAutoSync=true, no bootstrap calls',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final memberRepo = _FakeMemberRepo([
        _localMember('l1', 'Alice', pkUuid: 'pk-uuid-alice', pkId: 'aaaaa'),
      ]);

      // Prism: Alice fronting. PK: nobody. Creates disagreement so apply()
      // returns NeedsFronterResolution.
      final client = _FakeClient(
        'S1',
        members: [
          const PKMember(id: 'aaaaa', uuid: 'pk-uuid-alice', name: 'Alice'),
        ],
      );
      client.currentFrontersResult = PKSwitch(
        id: 'sw-nobody',
        timestamp: DateTime(2026, 1, 1),
        members: const [], // nobody fronting in PK
      );

      final frontingRepo = _TrackingFrontingSessionRepo([
        _activeSession('sess-alice', 'l1'),
      ]);

      final svc = _BootstrapCountingSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'test-token',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
          frontingMutationServiceProvider.overrideWithValue(
            FrontingMutationService(
              repository: frontingRepo,
              mutationRunner: MutationRunner.forDatabase(db),
              memberRepository: memberRepo,
            ),
          ),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Setup: setToken → confirmDirection → apply → NeedsFronterResolution
      await svc.setToken('test-token');
      await svc.confirmDirection();
      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);

      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();
      expect(
        outcome,
        isA<PkMappingApplyOutcomeNeedsFronterResolution>(),
        reason: 'Precondition: disagreement must produce NeedsFronterResolution',
      );
      // apply() has acknowledged the mapping — so needsMapping should be false.
      expect(svc.state.needsMapping, isFalse,
          reason: 'apply() calls acknowledgeMapping regardless of outcome');
      expect(svc.state.canAutoSync, isTrue,
          reason: 'mapping acknowledged → canAutoSync is already true before deferBootstrap');

      // Reset bootstrap count so we can confirm deferBootstrap adds zero calls.
      final bootstrapBeforeDefer = svc.bootstrapRan;
      expect(bootstrapBeforeDefer, isFalse,
          reason: 'Bootstrap must not have run before deferBootstrap');

      // Action: call deferBootstrap() instead of applyFronterResolution.
      await ctrl.deferBootstrap();

      // Assert: canAutoSync remains true.
      expect(svc.state.canAutoSync, isTrue,
          reason: 'canAutoSync must remain true after deferBootstrap');

      // Assert: SharedPreferences flag set for this systemId.
      final prefs = await SharedPreferences.getInstance();
      const systemId = 'S1'; // from client.getSystem()
      final key = PkPrefsKeys.firstSyncDeferred(systemId);
      expect(
        prefs.getBool(key),
        isTrue,
        reason: 'deferBootstrap must set $key=true in SharedPreferences',
      );

      // Assert: no bootstrap calls happened.
      expect(
        svc.bootstrapRan,
        isFalse,
        reason: 'deferBootstrap must not trigger any bootstrap methods',
      );
    },
  );

  // =========================================================================
  // Scenario (e): ephemeral lane regression — already-mapped member included in projection
  // =========================================================================

  test(
    '(e) ephemeral lane: already-mapped local member (pluralkitId set, no Link decision) '
    'is correctly projected into pkFronterMemberIds — no false disagreement',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Bob is ALREADY linked from a prior setup — `pluralkitId` is set on
      // the local row and no PkLinkDecision will be auto-generated for him.
      // Alice is unlinked and will get a PkLinkDecision auto-suggested.
      final memberRepo = _FakeMemberRepo([
        _localMember('l1', 'Alice'),
        _localMember(
          'l2',
          'Bob',
          pkUuid: 'pk-uuid-bob',
          pkId: 'bbbbb',
        ),
      ]);

      // PK has both members. The fake's getMembers() returns the full list;
      // the mapping screen will suggest a link for Alice only (since Bob is
      // already linked).
      final client = _FakeClient(
        'S1',
        members: [
          const PKMember(id: 'aaaaa', uuid: 'pk-uuid-alice', name: 'Alice'),
          const PKMember(id: 'bbbbb', uuid: 'pk-uuid-bob', name: 'Bob'),
        ],
      );
      // PK currently has Bob fronting (the already-linked member).
      client.currentFrontersResult = PKSwitch(
        id: 'sw-pk-bob',
        timestamp: DateTime(2026, 1, 1),
        members: const ['bbbbb'],
      );

      // Local: Bob is also fronting → sets must compare EQUAL after the ephemeral lane
      // fix. Before the fix, the projection couldn't resolve bbbbb → l2
      // (no Link decision exists for already-mapped Bob), so the bug
      // produced a false disagreement.
      final frontingRepo = _TrackingFrontingSessionRepo([
        _activeSession('sess-bob', 'l2'),
      ]);

      final svc = _BootstrapCountingSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'test-token',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(memberRepo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
          frontingMutationServiceProvider.overrideWithValue(
            FrontingMutationService(
              repository: frontingRepo,
              mutationRunner: MutationRunner.forDatabase(db),
              memberRepository: memberRepo,
            ),
          ),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await svc.setToken('test-token');
      await svc.confirmDirection();
      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);

      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      // After the ephemeral lane fix the projection picks up Bob via the DB-side
      // `pluralkitId` lookup, sets compare equal, and apply() proceeds
      // straight into the bootstrap without returning a resolution.
      expect(
        outcome,
        isNot(isA<PkMappingApplyOutcomeNeedsFronterResolution>()),
        reason:
            'ephemeral lane: already-mapped local fronter must be projected into PK set; '
            'sets must compare equal → no false disagreement.',
      );
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'No disagreement → bootstrap must run inline.',
      );
    },
  );
}
