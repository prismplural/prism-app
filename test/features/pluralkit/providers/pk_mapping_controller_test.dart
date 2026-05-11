import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as fronting;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unmapped_fronters_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Secure-storage stub (flutter_secure_storage uses a MethodChannel).
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

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> _byId = {};
  int createCallCount = 0;
  int updateCallCount = 0;

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
  Future<void> createMember(domain.Member m) async {
    createCallCount++;
    _byId[m.id] = m;
  }

  @override
  Future<void> updateMember(domain.Member m) async {
    updateCallCount++;
    _byId[m.id] = m;
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

class _NoopFrontingSessionRepo implements FrontingSessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Fronting repo not expected to be called: ${invocation.memberName}',
  );
}

/// Empty fronting repo used by the Phase 3 phase-transition tests, which
/// exercise `importSwitchesAfterLink` and `pushPendingSwitches` end-to-end
/// against an empty DB. Just returns empty lists for everything the
/// post-decision pipeline actually reads.
class _EmptyFrontingSessionRepo implements FrontingSessionRepository {
  @override
  Future<List<fronting.FrontingSession>> getAllSessions() async => const [];
  @override
  Future<List<fronting.FrontingSession>>
  getAllActiveSessionsUnfiltered() async => const [];
  @override
  Future<List<fronting.FrontingSession>> getDeletedLinkedSessions() async =>
      const [];
  @override
  Future<List<fronting.FrontingSession>> getFrontingSessions() async =>
      const [];
  @override
  Future<List<fronting.FrontingSession>> getActiveSessions() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Empty fronting repo: ${invocation.memberName} not stubbed',
  );
}

class _FakeClient extends PluralKitClient {
  final List<PKMember> members;
  int createCallCount = 0;
  int getSwitchesCallCount = 0;

  /// Probe fired whenever [getSwitches] is invoked. Tests use this to capture
  /// the controller state at the moment the post-apply switch import begins.
  void Function()? onGetSwitches;

  _FakeClient(this.members) : super(token: 'fake', httpClient: http.Client());

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test');
  @override
  Future<List<PKMember>> getMembers() async => members;
  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    final created = PKMember(
      id: 'id$createCallCount',
      uuid: 'uuid$createCallCount',
      name: data['name'] as String,
    );
    members.add(created);
    return created;
  }

  /// Returns an empty switch list so `importSwitchesAfterLink` completes
  /// cleanly without HTTP traffic, letting the apply pipeline reach the
  /// pushingSwitches phase.
  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    getSwitchesCallCount++;
    onGetSwitches?.call();
    return const [];
  }

  /// Returns `null` (PK uses 204 No Content when the system has no switches
  /// yet) so `pushPendingSwitches` can compute its diff without HTTP traffic.
  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  Future<List<int>> downloadBytes(String url) async => const [];
  @override
  void dispose() {}
}

class _FailingCreateClient extends _FakeClient {
  _FailingCreateClient(super.members);
  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    throw const PluralKitApiError(400, 'bad');
  }
}

