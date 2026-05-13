// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as fronting;
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
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart'
    show PkApplyOutcome;
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _installSecureStorageStub() {
  final store = <String, String?>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          switch (call.method) {
            case 'write':
              final key = call.arguments['key'] as String;
              store[key] = call.arguments['value'] as String?;
              return null;
            case 'read':
              final key = call.arguments['key'] as String;
              return store[key];
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

domain.Member _local(String id, String name, {String? pkUuid, String? pkId}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
      pluralkitId: pkId,
    );

// ---------------------------------------------------------------------------
// Fake member repository
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
  Future<void> deleteMember(String id) async => _byId.remove(id);

  @override
  Future<int> getCount() async => _byId.length;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _byId[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

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
// Fronting session repo stubs
// ---------------------------------------------------------------------------

/// Fronting session repo with configurable active sessions.
class _StubFrontingSessionRepo implements FrontingSessionRepository {
  final List<fronting.FrontingSession> activeSessions;

  _StubFrontingSessionRepo({this.activeSessions = const []});

  @override
  Future<List<fronting.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      activeSessions;

  @override
  Future<List<fronting.FrontingSession>> getAllSessions() async => const [];

  @override
  Future<List<fronting.FrontingSession>> getDeletedLinkedSessions() async =>
      const [];

  @override
  Future<List<fronting.FrontingSession>> getFrontingSessions() async => const [];

  @override
  Future<List<fronting.FrontingSession>> getActiveSessions() async =>
      activeSessions;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'StubFrontingSessionRepo: ${invocation.memberName} not stubbed',
  );
}

/// Fronting session repo that tracks endSession + createSession calls.
/// Used by the applyFronterResolution tests where the controller mutates
/// local sessions via FrontingMutationService.
class _TrackingFrontingSessionRepo implements FrontingSessionRepository {
  final List<fronting.FrontingSession> _sessions;

  /// IDs of sessions ended via [endSession].
  final List<String> endedSessionIds = [];

  /// Sessions added via [createSession].
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
  Future<List<fronting.FrontingSession>> getDeletedLinkedSessions() async => const [];

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
    'TrackingFrontingSessionRepo: ${invocation.memberName} not stubbed',
  );
}

// ---------------------------------------------------------------------------
// PluralKitClient fakes
// ---------------------------------------------------------------------------

/// A client that lets the test control what [getCurrentFronters] returns.
class _ConfigurableClient extends PluralKitClient {
  final List<PKMember> members;
  PKSwitch? currentFrontersResult;
  int getCurrentFrontersCallCount = 0;
  int getSwitchesCallCount = 0;
  int createSwitchCallCount = 0;

  /// Member IDs passed to [createSwitch] (captured for assertions).
  List<String>? lastCreateSwitchMemberIds;

  /// The switch ID returned by [createSwitch]. Override in tests that need a
  /// specific ID.
  String createSwitchReturnId = 'new-switch-id';

  /// If set, [getCurrentFronters] throws this instead of returning a value.
  Object? getCurrentFrontersError;

  _ConfigurableClient(this.members)
    : super(token: 'fake', httpClient: http.Client());

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test');

  @override
  Future<List<PKMember>> getMembers() async => members;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    final count = members.length + 1;
    final created = PKMember(
      id: 'id$count',
      uuid: 'uuid$count',
      name: data['name'] as String,
    );
    members.add(created);
    return created;
  }

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
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
    getSwitchesCallCount++;
    return const [];
  }

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    getCurrentFrontersCallCount++;
    final err = getCurrentFrontersError;
    if (err != null) throw err;
    return currentFrontersResult;
  }

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  void dispose() {}
}

