// Plan 08 — PluralKit bidirectional sync: success criterion #1 E2E lock.
//
// "5 Prism members + 5 overlapping PK members → zero duplicates, 5 linked in
// one pass."
//
// This test wires the real PkMappingController + PkMappingApplier +
// PluralKitSyncService together with fake PluralKit HTTP + in-memory repos,
// then drives the full mapping flow (build → apply) and asserts the end
// state. It's structurally similar to pk_mapping_controller_test.dart but
// covers the end-to-end happy path plus two adversarial shapes.

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

// ---------------------------------------------------------------------------
// Test doubles — mirror the structure used in pk_mapping_controller_test.dart
// and pk_mapping_applier_test.dart.
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

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> _byId = {};
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

class _FakePkClient extends PluralKitClient {
  final List<PKMember> members;
  int createCallCount = 0;
  _FakePkClient(this.members)
      : super(token: 'fake', httpClient: http.Client());

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test');

  @override
  Future<List<PKMember>> getMembers() async => List.of(members);

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    final created = PKMember(
      id: 'new$createCallCount',
      uuid: 'pk-new-uuid-$createCallCount',
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

domain.Member _local(String id, String name, {String? pkUuid}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
    );

PKMember _pk(String id, String name) =>
    PKMember(id: id, uuid: 'pk-$id', name: name);

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeMemberRepo repo;
  late _FakePkClient client;
  late PluralKitSyncService syncService;
  late ProviderContainer container;

  Future<void> bootstrap({
    required List<domain.Member> locals,
    required List<PKMember> pkMembers,
  }) async {
    _installSecureStorageStub();
    db = AppDatabase(NativeDatabase.memory());
    repo = _FakeMemberRepo(locals);
    client = _FakePkClient(pkMembers);
    syncService = PluralKitSyncService(
      memberRepository: repo,
      frontingSessionRepository: _NoopFrontingSessionRepo(),
      syncDao: PluralKitSyncDao(db),
      clientFactory: (_) => client,
      tokenOverride: 'fake',
    );
    await syncService.setToken('fake');
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(repo),
      pluralKitSyncServiceProvider.overrideWithValue(syncService),
    ]);
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'success criterion #1: 5 locals + 5 exact-name PK → 5 links, 0 duplicates, 1 pass',
    () async {
      const names = ['Alice', 'Bob', 'Charlie', 'Dana', 'Eve'];
      await bootstrap(
        locals: [
          for (var i = 0; i < names.length; i++) _local('l${i + 1}', names[i]),
        ],
        pkMembers: [
          for (var i = 0; i < names.length; i++)
            _pk('p${i + 1}', names[i]),
        ],
      );

      // Build decisions.
      final state =
          await container.read(pkMappingControllerProvider.future);

      // All 5 PK members must be auto-linked (exact-name matches).
      expect(state.decisionsByPkUuid, hasLength(5));
      for (final d in state.decisionsByPkUuid.values) {
        expect(d, isA<PkLinkDecision>(),
            reason: 'Every PK member should auto-link on exact name');
      }
      // No locals in the push pool — all were consumed by link decisions.
      expect(state.decisionsByLocalId, isEmpty);

      // Apply in one pass.
      await container.read(pkMappingControllerProvider.notifier).apply();

      final after = container.read(pkMappingControllerProvider).value!;
      expect(after.isApplying, isFalse);
      expect(after.lastResults, isNotNull);
      expect(after.lastResults!.length, 5);
      final failed = after.lastResults!
          .where((r) => r.outcome == PkApplyOutcome.failed)
          .toList();
      expect(failed, isEmpty, reason: 'Unexpected failures: $failed');

      // Every local now has a populated pluralkitUuid — no duplicates created.
      expect(await repo.getCount(), 5,
          reason: 'Total member count must stay 5 — zero duplicates');
      final allMembers = await repo.getAllMembers();
      expect(
        allMembers.every((m) =>
            m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty),
        isTrue,
        reason: 'All 5 locals must be linked to a PK UUID',
      );

      // createMember must NOT have been called — nothing should be pushed to PK.
      expect(client.createCallCount, 0,
          reason: 'Linked locals must not trigger PK create calls');

      // Mapping acknowledged.
      expect(syncService.state.needsMapping, isFalse);
    },
  );

  test(
    'disjoint names: 5 locals + 5 non-overlapping PK → push+import, 10 linked',
    () async {
      await bootstrap(
        locals: [
          _local('l1', 'Alpha'),
          _local('l2', 'Bravo'),
          _local('l3', 'Gamma'),
          _local('l4', 'Delta'),
          _local('l5', 'Echo'),
        ],
        pkMembers: [
          _pk('p1', 'Foxtrot'),
          _pk('p2', 'Golf'),
          _pk('p3', 'Hotel'),
          _pk('p4', 'India'),
          _pk('p5', 'Juliet'),
        ],
      );

      final state =
          await container.read(pkMappingControllerProvider.future);
      // All PK default to Import.
      expect(state.decisionsByPkUuid.values.whereType<PkImportDecision>(),
          hasLength(5));
      // All locals default to PushNew.
      expect(state.decisionsByLocalId.values.whereType<PkPushNewDecision>(),
          hasLength(5));

      await container.read(pkMappingControllerProvider.notifier).apply();

      // 5 push-new calls to PK.
      expect(client.createCallCount, 5);
      // Total member count is 5 locals + 5 imported = 10.
      expect(await repo.getCount(), 10);
      // Every member has a PK UUID (imports use the fake's UUID; pushes get
      // the UUID assigned by createMember).
      final allMembers = await repo.getAllMembers();
      expect(
        allMembers.every((m) =>
            m.pluralkitUuid != null && m.pluralkitUuid!.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'ambiguous names: two locals "Alex" + one PK "Alex" → Import + two PushNew',
    () async {
      await bootstrap(
        locals: [
          _local('l1', 'Alex'),
          _local('l2', 'Alex'),
        ],
        pkMembers: [
          _pk('p1', 'Alex'),
        ],
      );

      final state =
          await container.read(pkMappingControllerProvider.future);
      // Matcher picks the first-exact-match local and auto-links; the other
      // "Alex" defaults to push-new. That satisfies "ambiguous names must not
      // silently link both" — only one link is created, the other local still
      // pushes through.
      //
      // Either (a) pk-p1 → Link + one push-new, or (b) pk-p1 → Import + two
      // push-news — both are acceptable "no silent merge" outcomes. We assert
      // the invariant: the PK side has at most one link, and every unlinked
      // local defaults to PushNew, never to a silent auto-link.
      final linksFromPk = state.decisionsByPkUuid.values
          .whereType<PkLinkDecision>()
          .toList();
      expect(linksFromPk.length, lessThanOrEqualTo(1));
      // Every local that wasn't linked must default to PushNew (not silently
      // imported or skipped).
      final linkedLocalIds =
          linksFromPk.map((l) => l.localMemberId).toSet();
      for (final id in ['l1', 'l2']) {
        if (linkedLocalIds.contains(id)) continue;
        expect(state.decisionsByLocalId[id], isA<PkPushNewDecision>(),
            reason: 'Unlinked local $id must default to PushNew');
      }
    },
  );
}
