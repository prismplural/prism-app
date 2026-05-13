import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
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
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_one_shot_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// In-memory member repo — minimum surface the service touches.
// (Same shape as pk_mapping_applier_test.dart's FakeMemberRepo.)
// ---------------------------------------------------------------------------

class _FakeMemberRepo implements MemberRepository {
  final Map<String, domain.Member> _byId = {};

  _FakeMemberRepo(Iterable<domain.Member> seed) {
    for (final m in seed) {
      _byId[m.id] = m;
    }
  }

  // Test-only seam: replace the row in storage out of band, simulating a
  // concurrent UI write that lands between the service's initial check and
  // the post-POST re-read in `_linkBackLocally`.
  void replace(domain.Member member) => _byId[member.id] = member;

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      _byId.values.where((m) => !m.isDeleted).toList();

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      _byId.values.toList();

  @override
  Future<domain.Member?> getMemberById(String id) async => _byId[id];

  @override
  Future<void> createMember(domain.Member member) async =>
      _byId[member.id] = member;

  @override
  Future<void> updateMember(domain.Member member) async =>
      _byId[member.id] = member;

  @override
  Future<void> deleteMember(String id) async {
    final m = _byId[id];
    if (m == null) return;
    _byId[id] = m.copyWith(isDeleted: true);
  }

  @override
  Future<int> getCount() async => _byId.values.where((m) => !m.isDeleted).length;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      ids.map((id) => _byId[id]).whereType<domain.Member>().toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(
        ids.map((id) => _byId[id]).whereType<domain.Member>().toList(),
      );

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_byId.values.where((m) => m.isActive && !m.isDeleted).toList());

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(_byId.values.toList());

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
// Minimal stub for FrontingSessionRepository — never invoked in these tests,
// but the PluralKitSyncService constructor requires it. noSuchMethod fallback
// means any unexpected call surfaces a loud failure.
// ---------------------------------------------------------------------------

class _StubFrontingSessionRepo implements FrontingSessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fronting repo unused by one-shot push tests');
}

// ---------------------------------------------------------------------------
// Fake PluralKit client. Counts createMember calls (POST count) and lets each
// test stub getMember + createMember responses inline.
// ---------------------------------------------------------------------------

class _FakeClient extends PluralKitClient {
  int createCallCount = 0;
  int getCallCount = 0;
  bool disposed = false;

  PKMember Function(Map<String, dynamic>)? onCreate;
  PKMember Function(String ref)? onGet;

