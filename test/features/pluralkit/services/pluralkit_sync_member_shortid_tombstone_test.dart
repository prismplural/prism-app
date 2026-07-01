/// Regression: a soft-deleted member retaining a RECYCLED PluralKit short id
/// must not block importing a DIFFERENT live PK member that now owns that short
/// id. Before the v40 active-only `idx_members_pluralkit_id`, the fresh insert
/// in `_importMembers` failed with SQLITE_CONSTRAINT_UNIQUE against the
/// tombstone's stale short id, and the member was silently dropped.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

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

class _FakePluralKitClient implements PluralKitClient {
  _FakePluralKitClient({required this.membersToReturn});

  final List<PKMember> membersToReturn;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => membersToReturn;

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async =>
      const [];

  @override
  Future<PKSwitch> getSwitch(String switchRef) => throw UnimplementedError();

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<void> addMembersToGroup(String groupRef, List<String> memberRefs) async =>
      throw UnimplementedError();

  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(List<String> memberIds, {DateTime? timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(String switchId, {required DateTime timestamp}) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  test(
      'a deleted member holding a recycled short id does not block importing a '
      'different live PK member that now owns it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Soft-deleted member retaining the recycled short id "abcde" under its own
    // (now-stale) uuid.
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'deleted-holder',
            name: 'Old Holder',
            emoji: const Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            pluralkitUuid: const Value('pk-uuid-old'),
            pluralkitId: const Value('abcde'),
            isDeleted: const Value(true),
          ),
        );

    final memberRepo = DriftMemberRepository(db.membersDao, null);
    final sessionRepo =
        DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    final fakeClient = _FakePluralKitClient(
      membersToReturn: const [
        PKMember(id: 'abcde', uuid: 'pk-uuid-new', name: 'New Holder'),
      ],
    );
    final service = PluralKitSyncService(
      memberRepository: memberRepo,
      frontingSessionRepository: sessionRepo,
      syncDao: db.pluralKitSyncDao,
      bus: PkSyncEventBus(),
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    await service.performOneTimeFullImport(token: 'test-token');

    // The new live member was created and owns the recycled short id.
    final live = await (db.select(db.members)
          ..where((m) =>
              m.pluralkitUuid.equals('pk-uuid-new') &
              m.isDeleted.equals(false)))
        .getSingleOrNull();
    expect(live, isNotNull,
        reason: 'the new PK member must import despite the deleted tombstone '
            'holding the recycled short id');
    expect(live!.pluralkitId, 'abcde');

    // The deleted tombstone keeps its real uuid (uuid index still covers it).
    final deleted = await (db.select(db.members)
          ..where((m) => m.id.equals('deleted-holder')))
        .getSingle();
    expect(deleted.isDeleted, isTrue);
    expect(deleted.pluralkitUuid, 'pk-uuid-old');
  });

  test(
      'a soft-deleted member with the SAME uuid is not resurrected by import '
      '(delete intent is preserved)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'deleted-same-uuid',
            name: 'Gone',
            emoji: const Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            pluralkitUuid: const Value('pk-uuid-same'),
            pluralkitId: const Value('ghijk'),
            isDeleted: const Value(true),
          ),
        );

    // A fresh second member rides along so the import does not hit the
    // "no members resolved" guard — it proves the deleted same-uuid one is
    // skipped while a real member still imports.
    final fakeClient = _FakePluralKitClient(
      membersToReturn: const [
        PKMember(id: 'ghijk', uuid: 'pk-uuid-same', name: 'Gone'),
        PKMember(id: 'fresh', uuid: 'pk-uuid-fresh', name: 'Fresh'),
      ],
    );
    final service = PluralKitSyncService(
      memberRepository: DriftMemberRepository(db.membersDao, null),
      frontingSessionRepository:
          DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      syncDao: db.pluralKitSyncDao,
      bus: PkSyncEventBus(),
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    await service.performOneTimeFullImport(token: 'test-token');

    final rows = await db.select(db.members).get();
    // The same-uuid tombstone was NOT resurrected; only the fresh member is live.
    final live = rows.where((m) => !m.isDeleted).toList();
    expect(live.map((m) => m.pluralkitUuid), {'pk-uuid-fresh'},
        reason: 'a same-uuid PK member must not resurrect a deleted local '
            'member nor create a duplicate live row');
    final tombstone = rows.singleWhere((m) => m.id == 'deleted-same-uuid');
    expect(tombstone.isDeleted, isTrue);
    expect(tombstone.pluralkitUuid, 'pk-uuid-same');
  });

  test(
      'F5: full import adopts an orphaned PK member onto a lease-holding local '
      'member instead of creating a duplicate', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // A local member this fleet tried to create (stale create lease), still
    // unlinked because the prior POST's link-back never completed.
    final staleLease = DateTime.now()
        .subtract(const Duration(minutes: 20))
        .millisecondsSinceEpoch;
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'local-attempted',
            name: 'Nova',
            emoji: const Value('🟣'),
            createdAt: DateTime(2026, 1, 1),
            createPushStartedAt: Value(staleLease),
          ),
        );

    // PK now reports the member that the interrupted push created.
    final fakeClient = _FakePluralKitClient(
      membersToReturn: const [
        PKMember(id: 'nv1', uuid: 'uuid-nova', name: 'Nova'),
      ],
    );
    final service = PluralKitSyncService(
      memberRepository: DriftMemberRepository(db.membersDao, null),
      frontingSessionRepository:
          DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      syncDao: db.pluralKitSyncDao,
      bus: PkSyncEventBus(),
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    await service.performOneTimeFullImport(token: 'test-token');

    final rows = await db.select(db.members).get();
    expect(rows.length, 1,
        reason: 'the orphan must be adopted onto the lease-holding member, '
            'not imported as a duplicate');
    final adopted = rows.single;
    expect(adopted.id, 'local-attempted');
    expect(adopted.pluralkitUuid, 'uuid-nova');
    expect(adopted.createPushStartedAt, isNull,
        reason: 'the create lease is cleared once the orphan is adopted');
  });
}