domain.Member _local(String id, String name, {String? pkUuid, String? pkId}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
      pluralkitId: pkId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeMemberRepo repo;
  late _FakeClient client;
  late PluralKitSyncService syncService;
  late ProviderContainer container;

  setUp(() async {
    _installSecureStorageStub();
    db = AppDatabase(NativeDatabase.memory());
    repo = _FakeMemberRepo([
      _local('l1', 'Alice'),
      _local('l2', 'Bob'),
      _local('l3', 'Carol'),
    ]);
    client = _FakeClient([
      const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
      const PKMember(id: 'ddddd', uuid: 'pk-dana', name: 'Dana'),
    ]);
    // Mark as "connected" in the sync DAO so buildClientIgnoringMappingGate works.
    syncService = PluralKitSyncService(
      memberRepository: repo,
      frontingSessionRepository: _NoopFrontingSessionRepo(),
      syncDao: PluralKitSyncDao(db),
      clientFactory: (_) => client,
      tokenOverride: 'fake',
    );
    await syncService.setToken('fake');

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        memberRepositoryProvider.overrideWithValue(repo),
        pluralKitSyncServiceProvider.overrideWithValue(syncService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'build: seeds link for exact-name matches and import for others',
    () async {
      final state = await container.read(pkMappingControllerProvider.future);

      expect(state.pkMembers, hasLength(2));
      expect(
        state.localMembers.map((m) => m.id),
        containsAll(['l1', 'l2', 'l3']),
      );

      // Alice → exact link to l1.
      final alice = state.decisionsByPkUuid['pk-alice'];
      expect(alice, isA<PkLinkDecision>());
      expect((alice as PkLinkDecision).localMemberId, 'l1');

      // Dana → no match → import.
      expect(state.decisionsByPkUuid['pk-dana'], isA<PkImportDecision>());

      // l2 and l3 default to push-new (not consumed by a link).
      expect(state.decisionsByLocalId['l2'], isA<PkPushNewDecision>());
      expect(state.decisionsByLocalId['l3'], isA<PkPushNewDecision>());
      // l1 is consumed by the link — not in the push pool.
      expect(state.decisionsByLocalId.containsKey('l1'), isFalse);
    },
  );

  test(
    'build: excludes PK members whose identity is held by a deleted local row',
    () async {
      repo = _FakeMemberRepo([
        _local('l1', 'Alice'),
        _local('l2', 'Bob'),
        _local(
          'gone',
          'Deleted Alice',
          pkId: 'aaaaa',
        ).copyWith(isDeleted: true),
      ]);
      syncService = PluralKitSyncService(
        memberRepository: repo,
        frontingSessionRepository: _NoopFrontingSessionRepo(),
        syncDao: PluralKitSyncDao(db),
        clientFactory: (_) => client,
        tokenOverride: 'fake',
      );
      await syncService.setToken('fake');
      container.dispose();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(repo),
          pluralKitSyncServiceProvider.overrideWithValue(syncService),
        ],
      );

      final state = await container.read(pkMappingControllerProvider.future);

      expect(state.pkMembers.map((m) => m.uuid), isNot(contains('pk-alice')));
      expect(state.decisionsByPkUuid.containsKey('pk-alice'), isFalse);
      expect(state.decisionsByPkUuid['pk-dana'], isA<PkImportDecision>());
    },
  );

  test(
    'setPkDecision: flipping a link to import frees up the local for push',
    () async {
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      // Flip Alice link → import.
      ctrl.setPkDecision(
        'pk-alice',
        const PkImportDecision(
          pkMember: PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
        ),
      );

      final s = container.read(pkMappingControllerProvider).value!;
      expect(s.decisionsByPkUuid['pk-alice'], isA<PkImportDecision>());
      // l1 now appears in the push pool with a default push-new decision.
      expect(s.decisionsByLocalId['l1'], isA<PkPushNewDecision>());
    },
  );

  test(
    'apply: runs applier, populates lastResults, and acknowledges mapping',
    () async {
      await container.read(pkMappingControllerProvider.future);
      final ctrl = container.read(pkMappingControllerProvider.notifier);

      await ctrl.apply();

      final s = container.read(pkMappingControllerProvider).value!;
      expect(s.lastResults, isNotNull);
      expect(s.isApplying, isFalse);
      // Decisions: Alice link + Dana import + push l2 + push l3 = 4
      expect(s.lastResults!.length, 4);
      final failed = s.lastResults!
          .where((r) => r.outcome == PkApplyOutcome.failed)
          .toList();
      expect(failed, isEmpty, reason: 'Unexpected failures: $failed');

      // Alice should now have pluralkit fields.
      final alice = await repo.getMemberById('l1');
      expect(alice!.pluralkitUuid, 'pk-alice');

      // l2 & l3 should have been pushed (createMember called twice).
      expect(client.createCallCount, 2);

      // Mapping acknowledged → service state flips to canAutoSync.
      expect(syncService.state.needsMapping, isFalse);
    },
  );

  test('apply: partial failure does NOT acknowledge mapping', () async {
    // Make createMember throw so push decisions fail.
    final failingClient = _FailingCreateClient([
      const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
      const PKMember(id: 'ddddd', uuid: 'pk-dana', name: 'Dana'),
    ]);
    final failSyncService = PluralKitSyncService(
      memberRepository: repo,
      frontingSessionRepository: _NoopFrontingSessionRepo(),
      syncDao: PluralKitSyncDao(db),
      clientFactory: (_) => failingClient,
      tokenOverride: 'fake',
    );
    await failSyncService.setToken('fake');

    final localContainer = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        memberRepositoryProvider.overrideWithValue(repo),
        pluralKitSyncServiceProvider.overrideWithValue(failSyncService),
      ],
    );
    addTearDown(localContainer.dispose);

    await localContainer.read(pkMappingControllerProvider.future);
    await localContainer.read(pkMappingControllerProvider.notifier).apply();

    final s = localContainer.read(pkMappingControllerProvider).value!;
    final failed = s.lastResults!
        .where((r) => r.outcome == PkApplyOutcome.failed)
        .toList();
    expect(failed, isNotEmpty);
    expect(
      failSyncService.state.needsMapping,
      isTrue,
      reason: 'Partial failure must leave needsMapping set',
    );
  });

  test('dismiss: does NOT acknowledge mapping', () async {
    await container.read(pkMappingControllerProvider.future);
    final ctrl = container.read(pkMappingControllerProvider.notifier);

    // Precondition — setToken marked needsMapping = true.
    expect(syncService.state.needsMapping, isTrue);

    ctrl.dismiss();

    expect(
      syncService.state.needsMapping,
      isTrue,
      reason: 'Dismiss must not flip needsMapping',
    );
  });

  test(
    'build: empty PK system + no unlinked locals auto-acknowledges',
    () async {
      // PK has no members; every local is already linked.
      final emptyRepo = _FakeMemberRepo([
        domain.Member(
          id: 'l1',
          name: 'Alice',
          createdAt: DateTime(2026),
          pluralkitUuid: 'pk-alice',
        ),
      ]);
      final emptyClient = _FakeClient([]);
      final emptySync = PluralKitSyncService(
        memberRepository: emptyRepo,
        frontingSessionRepository: _NoopFrontingSessionRepo(),
        syncDao: PluralKitSyncDao(db),
        clientFactory: (_) => emptyClient,
        tokenOverride: 'fake',
      );
      await emptySync.setToken('fake');
      expect(emptySync.state.needsMapping, isTrue);

      final localContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(emptyRepo),
          pluralKitSyncServiceProvider.overrideWithValue(emptySync),
        ],
      );
      addTearDown(localContainer.dispose);

      final s = await localContainer.read(pkMappingControllerProvider.future);
      expect(s.decisionsByPkUuid, isEmpty);
      expect(s.decisionsByLocalId, isEmpty);
      expect(
        emptySync.state.needsMapping,
        isFalse,
        reason:
            'Nothing to decide — must auto-acknowledge so user is not stranded',
      );
    },
  );

  test(
    'setPkDecision: link conflict demotes the loser to Skip (not Import)',
    () async {
      // Two PK members both matching local "Alice" (l1).
      final conflictRepo = _FakeMemberRepo([_local('l1', 'Alice')]);
      final conflictClient = _FakeClient([
        const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
        const PKMember(id: 'bbbbb', uuid: 'pk-alicia', name: 'Alice'),
      ]);
      final conflictSync = PluralKitSyncService(
        memberRepository: conflictRepo,
        frontingSessionRepository: _NoopFrontingSessionRepo(),
        syncDao: PluralKitSyncDao(db),
        clientFactory: (_) => conflictClient,
        tokenOverride: 'fake',
      );
      await conflictSync.setToken('fake');

      final localContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(conflictRepo),
          pluralKitSyncServiceProvider.overrideWithValue(conflictSync),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(pkMappingControllerProvider.future);
      final ctrl = localContainer.read(pkMappingControllerProvider.notifier);

      // Force both PK members to link to l1 sequentially. The matcher leaves
      // both as Import (PK-side ambiguity), so we promote pk-alice first.
      ctrl.setPkDecision(
        'pk-alice',
        const PkLinkDecision(
          localMemberId: 'l1',
          pkMember: PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
        ),
      );
      // Now promote pk-alicia to the same local — must demote pk-alice.
      ctrl.setPkDecision(
        'pk-alicia',
        const PkLinkDecision(
          localMemberId: 'l1',
          pkMember: PKMember(id: 'bbbbb', uuid: 'pk-alicia', name: 'Alice'),
        ),
      );

      final s = localContainer.read(pkMappingControllerProvider).value!;
      expect(s.decisionsByPkUuid['pk-alicia'], isA<PkLinkDecision>());
      final loser = s.decisionsByPkUuid['pk-alice'];
      expect(
        loser,
        isA<PkSkipDecision>(),
        reason: 'Defensive path must Skip, never silently Import',
      );
    },
  );

  test(
    'build: does NOT write to the member repository (regression B1)',
    () async {
      // Precondition — setToken already wrote the fake PK system name, but
      // that path targets pluralkit_sync_state, not members. Capture the
      // member-write counts right before reading the controller so we can
      // assert no new writes during build().
      repo.createCallCount = 0;
      repo.updateCallCount = 0;

      final state = await container.read(pkMappingControllerProvider.future);

      // Sanity: PK members were fetched read-only.
      expect(state.pkMembers, hasLength(2));

      // The mapping controller must not auto-create or update members during
      // build(); writes happen later, per-decision, via the applier on Apply.
      expect(
        repo.createCallCount,
        0,
        reason: 'build() must not call createMember (B1)',
      );
      expect(
        repo.updateCallCount,
        0,
        reason: 'build() must not call updateMember (B1)',
      );
    },
  );

  test('build: excludes pluralkitSyncIgnored locals from decisions', () async {
    final ignoredRepo = _FakeMemberRepo([
      _local('l1', 'Alice'),
      domain.Member(
        id: 'l-ignored',
        name: 'Shadow',
        createdAt: DateTime(2026),
        pluralkitSyncIgnored: true,
      ),
    ]);
    final syncSvc = PluralKitSyncService(
      memberRepository: ignoredRepo,
      frontingSessionRepository: _NoopFrontingSessionRepo(),
      syncDao: PluralKitSyncDao(db),
      clientFactory: (_) => _FakeClient([]),
      tokenOverride: 'fake',
    );
    await syncSvc.setToken('fake');

    final localContainer = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        memberRepositoryProvider.overrideWithValue(ignoredRepo),
        pluralKitSyncServiceProvider.overrideWithValue(syncSvc),
      ],
    );
    addTearDown(localContainer.dispose);

    final s = await localContainer.read(pkMappingControllerProvider.future);
    expect(
      s.localMembers.map((m) => m.id),
      ['l1'],
      reason: 'Ignored locals must not appear in the mapping pool',
    );
    expect(s.decisionsByLocalId.containsKey('l-ignored'), isFalse);
  });

  test(
    'build: treats short-id-only PluralKit links as already mapped',
    () async {
      final halfLinkedRepo = _FakeMemberRepo([
        _local('l1', 'Alice', pkId: 'aaaaa'),
        _local('l2', 'Bob'),
      ]);
      final syncSvc = PluralKitSyncService(
        memberRepository: halfLinkedRepo,
        frontingSessionRepository: _NoopFrontingSessionRepo(),
        syncDao: PluralKitSyncDao(db),
        clientFactory: (_) => _FakeClient([
          const PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
          const PKMember(id: 'bbbbb', uuid: 'pk-dana', name: 'Dana'),
        ]),
        tokenOverride: 'fake',
      );
      await syncSvc.setToken('fake');

      final localContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(halfLinkedRepo),
          pluralKitSyncServiceProvider.overrideWithValue(syncSvc),
        ],
      );
      addTearDown(localContainer.dispose);

      final s = await localContainer.read(pkMappingControllerProvider.future);

      expect(s.pkMembers.map((m) => m.id), ['bbbbb']);
      expect(s.decisionsByPkUuid.containsKey('pk-alice'), isFalse);
      expect(s.decisionsByLocalId.containsKey('l1'), isFalse);
      expect(s.decisionsByLocalId['l2'], isA<PkPushNewDecision>());
    },
  );

  // -- Phase 3 (per docs/plans/pk-megasystem-import.md): phase transitions ---

  group('apply: phase transitions', () {
    test(
      'initial state defaults to applyingDecisions with no statusText',
      () async {
        final s = await container.read(pkMappingControllerProvider.future);
        expect(s.phase, PkMappingPhase.applyingDecisions);
        expect(s.statusText, isNull);
        expect(s.isApplying, isFalse);
        expect(s.applyProgress, 0.0);
      },
    );

    test(
      'apply progresses through three phases and ends idle without statusText',
      () async {
        // Build a probe sync service tied to the test DB / repo / client.
        // The probe captures controller state at the entry point of the
        // post-decision phase methods so the test can assert the
        // controller had already advanced phase + reset progress before
        // each call.
        late ProviderContainer probedContainer;
        final probe = _PhaseProbeSyncService(
          memberRepository: repo,
          frontingSessionRepository: _EmptyFrontingSessionRepo(),
          syncDao: PluralKitSyncDao(db),
          clientFactory: (_) => client,
          tokenOverride: 'fake',
          readState: () =>
              probedContainer.read(pkMappingControllerProvider).value,
        );
        await probe.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(repo),
            pluralKitSyncServiceProvider.overrideWithValue(probe),
            frontingMigrationWritesBlockedProvider.overrideWithValue(false),
          ],
        );
        addTearDown(probedContainer.dispose);

        await probedContainer
            .read(pkSyncDirectionProvider.notifier)
            .setDirection(PkSyncDirection.bidirectional);
        await probedContainer.read(pkMappingControllerProvider.future);
        final ctrl = probedContainer.read(pkMappingControllerProvider.notifier);

        // Hook the fake client so we can sample state in mid-import-phase too.
        PkMappingState? duringImport;
        client.onGetSwitches = () {
          duringImport = probedContainer
              .read(pkMappingControllerProvider)
              .value;
        };

        await ctrl.apply(
          importingHistoryStatus: 'Importing switch history…',
          pushingHistoryStatus: 'Pushing switch updates to PluralKit…',
        );

        // Phase 2 entry: `importSwitchesAfterLink` was awaited with phase
        // already set to importingSwitches and applyProgress reset to 0.
        expect(probe.importSwitchesCallCount, 1);
        final atImport = probe.stateAtImportEntry;
        expect(
          atImport,
          isNotNull,
          reason: 'importSwitchesAfterLink should have been awaited',
        );
        expect(atImport!.phase, PkMappingPhase.importingSwitches);
        expect(atImport.applyProgress, 0.0);
        expect(atImport.statusText, 'Importing switch history…');
        expect(atImport.isApplying, isTrue);

        // Mid-import sample (during _fetchAllSwitches → client.getSwitches):
        // still in importingSwitches phase.
        expect(duringImport, isNotNull);
        expect(duringImport!.phase, PkMappingPhase.importingSwitches);
        expect(duringImport!.isApplying, isTrue);

        // Phase 3 entry: `pushPendingSwitches` saw phase=pushingSwitches with
        // applyProgress reset and the pushing-history label.
        expect(probe.pushSwitchesCallCount, 1);
        final atPush = probe.stateAtPushEntry;
        expect(
          atPush,
          isNotNull,
          reason: 'pushPendingSwitches should have been awaited',
        );
        expect(atPush!.phase, PkMappingPhase.pushingSwitches);
        expect(atPush.applyProgress, 0.0);
        expect(atPush.statusText, 'Pushing switch updates to PluralKit…');
        expect(atPush.isApplying, isTrue);

        // Final state: apply finished; status text cleared; progress at 1.0.
        final after = probedContainer.read(pkMappingControllerProvider).value!;
        expect(after.isApplying, isFalse);
        expect(after.applyProgress, 1.0);
        expect(after.statusText, isNull);
        expect(after.lastResults, isNotNull);
        // We applied 4 decisions (alice link + dana import + push l2 + push l3).
        expect(after.lastResults!.length, 4);
      },
    );

    test(
      'apply in full-sync push-only skips history import and only runs push phase',
      () async {
        late ProviderContainer probedContainer;
        final probe = _PhaseProbeSyncService(
          memberRepository: repo,
          frontingSessionRepository: _EmptyFrontingSessionRepo(),
          syncDao: PluralKitSyncDao(db),
          clientFactory: (_) => client,
          tokenOverride: 'fake',
          readState: () =>
              probedContainer.read(pkMappingControllerProvider).value,
        );
        await probe.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(repo),
            pluralKitSyncServiceProvider.overrideWithValue(probe),
            frontingMigrationWritesBlockedProvider.overrideWithValue(false),
          ],
        );
        addTearDown(probedContainer.dispose);

        await probedContainer
            .read(pkSyncDirectionProvider.notifier)
            .setDirection(PkSyncDirection.pushOnly);
        await probedContainer.read(pkMappingControllerProvider.future);

        await probedContainer
            .read(pkMappingControllerProvider.notifier)
            .apply(
              pushingHistoryStatus: 'Pushing switch updates to PluralKit...',
            );

        expect(probe.importSwitchesCallCount, 0);
        expect(probe.liveFrontsOnlyCallCount, 0);
        expect(probe.pushSwitchesCallCount, 1);
        expect(probe.stateAtPushEntry?.phase, PkMappingPhase.pushingSwitches);
      },
    );

    test(
      'apply in live-fronts-only uses live sync and skips full history',
      () async {
        SharedPreferences.setMockInitialValues({});
        late ProviderContainer probedContainer;
        final probe = _PhaseProbeSyncService(
          memberRepository: repo,
          frontingSessionRepository: _EmptyFrontingSessionRepo(),
          syncDao: PluralKitSyncDao(db),
          clientFactory: (_) => client,
          tokenOverride: 'fake',
          readState: () =>
              probedContainer.read(pkMappingControllerProvider).value,
        );
        await probe.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(repo),
            pluralKitSyncServiceProvider.overrideWithValue(probe),
            frontingMigrationWritesBlockedProvider.overrideWithValue(false),
          ],
        );
        addTearDown(probedContainer.dispose);

        await probedContainer
            .read(pkSyncModeProvider.notifier)
            .setMode(PkSyncMode.liveFrontsOnly);
        await probedContainer
            .read(pkSyncDirectionProvider.notifier)
            .setDirection(PkSyncDirection.pullOnly);
        await probedContainer.read(pkMappingControllerProvider.future);

        await probedContainer
            .read(pkMappingControllerProvider.notifier)
            .apply();

        expect(probe.importSwitchesCallCount, 0);
        expect(probe.pushSwitchesCallCount, 0);
        expect(probe.liveFrontsOnlyCallCount, 1);
        expect(probe.liveFrontsOnlyDirection, PkSyncDirection.pullOnly);
      },
    );

    test(
      'apply in live-fronts-only publishes unmapped notice via sync notifier',
      () async {
        SharedPreferences.setMockInitialValues({});
        final notice = PkUnmappedFrontersNotice(
          systemId: 'sys-1',
          switchId: 'switch-current',
          switchTimestamp: DateTime.utc(2026, 5, 11, 12),
          sortedPkIds: const ['aaaaa'],
          refs: const [PkUnmappedFronterRef(pkId: 'aaaaa')],
        );

        late ProviderContainer probedContainer;
        final probe =
            _PhaseProbeSyncService(
                memberRepository: repo,
                frontingSessionRepository: _EmptyFrontingSessionRepo(),
                syncDao: PluralKitSyncDao(db),
                clientFactory: (_) => client,
                tokenOverride: 'fake',
                readState: () =>
                    probedContainer.read(pkMappingControllerProvider).value,
              )
              ..liveFrontsOnlySummary = PkSyncSummary(
                liveUnmappedFronters: notice,
                observedLiveFronters: true,
                observedLiveFrontersDismissalKey: notice.dismissalKey,
              );
        await probe.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(repo),
            pluralKitSyncServiceProvider.overrideWithValue(probe),
            frontingMigrationWritesBlockedProvider.overrideWithValue(false),
          ],
        );
        addTearDown(probedContainer.dispose);

        await probedContainer
            .read(pkSyncModeProvider.notifier)
            .setMode(PkSyncMode.liveFrontsOnly);
        await probedContainer
            .read(pkSyncDirectionProvider.notifier)
            .setDirection(PkSyncDirection.pullOnly);
        await probedContainer.read(pkMappingControllerProvider.future);

        await probedContainer
            .read(pkMappingControllerProvider.notifier)
            .apply();

        final noticeState = await probedContainer.read(
          pkUnmappedFrontersNoticeProvider.future,
        );
        expect(noticeState.currentNotice?.dismissalKey, notice.dismissalKey);
      },
    );

    test(
      'apply in live-fronts-only respects migration gate before live sync',
      () async {
        late ProviderContainer probedContainer;
        final probe = _PhaseProbeSyncService(
          memberRepository: repo,
          frontingSessionRepository: _EmptyFrontingSessionRepo(),
          syncDao: PluralKitSyncDao(db),
          clientFactory: (_) => client,
          tokenOverride: 'fake',
          readState: () =>
              probedContainer.read(pkMappingControllerProvider).value,
        );
        await probe.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(repo),
            pluralKitSyncServiceProvider.overrideWithValue(probe),
            frontingMigrationWritesBlockedProvider.overrideWithValue(true),
          ],
        );
        addTearDown(probedContainer.dispose);

        await probedContainer
            .read(pkSyncModeProvider.notifier)
            .setMode(PkSyncMode.liveFrontsOnly);
        await probedContainer
            .read(pkSyncDirectionProvider.notifier)
            .setDirection(PkSyncDirection.pullOnly);
        await probedContainer.read(pkMappingControllerProvider.future);

        await probedContainer
            .read(pkMappingControllerProvider.notifier)
            .apply();

        expect(probe.liveFrontsOnlyCallCount, 0);
      },
    );

    test(
      'per-decision loop advances applyProgress while phase stays applyingDecisions',
      () async {
        // Capture state snapshots inside the per-decision loop. We tap the
        // member repo: every applier write (link update / import create /
        // push create) fires a probe that snapshots the controller's
        // (phase, applyProgress) tuple at that point. All such writes must
        // happen during phase 1 (applyingDecisions).
        final phaseDuringApplier = <PkMappingPhase>[];
        final progressDuringApplier = <double>[];

        late ProviderContainer probedContainer;
        final wrappedRepo = _RecordingMemberRepo(
          repo,
          onWrite: () {
            final s = probedContainer.read(pkMappingControllerProvider).value;
            if (s != null && s.isApplying) {
              phaseDuringApplier.add(s.phase);
              progressDuringApplier.add(s.applyProgress);
            }
          },
        );

        final svc = PluralKitSyncService(
          memberRepository: wrappedRepo,
          frontingSessionRepository: _EmptyFrontingSessionRepo(),
          syncDao: PluralKitSyncDao(db),
          clientFactory: (_) => client,
          tokenOverride: 'fake',
        );
        await svc.setToken('fake');

        probedContainer = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(wrappedRepo),
            pluralKitSyncServiceProvider.overrideWithValue(svc),
          ],
        );
        addTearDown(probedContainer.dispose);

        client.onGetSwitches = () {
          // Sanity check: by the time getSwitches fires, phase must have
          // advanced past applyingDecisions.
          final s = probedContainer.read(pkMappingControllerProvider).value!;
          expect(s.phase, isNot(PkMappingPhase.applyingDecisions));
        };

        await probedContainer.read(pkMappingControllerProvider.future);
        await probedContainer
            .read(pkMappingControllerProvider.notifier)
            .apply(
              importingHistoryStatus: 'Importing switch history…',
              pushingHistoryStatus: 'Pushing switch updates to PluralKit…',
            );

        // We captured at least the writes performed by the per-decision loop
        // (Alice's link, Dana's import, and two pushed locals).
        expect(
          phaseDuringApplier,
          isNotEmpty,
          reason: 'expected applier writes during phase 1',
        );
        // Every captured phase during the writes the applier performs is
        // applyingDecisions (the per-decision loop is the only writer in
        // phase 1).
        expect(
          phaseDuringApplier.every(
            (p) => p == PkMappingPhase.applyingDecisions,
          ),
          isTrue,
          reason:
              'applier writes must happen with phase=applyingDecisions; '
              'got $phaseDuringApplier',
        );
        // Progress was monotonically non-decreasing across the per-decision
        // writes.
        for (var i = 1; i < progressDuringApplier.length; i++) {
          expect(
            progressDuringApplier[i],
            greaterThanOrEqualTo(progressDuringApplier[i - 1]),
            reason:
                'applyProgress should be monotonically non-decreasing in '
                'phase 1; saw $progressDuringApplier',
          );
        }
      },
    );
  });
}