  _FakeClient() : super(token: 'fake-token', httpClient: http.Client());

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    final result = onCreate?.call(data) ??
        PKMember(
          id: 'abcde',
          uuid: 'uuid-$createCallCount',
          name: data['name'] as String,
        );
    return result;
  }

  @override
  Future<PKMember> getMember(String memberRef) async {
    getCallCount++;
    final cb = onGet;
    if (cb != null) return cb(memberRef);
    return PKMember(id: 'abcde', uuid: memberRef, name: 'Fetched');
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Fake sync service. Only `buildClientIfConnected` is exercised by the one-shot
// service; everything else stays as the real implementation (but is unused).
// ---------------------------------------------------------------------------

class _FakeSyncService extends PluralKitSyncService {
  _FakeClient client;
  bool returnNullClient = false;

  _FakeSyncService({
    required this.client,
    required super.memberRepository,
    required super.frontingSessionRepository,
    required super.syncDao,
    required super.bus,
  });

  @override
  Future<PluralKitClient?> buildClientIfConnected() async =>
      returnNullClient ? null : client;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

domain.Member _member({
  required String id,
  required String name,
  String? pluralkitUuid,
  String? pluralkitId,
  bool ignored = false,
  bool deleted = false,
}) {
  return domain.Member(
    id: id,
    name: name,
    createdAt: DateTime(2026),
    pluralkitUuid: pluralkitUuid,
    pluralkitId: pluralkitId,
    pluralkitSyncIgnored: ignored,
    isDeleted: deleted,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late PluralKitSyncDao syncDao;
  late _FakeMemberRepo memberRepo;
  late _FakeClient client;
  late _FakeSyncService syncSvc;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncDao = PluralKitSyncDao(db);
    memberRepo = _FakeMemberRepo([_member(id: 'm1', name: 'Alice')]);
    client = _FakeClient();
    syncSvc = _FakeSyncService(
      client: client,
      memberRepository: memberRepo,
      frontingSessionRepository: _StubFrontingSessionRepo(),
      syncDao: syncDao,
      bus: PkSyncEventBus(),
    );
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(memberRepo),
      pluralKitSyncServiceProvider.overrideWithValue(syncSvc),
      frontingMigrationWritesBlockedProvider.overrideWithValue(false),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('happy path: state row goes pending → applied, identifiers land on member, no PK sync state mutation', () async {
    final svc = container.read(pkOneShotPushServiceProvider);
    final dao = container.read(pkMappingStateDaoProvider);

    // Snapshot the pluralkit_sync_state row before pushing so we can prove
    // the one-shot path does not mutate it.
    final beforeSyncRow = await syncDao.getSyncState();

    client.onCreate = (data) => const PKMember(
          id: 'abcde',
          uuid: 'uuid-alice',
          name: 'Alice',
        );

    final result = await svc.pushSingleMember('m1');

    expect(result.id, 'abcde');
    expect(result.uuid, 'uuid-alice');
    expect(client.createCallCount, 1, reason: 'should have POSTed once');

    final stored = await memberRepo.getMemberById('m1');
    expect(stored!.pluralkitId, 'abcde');
    expect(stored.pluralkitUuid, 'uuid-alice');
    // pluralkitSyncIgnored must NOT be touched (was false before, still false).
    expect(stored.pluralkitSyncIgnored, isFalse);

    final stateRow = await dao.getById('one_shot_push:m1');
    expect(stateRow, isNotNull);
    expect(stateRow!.status, 'applied');
    expect(stateRow.pkMemberId, 'abcde');
    expect(stateRow.pkMemberUuid, 'uuid-alice');
    expect(stateRow.decisionType, 'push');
    expect(stateRow.localMemberId, 'm1');

    // No mutation of pluralkit_sync_state row.
    final afterSyncRow = await syncDao.getSyncState();
    expect(afterSyncRow.fieldSyncConfig, beforeSyncRow.fieldSyncConfig);
    expect(afterSyncRow.isConnected, beforeSyncRow.isConnected);
    expect(afterSyncRow.directionConfirmed, beforeSyncRow.directionConfirmed);
    expect(afterSyncRow.mappingAcknowledged, beforeSyncRow.mappingAcknowledged);

    expect(client.disposed, isTrue, reason: 'client must be disposed');
  });

  test('reuses prior pk_mapping_state row: no second POST, fetches existing PK member', () async {
    final svc = container.read(pkOneShotPushServiceProvider);
    final dao = container.read(pkMappingStateDaoProvider);

    // Seed a prior pending state row with the PK UUID already populated —
    // simulates a crash between the PK POST and the local writeback.
    await dao.upsert(_priorStateRow('one_shot_push:m1', 'm1', 'abcde', 'uuid-alice'));

    client.onGet = (ref) => PKMember(id: 'abcde', uuid: ref, name: 'Alice');

    final result = await svc.pushSingleMember('m1');

    expect(result.uuid, 'uuid-alice');
    expect(client.createCallCount, 0, reason: 'must NOT POST again');
    expect(client.getCallCount, 1, reason: 'must fetch existing PK member by uuid');

    final stored = await memberRepo.getMemberById('m1');
    expect(stored!.pluralkitId, 'abcde');
    expect(stored.pluralkitUuid, 'uuid-alice');

    final stateRow = await dao.getById('one_shot_push:m1');
    expect(stateRow!.status, 'applied');
  });

  test('member soft-deleted mid-push: aborts local write, marks failed with "deleted" message, PK row orphaned', () async {
    final dao = container.read(pkMappingStateDaoProvider);

    // Configure createMember to simulate a successful POST, then mutate the
    // local repo to mark the member as soft-deleted before _linkBackLocally
    // re-reads. This models the user tapping delete during the in-flight push.
    client.onCreate = (data) {
      memberRepo.replace(
        _member(id: 'm1', name: 'Alice', deleted: true),
      );
      return const PKMember(id: 'abcde', uuid: 'uuid-alice', name: 'Alice');
    };

    final svc = container.read(pkOneShotPushServiceProvider);
    final result = await svc.pushSingleMember('m1');

    // Service returns the PK member as created — POST succeeded; local
    // writeback was aborted.
    expect(result.uuid, 'uuid-alice');
    expect(client.createCallCount, 1);

    final stored = await memberRepo.getMemberById('m1');
    expect(stored!.isDeleted, isTrue);
    expect(stored.pluralkitId, isNull, reason: 'local write must be skipped');
    expect(stored.pluralkitUuid, isNull);

    final stateRow = await dao.getById('one_shot_push:m1');
    expect(stateRow!.status, 'failed');
    expect(stateRow.errorMessage, isNotNull);
    expect(
      stateRow.errorMessage!.toLowerCase(),
      contains('deleted'),
      reason: 'errorMessage should mention "deleted"',
    );
  });

  test('member marked pluralkitSyncIgnored mid-push: aborts local write, marks failed with "Keep local" message', () async {
    final dao = container.read(pkMappingStateDaoProvider);

    client.onCreate = (data) {
      memberRepo.replace(
        _member(id: 'm1', name: 'Alice', ignored: true),
      );
      return const PKMember(id: 'abcde', uuid: 'uuid-alice', name: 'Alice');
    };

    final svc = container.read(pkOneShotPushServiceProvider);
    final result = await svc.pushSingleMember('m1');

    expect(result.uuid, 'uuid-alice');

    final stored = await memberRepo.getMemberById('m1');
    expect(stored!.pluralkitSyncIgnored, isTrue);
    expect(stored.pluralkitId, isNull, reason: 'local write must be skipped');
    expect(stored.pluralkitUuid, isNull);

    final stateRow = await dao.getById('one_shot_push:m1');
    expect(stateRow!.status, 'failed');
    expect(stateRow.errorMessage, isNotNull);
    expect(
      stateRow.errorMessage!,
      contains('Keep local'),
      reason: 'errorMessage should mention "Keep local"',
    );
  });

  test('concurrent push attempt for same member throws PkOneShotPushBusyException', () async {
    final svc = container.read(pkOneShotPushServiceProvider);

    // Swap in a client whose createMember blocks until we signal the gate, so
    // the first push stays in-flight while the second concurrent call runs.
    final gate = Completer<PKMember>();
    final blockingClient = _BlockingClient(gate);
    syncSvc.client = blockingClient;

    final first = svc.pushSingleMember('m1');
    // Yield so the first call enters _inFlight before the second attempt.
    await Future<void>.delayed(Duration.zero);

    expect(
      () => svc.pushSingleMember('m1'),
      throwsA(isA<PkOneShotPushBusyException>()),
    );

    // Let the first push finish so the test tears down cleanly.
    gate.complete(const PKMember(
      id: 'abcde',
      uuid: 'uuid-alice',
      name: 'Alice',
    ));
    await first;
  });

  test('migration gate: throws PkSyncMigrationGatedException', () async {
    container.dispose();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(memberRepo),
      pluralKitSyncServiceProvider.overrideWithValue(syncSvc),
      frontingMigrationWritesBlockedProvider.overrideWithValue(true),
    ]);

    final svc = container.read(pkOneShotPushServiceProvider);

    expect(
      () => svc.pushSingleMember('m1'),
      throwsA(isA<PkSyncMigrationGatedException>()),
    );
    expect(client.createCallCount, 0, reason: 'must not POST when gated');
  });

  test('does NOT mutate pkSyncDirection or pkSyncMode providers', () async {
    final svc = container.read(pkOneShotPushServiceProvider);

    // Read the providers before and after the push and confirm no change.
    final beforeDirection = container.read(pkSyncDirectionProvider);
    final beforeMode = container.read(pkSyncModeProvider);

    client.onCreate = (_) => const PKMember(
          id: 'abcde',
          uuid: 'uuid-alice',
          name: 'Alice',
        );

    await svc.pushSingleMember('m1');

    final afterDirection = container.read(pkSyncDirectionProvider);
    final afterMode = container.read(pkSyncModeProvider);

    expect(afterDirection, beforeDirection,
        reason: 'one-shot push must not touch sync direction');
    expect(afterMode, beforeMode,
        reason: 'one-shot push must not touch sync mode');
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

PkMappingStateCompanion _priorStateRow(
  String id,
  String localMemberId,
  String pkMemberId,
  String pkMemberUuid,
) {
  final now = DateTime.utc(2026, 1, 1);
  return PkMappingStateCompanion(
    id: Value(id),
    decisionType: const Value('push'),
    pkMemberId: Value(pkMemberId),
    pkMemberUuid: Value(pkMemberUuid),
    localMemberId: Value(localMemberId),
    status: const Value('pending'),
    createdAt: Value(now),
    updatedAt: Value(now),
  );
}

/// Client whose createMember awaits an external completer — used to keep a
/// push in-flight while a second concurrent call is made.
class _BlockingClient extends _FakeClient {
  final Completer<PKMember> _gate;
  _BlockingClient(this._gate);

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    createCallCount++;
    return _gate.future;
  }
}