/// A sync service subclass that lets the test assert bootstrap was or wasn't
/// called (by counting calls to importSwitchesAfterLink, pushPendingSwitches,
/// and syncLiveFrontersOnly).
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

  /// Member IDs passed to the last [pushOverrideSwitch] call.
  List<String>? lastPushOverrideMemberIds;

  /// The full switch returned by [pushOverrideSwitch]. Override to null to
  /// simulate a failure. Tests that care about the cursor timestamp should
  /// set this to a switch whose `timestamp` differs from the caller's `now`
  /// so cursor-advance assertions are unambiguous.
  PKSwitch? pushOverrideSwitchReturn = PKSwitch(
    id: 'override-switch-id',
    timestamp: DateTime.utc(2026, 1, 1, 12),
    members: const [],
  );

  /// Last (switchId, timestamp) pair passed to [advanceImportCursorPast].
  ({String switchId, DateTime timestamp})? lastAdvanceCursorArgs;

  @override
  Future<void> importSwitchesAfterLink({
    void Function(double fraction, String status)? onProgress,
  }) async {
    importSwitchesCallCount++;
    // Don't call super — we just count the call.
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

  /// True if any bootstrap method was invoked at least once.
  bool get bootstrapRan =>
      importSwitchesCallCount > 0 ||
      pushSwitchesCallCount > 0 ||
      liveFrontsOnlyCallCount > 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeMemberRepo repo;
  late _ConfigurableClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _installSecureStorageStub();
    db = AppDatabase(NativeDatabase.memory());
    repo = _FakeMemberRepo([
      _local('l1', 'Alice'),
      _local('l2', 'Bob'),
    ]);
    client = _ConfigurableClient([
      const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  // Helper to build a container with the counting sync service and configurable
  // fronting session repo.
  (ProviderContainer, _BootstrapCountingSyncService) makeContainer({
    required _StubFrontingSessionRepo frontingRepo,
    PkSyncDirection direction = PkSyncDirection.bidirectional,
    PkSyncMode mode = PkSyncMode.fullSync,
  }) {
    final svc = _BootstrapCountingSyncService(
      memberRepository: repo,
      frontingSessionRepository: frontingRepo,
      syncDao: PluralKitSyncDao(db),
      bus: PkSyncEventBus(),
      clientFactory: (_) => client,
      tokenOverride: 'fake',
    );
    // setToken is sync-setup — we'll call it in the test, not here.
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        memberRepositoryProvider.overrideWithValue(repo),
        pluralKitSyncServiceProvider.overrideWithValue(svc),
        frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
        frontingMigrationWritesBlockedProvider.overrideWithValue(false),
      ],
    );
    return (container, svc);
  }

  // ---------------------------------------------------------------------------
  // Scenario (c): per-decision failures → PkMappingApplyOutcomeFailed
  // ---------------------------------------------------------------------------

  test(
    '(c) decision failures → apply() returns PkMappingApplyOutcomeFailed',
    () async {
      // Make createMember throw so all push decisions fail.
      client = _ConfigurableClient([
        const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
      ]);
      // Override client to throw on createMember.
      final failingClient = _ThrowingCreateClient([
        const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
      ]);
      // repo has l1 (Alice) and l2 (Bob, unlinked → push-new will fail).
      final frontingRepo = _StubFrontingSessionRepo();
      final svc = _BootstrapCountingSyncService(
        memberRepository: repo,
        frontingSessionRepository: frontingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => failingClient,
        tokenOverride: 'fake',
      );
      await svc.setToken('fake');

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(repo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      expect(
        outcome,
        isA<PkMappingApplyOutcomeFailed>(),
        reason: 'Decision failures should return PkMappingApplyOutcomeFailed',
      );
      final failed = outcome as PkMappingApplyOutcomeFailed;
      expect(
        failed.failures.isNotEmpty,
        isTrue,
        reason: 'Failures list must be non-empty',
      );
      expect(
        failed.failures.every((r) => r.outcome == PkApplyOutcome.failed),
        isTrue,
      );
      // Bootstrap must NOT run on failure.
      expect(svc.bootstrapRan, isFalse, reason: 'Bootstrap should not run on failure');
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario (a): fronter sets match → PkMappingApplyOutcomeApplied + bootstrap
  // ---------------------------------------------------------------------------

  test(
    '(a) fronter sets match → apply() returns PkMappingApplyOutcomeApplied; bootstrap ran',
    () async {
      // Alice (l1) is currently fronting in Prism.
      // PK also has Alice fronting (short id 'aaaaa').
      final frontingRepo = _StubFrontingSessionRepo(
        activeSessions: [
          fronting.FrontingSession(
            id: 'sess-1',
            memberId: 'l1',
            startTime: DateTime(2026, 1, 1),
          ),
        ],
      );
      // PK current fronters = Alice.
      client.currentFrontersResult = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const ['aaaaa'], // Alice's PK short ID
      );

      final (container, svc) = makeContainer(frontingRepo: frontingRepo);
      addTearDown(container.dispose);
      await svc.setToken('fake');

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      expect(
        outcome,
        isA<PkMappingApplyOutcomeApplied>(),
        reason: 'Matching fronter sets should return PkMappingApplyOutcomeApplied',
      );
      // Bootstrap must have run.
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap should run when sets match',
      );
      // Mapping acknowledged.
      expect(svc.state.needsMapping, isFalse);
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario (b): fronter sets differ + bidirectional → NeedsFronterResolution;
  //               bootstrap NOT called
  // ---------------------------------------------------------------------------

  test(
    '(b) fronter sets differ + bidirectional → NeedsFronterResolution; no bootstrap',
    () async {
      // Prism: Alice (l1) fronting.
      // PK: nobody fronting (null switch).
      final frontingRepo = _StubFrontingSessionRepo(
        activeSessions: [
          fronting.FrontingSession(
            id: 'sess-1',
            memberId: 'l1',
            startTime: DateTime(2026, 1, 1),
          ),
        ],
      );
      // PK has no fronters.
      client.currentFrontersResult = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final (container, svc) = makeContainer(frontingRepo: frontingRepo);
      addTearDown(container.dispose);
      await svc.setToken('fake');

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      expect(
        outcome,
        isA<PkMappingApplyOutcomeNeedsFronterResolution>(),
        reason: 'Differing sets + bidirectional should return NeedsFronterResolution',
      );
      final needsRes = outcome as PkMappingApplyOutcomeNeedsFronterResolution;
      // Local set has Alice.
      expect(needsRes.localFronterMemberIds, contains('l1'));
      // PK projected set is empty.
      expect(needsRes.pkFronterMemberIds, isEmpty);
      expect(needsRes.direction, PkSyncDirection.bidirectional);

      // Bootstrap must NOT have run.
      expect(
        svc.bootstrapRan,
        isFalse,
        reason: 'Bootstrap must not run when returning NeedsFronterResolution',
      );
      // C5: mapping is NOT yet acknowledged on the NeedsFronterResolution
      // path. Acknowledgement is deferred until applyFronterResolution() or
      // deferBootstrap() completes — otherwise canAutoSync would flip true
      // while the "Who's fronting?" sheet is being shown and auto-poll could
      // fire before the user has decided.
      //
      // We check mappingAcknowledged directly (not needsMapping) because
      // this test container never calls confirmDirection(), so
      // directionConfirmed=false and needsMapping is always false via that
      // composite gate.
      expect(
        svc.state.mappingAcknowledged,
        isFalse,
        reason: 'mappingAcknowledged must stay false on the '
            'NeedsFronterResolution path — otherwise auto-poll could fire '
            'while the "Who\'s fronting?" sheet is pending',
      );
      expect(
        svc.state.canAutoSync,
        isFalse,
        reason: 'canAutoSync must stay false while the resolution sheet '
            'is pending',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario (d): getCurrentFronters network failure → PkMappingApplyOutcomeApplied
  // ---------------------------------------------------------------------------

  test(
    '(d) getCurrentFronters network failure → PkMappingApplyOutcomeApplied; bootstrap ran',
    () async {
      // Prism: Alice fronting, but PK call throws a SocketException.
      final frontingRepo = _StubFrontingSessionRepo(
        activeSessions: [
          fronting.FrontingSession(
            id: 'sess-1',
            memberId: 'l1',
            startTime: DateTime(2026, 1, 1),
          ),
        ],
      );
      client.getCurrentFrontersError = const SocketException('no network');

      final (container, svc) = makeContainer(frontingRepo: frontingRepo);
      addTearDown(container.dispose);
      await svc.setToken('fake');

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      expect(
        outcome,
        isA<PkMappingApplyOutcomeApplied>(),
        reason: 'Network failure on getCurrentFronters should return Applied',
      );
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap should run despite network failure',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario (e): direction=disabled → PkMappingApplyOutcomeApplied (disagreement
  //               not actionable)
  // ---------------------------------------------------------------------------

  test(
    '(e) direction=disabled → PkMappingApplyOutcomeApplied even if sets differ',
    () async {
      // Prism: Alice fronting. PK: nobody. But direction is disabled.
      final frontingRepo = _StubFrontingSessionRepo(
        activeSessions: [
          fronting.FrontingSession(
            id: 'sess-1',
            memberId: 'l1',
            startTime: DateTime(2026, 1, 1),
          ),
        ],
      );
      client.currentFrontersResult = PKSwitch(
        id: 'sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final (container, svc) = makeContainer(
        frontingRepo: frontingRepo,
        direction: PkSyncDirection.disabled,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.disabled);
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();

      expect(
        outcome,
        isA<PkMappingApplyOutcomeApplied>(),
        reason: 'direction=disabled means disagreement is not actionable → Applied',
      );
      // Direction=disabled means bootstrap body does nothing (no pull, no push).
      // The important assertion is that we returned Applied, not NeedsFronterResolution.
      expect(svc.bootstrapRan, isFalse, reason: 'disabled direction has nothing to bootstrap');
    },
  );

  // ---------------------------------------------------------------------------
  // applyFronterResolution test helpers
  // ---------------------------------------------------------------------------

  // Builds a container wired for applyFronterResolution: tracking fronting
  // repo, real FrontingMutationService (needs DB for MutationRunner), and the
  // bootstrap-counting sync service with pushOverrideSwitch stubbed.
  (ProviderContainer, _BootstrapCountingSyncService) makeResolutionContainer({
    required _TrackingFrontingSessionRepo trackingRepo,
    PkSyncDirection direction = PkSyncDirection.bidirectional,
    PkSyncMode mode = PkSyncMode.fullSync,
  }) {
    final svc = _BootstrapCountingSyncService(
      memberRepository: repo,
      frontingSessionRepository: trackingRepo,
      syncDao: PluralKitSyncDao(db),
      bus: PkSyncEventBus(),
      clientFactory: (_) => client,
      tokenOverride: 'fake',
    );
    final mutSvc = FrontingMutationService(
      repository: trackingRepo,
      mutationRunner: MutationRunner.forDatabase(db),
      memberRepository: repo,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        memberRepositoryProvider.overrideWithValue(repo),
        pluralKitSyncServiceProvider.overrideWithValue(svc),
        frontingSessionRepositoryProvider.overrideWithValue(trackingRepo),
        frontingMutationServiceProvider.overrideWithValue(mutSvc),
        frontingMigrationWritesBlockedProvider.overrideWithValue(false),
      ],
    );
    return (container, svc);
  }

  // ---------------------------------------------------------------------------
  // T9 scenario 1: chosen [A,B], bidirectional → write local + push + cursor + bootstrap
  // ---------------------------------------------------------------------------

  test(
    'applyFronterResolution(chosen=[A,B], bidirectional) → ends non-chosen sessions, starts B, pushes to PK, advances cursor, runs bootstrap',
    () async {
      // Local: A (l1) is fronting. B (l2) is not.
      // Both l1 and l2 are linked to PK members so pushOverrideSwitch can
      // resolve them.
      repo = _FakeMemberRepo([
        _local('l1', 'Alice', pkUuid: 'pk-uuid-alice', pkId: 'aaaaa'),
        _local('l2', 'Bob', pkUuid: 'pk-uuid-bob', pkId: 'bbbbb'),
      ]);
      client = _ConfigurableClient([
        const PKMember(id: 'aaaaa', uuid: 'pk-uuid-alice', name: 'Alice'),
        const PKMember(id: 'bbbbb', uuid: 'pk-uuid-bob', name: 'Bob'),
      ]);
      client.createSwitchReturnId = 'override-switch-123';

      final activeSession = fronting.FrontingSession(
        id: 'sess-alice',
        memberId: 'l1',
        startTime: DateTime(2026, 1, 1),
      );
      final trackingRepo = _TrackingFrontingSessionRepo([activeSession]);

      final (container, svc) = makeResolutionContainer(
        trackingRepo: trackingRepo,
        direction: PkSyncDirection.bidirectional,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      final pkSwitch = PKSwitch(
        id: 'pk-sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const ['bbbbb'],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1', 'l2'},
        direction: PkSyncDirection.bidirectional,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // (a) Local: Alice's session NOT ended (already in chosen set).
      expect(
        trackingRepo.endedSessionIds,
        isNot(contains('sess-alice')),
        reason: 'Alice is in chosen set — session must not be ended',
      );
      // Bob should have a new session created.
      expect(
        trackingRepo.createdSessions.any((s) => s.memberId == 'l2'),
        isTrue,
        reason: 'Bob was not fronting → startFronting should create a session for l2',
      );

      // (b) PK push: pushOverrideSwitch called with chosen member IDs.
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(1),
        reason: 'pushOverrideSwitch must be called once for bidirectional + non-empty set',
      );
      expect(
        svc.lastPushOverrideMemberIds,
        containsAll(['l1', 'l2']),
        reason: 'pushOverrideSwitch should receive all chosen local member IDs',
      );

      // (c) Cursor advanced.
      expect(
        svc.advanceCursorCallCount,
        equals(1),
        reason: 'advanceImportCursorPast must be called once after successful push',
      );
      expect(
        svc.lastAdvanceCursorArgs?.switchId,
        equals('override-switch-id'), // return value from stub
        reason: 'Cursor must be advanced to the new switch ID',
      );

      // (d) Bootstrap ran.
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap must run after fronter resolution',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // T9 scenario 2: empty chosen set, bidirectional → end all sessions, no push, bootstrap runs
  // ---------------------------------------------------------------------------

  test(
    'applyFronterResolution(chosen={}, bidirectional) → ends all active sessions, pushes empty switch to PK, bootstrap runs',
    () async {
      final activeSession = fronting.FrontingSession(
        id: 'sess-alice',
        memberId: 'l1',
        startTime: DateTime(2026, 1, 1),
      );
      final trackingRepo = _TrackingFrontingSessionRepo([activeSession]);

      final (container, svc) = makeResolutionContainer(
        trackingRepo: trackingRepo,
        direction: PkSyncDirection.bidirectional,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      final pkSwitch = PKSwitch(
        id: 'pk-sw-empty',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {}, // empty — user chose "Leave no one fronting"
        direction: PkSyncDirection.bidirectional,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // Alice's session must be ended.
      expect(
        trackingRepo.endedSessionIds,
        contains('sess-alice'),
        reason: 'Alice is NOT in empty chosen set → session must be ended',
      );

      // C1: Empty chosen set MUST still push to PK when push is enabled —
      // PK's API accepts `members: []` to clear the current front, and
      // without the push the bootstrap pull would re-apply PK's old
      // fronters and silently undo the user's clear.
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(1),
        reason: 'Empty chosen set must still push to PK when push is enabled',
      );
      expect(
        svc.lastPushOverrideMemberIds,
        isEmpty,
        reason: 'Push payload for empty resolution must be an empty list',
      );
      expect(
        svc.advanceCursorCallCount,
        equals(1),
        reason: 'Cursor advances on successful empty push too',
      );

      // Bootstrap still runs.
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap must run even when chosen set is empty',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // T9 scenario 3: chosen=[A], pullOnly → creates local session, no PK push, bootstrap runs
  // ---------------------------------------------------------------------------

  test(
    'applyFronterResolution(chosen={A}, pullOnly) → creates local session, no PK push, bootstrap runs',
    () async {
      // Local: empty. PK has B fronting. User chose A locally.
      final trackingRepo = _TrackingFrontingSessionRepo([]); // no active sessions

      final (container, svc) = makeResolutionContainer(
        trackingRepo: trackingRepo,
        direction: PkSyncDirection.pullOnly,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      final pkSwitch = PKSwitch(
        id: 'pk-sw-b',
        timestamp: DateTime(2026, 1, 1),
        members: const ['bbbbb'],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1'}, // chose Alice locally
        direction: PkSyncDirection.pullOnly,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // Local session created for l1.
      expect(
        trackingRepo.createdSessions.any((s) => s.memberId == 'l1'),
        isTrue,
        reason: 'l1 was not fronting → a new session should be created',
      );

      // No PK push (pullOnly.pushEnabled == false).
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(0),
        reason: 'pullOnly direction must NOT push to PK',
      );
      expect(
        svc.advanceCursorCallCount,
        equals(0),
        reason: 'No cursor advance on pullOnly',
      );

      // Bootstrap runs.
      expect(
        svc.bootstrapRan,
        isTrue,
        reason: 'Bootstrap must run after resolution',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // M3: pushOverrideSwitch returns null (network failure) → no cursor advance,
  //     local writes still happened, bootstrap still ran. Includes both the
  //     non-empty and empty (C1) chosen-set sub-cases.
  // ---------------------------------------------------------------------------

  test(
    'M3 (non-empty): pushOverrideSwitch null → local writes + bootstrap still run; no cursor advance',
    () async {
      repo = _FakeMemberRepo([
        _local('l1', 'Alice', pkUuid: 'pk-uuid-alice', pkId: 'aaaaa'),
      ]);

      final trackingRepo = _TrackingFrontingSessionRepo([]); // nobody fronting

      final (container, svc) = makeResolutionContainer(
        trackingRepo: trackingRepo,
        direction: PkSyncDirection.bidirectional,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      // Simulate network failure on push.
      svc.pushOverrideSwitchReturn = null;

      final pkSwitch = PKSwitch(
        id: 'pk-sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1'},
        direction: PkSyncDirection.bidirectional,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // Push attempted.
      expect(svc.pushOverrideSwitchCallCount, equals(1));
      // Cursor NOT advanced (null return).
      expect(
        svc.advanceCursorCallCount,
        equals(0),
        reason: 'Null push must NOT advance the cursor',
      );
      // Local writes still happened.
      expect(
        trackingRepo.createdSessions.any((s) => s.memberId == 'l1'),
        isTrue,
        reason: 'Local write must proceed even when push fails',
      );
      // Bootstrap still ran.
      expect(svc.bootstrapRan, isTrue);
    },
  );

  test(
    'M3 (empty/C1): pushOverrideSwitch null on empty resolution → local end happens; no cursor advance',
    () async {
      // C1 path: empty chosen set, push enabled. Network fails.
      final activeSession = fronting.FrontingSession(
        id: 'sess-alice',
        memberId: 'l1',
        startTime: DateTime(2026, 1, 1),
      );
      final trackingRepo = _TrackingFrontingSessionRepo([activeSession]);

      final (container, svc) = makeResolutionContainer(
        trackingRepo: trackingRepo,
        direction: PkSyncDirection.bidirectional,
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      svc.pushOverrideSwitchReturn = null;

      final pkSwitch = PKSwitch(
        id: 'pk-sw-empty',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {},
        direction: PkSyncDirection.bidirectional,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // C1: empty push was attempted (the whole point of the fix).
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(1),
        reason: 'C1: empty chosen set must still attempt PK push',
      );
      expect(svc.lastPushOverrideMemberIds, isEmpty);
      // Null push → no cursor advance.
      expect(svc.advanceCursorCallCount, equals(0));
      // Local end still happened.
      expect(trackingRepo.endedSessionIds, contains('sess-alice'));
      // Bootstrap still ran.
      expect(svc.bootstrapRan, isTrue);
    },
  );

  // ---------------------------------------------------------------------------
  // M4: applyFronterResolution under frontingMigrationWritesBlocked → no-op
  //     (no push, no local writes, no cursor advance, no bootstrap)
  // ---------------------------------------------------------------------------

  test(
    'M4: applyFronterResolution under migration-blocked is a no-op',
    () async {
      final activeSession = fronting.FrontingSession(
        id: 'sess-alice',
        memberId: 'l1',
        startTime: DateTime(2026, 1, 1),
      );
      final trackingRepo = _TrackingFrontingSessionRepo([activeSession]);

      // Hand-build container so we can flip the migration override true.
      final svc = _BootstrapCountingSyncService(
        memberRepository: repo,
        frontingSessionRepository: trackingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'fake',
      );
      final mutSvc = FrontingMutationService(
        repository: trackingRepo,
        mutationRunner: MutationRunner.forDatabase(db),
        memberRepository: repo,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(repo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(trackingRepo),
          frontingMutationServiceProvider.overrideWithValue(mutSvc),
          // Migration is BLOCKED — fronting writes must not happen.
          frontingMigrationWritesBlockedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      final pkSwitch = PKSwitch(
        id: 'pk-sw-1',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final ctrl = container.read(pkMappingControllerProvider.notifier);
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1'},
        direction: PkSyncDirection.bidirectional,
        mode: PkSyncMode.fullSync,
        pkCurrentSwitch: pkSwitch,
      );

      // Nothing happens — same gate semantics as pushPendingSwitches.
      expect(
        svc.pushOverrideSwitchCallCount,
        equals(0),
        reason: 'Migration-blocked must skip PK push',
      );
      expect(
        svc.advanceCursorCallCount,
        equals(0),
        reason: 'Migration-blocked must skip cursor advance',
      );
      expect(
        trackingRepo.createdSessions,
        isEmpty,
        reason: 'Migration-blocked must skip local writes',
      );
      expect(
        trackingRepo.endedSessionIds,
        isEmpty,
        reason: 'Migration-blocked must skip local writes',
      );
      expect(
        svc.bootstrapRan,
        isFalse,
        reason: 'Migration-blocked must skip bootstrap',
      );
      expect(
        svc.state.mappingAcknowledged,
        isFalse,
        reason: 'Migration-blocked must not acknowledge the mapping',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // T10: deferBootstrap() — sets SharedPreferences flag; no bootstrap ran
  // ---------------------------------------------------------------------------

  test(
    'T10: deferBootstrap() sets pk_first_sync_deferred_<systemId> in SharedPreferences; no bootstrap ran',
    () async {
      // Arrange: outcome NeedsFronterResolution (sets differ).
      // Prism: Alice (l1) fronting. PK: nobody.
      final frontingRepo = _StubFrontingSessionRepo(
        activeSessions: [
          fronting.FrontingSession(
            id: 'sess-1',
            memberId: 'l1',
            startTime: DateTime(2026, 1, 1),
          ),
        ],
      );
      client.currentFrontersResult = PKSwitch(
        id: 'sw-defer',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final (container, svc) = makeContainer(frontingRepo: frontingRepo);
      addTearDown(container.dispose);
      await svc.setToken('fake');

      // setToken writes the system id (sys-1) from getSystem() into the DAO.
      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      final outcome = await ctrl.apply();
      expect(outcome, isA<PkMappingApplyOutcomeNeedsFronterResolution>(),
          reason: 'Precondition: outcome must be NeedsFronterResolution');

      // Act.
      await ctrl.deferBootstrap();

      // Assert: SharedPreferences must have the deferred-sync flag.
      final prefs = await SharedPreferences.getInstance();
      const key = 'pk_first_sync_deferred_sys-1';
      expect(
        prefs.getBool(key),
        isTrue,
        reason: 'deferBootstrap must persist the flag under $key',
      );

      // Assert: no bootstrap ran.
      expect(
        svc.bootstrapRan,
        isFalse,
        reason: 'deferBootstrap must not trigger any bootstrap methods',
      );

      // Assert: mapping was acknowledged by deferBootstrap() (C5 — the
      // acknowledgement is deferred until either applyFronterResolution() or
      // deferBootstrap() completes, since apply() only acknowledges on the
      // Applied outcome path when no resolution is needed).
      expect(
        svc.state.mappingAcknowledged,
        isTrue,
        reason: 'deferBootstrap must call acknowledgeMapping (C5)',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // T11: liveFrontsOnly cache pass-through — exactly 1 getCurrentFronters call
  // ---------------------------------------------------------------------------

  test(
    'T11: apply() + applyFronterResolution() with mode=liveFrontsOnly call getCurrentFronters exactly once',
    () async {
      // Arrange: outcome NeedsFronterResolution, liveFrontsOnly mode.
      // Prism: Alice (l1) fronting. PK: nobody → disagreement.
      final activeSession = fronting.FrontingSession(
        id: 'sess-alice',
        memberId: 'l1',
        startTime: DateTime(2026, 1, 1),
      );
      final trackingRepo = _TrackingFrontingSessionRepo([activeSession]);

      client.currentFrontersResult = PKSwitch(
        id: 'sw-live',
        timestamp: DateTime(2026, 1, 1),
        members: const [],
      );

      final svc = _BootstrapCountingSyncService(
        memberRepository: repo,
        frontingSessionRepository: trackingRepo,
        syncDao: PluralKitSyncDao(db),
        bus: PkSyncEventBus(),
        clientFactory: (_) => client,
        tokenOverride: 'fake',
      );
      final mutSvc = FrontingMutationService(
        repository: trackingRepo,
        mutationRunner: MutationRunner.forDatabase(db),
        memberRepository: repo,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(repo),
          pluralKitSyncServiceProvider.overrideWithValue(svc),
          frontingSessionRepositoryProvider.overrideWithValue(trackingRepo),
          frontingMutationServiceProvider.overrideWithValue(mutSvc),
          frontingMigrationWritesBlockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      await svc.setToken('fake');

      // Set liveFrontsOnly mode + bidirectional direction.
      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.bidirectional);
      await container
          .read(pkSyncModeProvider.notifier)
          .setMode(PkSyncMode.liveFrontsOnly);

      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      // Act: apply() → NeedsFronterResolution; then applyFronterResolution().
      final outcome = await ctrl.apply();
      expect(outcome, isA<PkMappingApplyOutcomeNeedsFronterResolution>(),
          reason: 'Precondition: disagreement must produce NeedsFronterResolution');

      final res = outcome as PkMappingApplyOutcomeNeedsFronterResolution;
      await ctrl.applyFronterResolution(
        chosenLocalMemberIds: {'l1'}, // keep Alice
        direction: res.direction,
        mode: res.mode,
        pkCurrentSwitch: res.pkCurrentSwitch,
      );

      // Assert: the real PK client's getCurrentFronters was called exactly once
      // (by apply(); the cache must be passed through to syncLiveFrontersOnly).
      expect(
        client.getCurrentFrontersCallCount,
        equals(1),
        reason: 'getCurrentFronters must be called exactly once across apply + applyFronterResolution',
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Helper clients
// ---------------------------------------------------------------------------

class _ThrowingCreateClient extends _ConfigurableClient {
  _ThrowingCreateClient(super.members);

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    throw const PluralKitApiError(400, 'forced failure');
  }
}