/// Records mapping state at each member-repo write — used to observe what the
/// controller's phase / applyProgress look like during the per-decision loop.
class _RecordingMemberRepo implements MemberRepository {
  _RecordingMemberRepo(this._inner, {required this.onWrite});

  final MemberRepository _inner;
  final void Function() onWrite;

  @override
  Future<void> createMember(domain.Member m) async {
    onWrite();
    return _inner.createMember(m);
  }

  @override
  Future<void> updateMember(domain.Member m) async {
    onWrite();
    return _inner.updateMember(m);
  }

  @override
  Future<List<domain.Member>> getAllMembers() => _inner.getAllMembers();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() =>
      _inner.getAllMembersIncludingDeleted();

  @override
  Future<domain.Member?> getMemberById(String id) => _inner.getMemberById(id);

  @override
  Future<void> deleteMember(String id) => _inner.deleteMember(id);

  @override
  Future<int> getCount() => _inner.getCount();

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) =>
      _inner.getMembersByIds(ids);

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      _inner.watchMembersByIds(ids);

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      _inner.watchActiveMembers();

  @override
  Stream<List<domain.Member>> watchAllMembers() => _inner.watchAllMembers();

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      _inner.watchMemberById(id);

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() =>
      _inner.getDeletedLinkedMembers();

  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);

  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => _inner.ensureUnknownSentinelMember();
}

