import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

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
  Future<List<domain.Member>> getAllMembers() async => _byId.values.toList();
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
      Stream.value(_byId.values.toList());
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      Stream.value(_byId[id]);

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
      'Fronting repo not expected to be called: ${invocation.memberName}');
}

class _FakeClient extends PluralKitClient {
  final List<PKMember> members;
  int createCallCount = 0;
  _FakeClient(this.members)
      : super(token: 'fake', httpClient: http.Client());

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

domain.Member _local(String id, String name, {String? pkUuid}) => domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
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

  test('build: seeds link for exact-name matches and import for others',
      () async {
    final state =
        await container.read(pkMappingControllerProvider.future);

    expect(state.pkMembers, hasLength(2));
    expect(state.localMembers.map((m) => m.id),
        containsAll(['l1', 'l2', 'l3']));

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
  });

  test(
      'setPkDecision: flipping a link to import frees up the local for push',
      () async {
    await container.read(pkMappingControllerProvider.future);
    final ctrl = container.read(pkMappingControllerProvider.notifier);

    // Flip Alice link → import.
    ctrl.setPkDecision(
      'pk-alice',
      const PkImportDecision(
        pkMember:
            PKMember(id: 'aaaaa', uuid: 'pk-alice', name: 'Alice'),
      ),
    );

    final s = container.read(pkMappingControllerProvider).value!;
    expect(s.decisionsByPkUuid['pk-alice'], isA<PkImportDecision>());
    // l1 now appears in the push pool with a default push-new decision.
    expect(s.decisionsByLocalId['l1'], isA<PkPushNewDecision>());
  });

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
  });

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
    expect(failSyncService.state.needsMapping, isTrue,
        reason: 'Partial failure must leave needsMapping set');
  });

  test('dismiss: does NOT acknowledge mapping', () async {
    await container.read(pkMappingControllerProvider.future);
    final ctrl = container.read(pkMappingControllerProvider.notifier);

    // Precondition — setToken marked needsMapping = true.
    expect(syncService.state.needsMapping, isTrue);

    ctrl.dismiss();

    expect(syncService.state.needsMapping, isTrue,
        reason: 'Dismiss must not flip needsMapping');
  });

  test('build: empty PK system + no unlinked locals auto-acknowledges',
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

    final localContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(emptyRepo),
      pluralKitSyncServiceProvider.overrideWithValue(emptySync),
    ]);
    addTearDown(localContainer.dispose);

    final s = await localContainer.read(pkMappingControllerProvider.future);
    expect(s.decisionsByPkUuid, isEmpty);
    expect(s.decisionsByLocalId, isEmpty);
    expect(emptySync.state.needsMapping, isFalse,
        reason: 'Nothing to decide — must auto-acknowledge so user is not stranded');
  });

  test('setPkDecision: link conflict demotes the loser to Skip (not Import)',
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

    final localContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(conflictRepo),
      pluralKitSyncServiceProvider.overrideWithValue(conflictSync),
    ]);
    addTearDown(localContainer.dispose);

    await localContainer.read(pkMappingControllerProvider.future);
    final ctrl =
        localContainer.read(pkMappingControllerProvider.notifier);

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
    expect(loser, isA<PkSkipDecision>(),
        reason: 'Defensive path must Skip, never silently Import');
  });

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
    expect(repo.createCallCount, 0,
        reason: 'build() must not call createMember (B1)');
    expect(repo.updateCallCount, 0,
        reason: 'build() must not call updateMember (B1)');
  });

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

    final localContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(ignoredRepo),
      pluralKitSyncServiceProvider.overrideWithValue(syncSvc),
    ]);
    addTearDown(localContainer.dispose);

    final s = await localContainer.read(pkMappingControllerProvider.future);
    expect(s.localMembers.map((m) => m.id), ['l1'],
        reason: 'Ignored locals must not appear in the mapping pool');
    expect(s.decisionsByLocalId.containsKey('l-ignored'), isFalse);
  });
}