/// A [PluralKitSyncService] that, before delegating to the inherited
/// implementation of `importSwitchesAfterLink` and `pushPendingSwitches`,
/// captures the mapping controller's state via a caller-supplied closure.
/// The closure reads the controller off a [ProviderContainer] late-bound by
/// the test, since the controller (and therefore its container) can't exist
/// before this service is constructed.
class _PhaseProbeSyncService extends PluralKitSyncService {
  _PhaseProbeSyncService({
    required super.memberRepository,
    required super.frontingSessionRepository,
    required super.syncDao,
    required super.clientFactory,
    required super.tokenOverride,
    required this.readState,
  });

  /// Returns the controller's current state snapshot. Test wires this to a
  /// `container.read(pkMappingControllerProvider).value` lookup.
  final PkMappingState? Function() readState;

  int importSwitchesCallCount = 0;
  int pushSwitchesCallCount = 0;
  int liveFrontsOnlyCallCount = 0;
  PkMappingState? stateAtImportEntry;
  PkMappingState? stateAtPushEntry;
  PkSyncDirection? liveFrontsOnlyDirection;
  PkSyncSummary? liveFrontsOnlySummary;

  @override
  Future<void> importSwitchesAfterLink({
    void Function(double fraction, String status)? onProgress,
  }) async {
    importSwitchesCallCount++;
    stateAtImportEntry = readState();
    return super.importSwitchesAfterLink(onProgress: onProgress);
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
    stateAtPushEntry = readState();
    return super.pushPendingSwitches(
      pushService: pushService,
      onStaleLink: onStaleLink,
      allowDuringSync: allowDuringSync,
      knownCurrentFronters: knownCurrentFronters,
      refreshMembersOnStaleLink: refreshMembersOnStaleLink,
    );
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    required PkSyncDirection direction,
    bool isManual = false,
  }) {
    liveFrontsOnlyCallCount++;
    liveFrontsOnlyDirection = direction;
    final summary = liveFrontsOnlySummary;
    if (summary != null) return Future.value(summary);
    return super.syncLiveFrontersOnly(direction: direction, isManual: isManual);
  }
}
