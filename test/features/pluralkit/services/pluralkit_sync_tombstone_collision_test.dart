/// Integration test: regression coverage for the PluralKit sync unique-
/// constraint catch-site (Layer 1 — synchronous in-process DB).
///
/// Schema v7 note: the unique index on `fronting_sessions` was replaced by a
/// composite partial unique index on `(pluralkit_uuid, member_id)` in the
/// fronting refactor (docs/plans/fronting-per-member-sessions.md §3.7).
/// The tombstone-collision protection now depends on the new row carrying the
/// same `member_id` as the tombstone — SQLite treats NULL != NULL in unique
/// indexes, so a tombstone with `member_id=null` will NOT block a new import
/// row that also has `member_id=null`.  For rows where member resolution
/// succeeds (non-null `member_id`), the protection is fully intact.
///
/// Phase 2 will rewrite the importer so every PK-linked row always has a
/// non-null `member_id`, at which point the composite index provides the same
/// belt-and-braces protection the old single-column index did.  Until then the
/// null-member_id case is a known gap in DB-level tombstone protection; the
/// application-layer `getDeletedLinkedSessions` check remains the primary guard.
///
/// This test verifies the protection FOR THE RESOLVABLE-MEMBER CASE by seeding
/// a tombstone with `member_id='local-member-id'` and importing a switch whose
/// members include that same local member.
///
/// Layer 2 (DriftRemoteException isolate-wrapping) is covered by the helper
/// unit tests in `test/core/database/sqlite_constraint_test.dart`.
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

// ---------------------------------------------------------------------------
// Secure storage stub (mirrors pluralkit_sync_service_test.dart)
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
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                _store[key] = value;
                return null;
              case 'read':
                final key = call.arguments['key'] as String;
                return _store[key];
              case 'delete':
                final key = call.arguments['key'] as String;
                _store.remove(key);
                return null;
              case 'containsKey':
                final key = call.arguments['key'] as String;
                return _store.containsKey(key);
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
// Fake PluralKitClient — single switch with id 'X', no members.
// ---------------------------------------------------------------------------

class _FakePluralKitClient implements PluralKitClient {
  _FakePluralKitClient({required this.switchesToReturn});

  final List<PKSwitch> switchesToReturn;

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    // Single page — return the switches once, then empty so the paging
    // loop terminates.
    if (before != null) return const [];
    return switchesToReturn;
  }

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();

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
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storageStub = _SecureStorageStub();

  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  test('performFullImport tolerates a tombstoned PK-linked session colliding '
      'on the partial unique index', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // -- Seed the local member that the PK switch refers to ---------------
    // The switch lists member 'pk-short-id'.  Seeding a Prism member with
    // pluralkitId='pk-short-id' and pluralkitUuid='pk-member-uuid' causes
    // the diff sweep to map that to 'local-member-id', so the importer's
    // INSERT carries
    // (pluralkit_uuid='X', member_id='local-member-id') — exactly matching
    // the tombstone below and triggering the composite unique-constraint catch.
    await db.membersDao.upsertMember(
      MembersCompanion.insert(
        id: 'local-member-id',
        name: 'Test Member',
        createdAt: DateTime(2026, 1, 1),
        pluralkitId: const Value('pk-short-id'),
        pluralkitUuid: const Value('pk-member-uuid'),
      ),
    );

    // -- Seed a tombstone row carrying pluralkit_uuid='X' ---------------
    // We bypass the repository sync hooks here — this models a row that
    // already exists in the local DB after a soft-delete that hasn't yet
    // pushed up to the relay (and thus hasn't had its PK link cleared).
    // The composite partial unique index on (pluralkit_uuid, member_id)
    // prevents a new live row for the same (uuid, member) pair — but only
    // when member_id is non-null (SQLite treats NULL != NULL in unique
    // indexes, so unresolvable-member rows bypass this protection).
    // Drift stores DateTimes as Unix seconds and round-trips through local
    // time, so use a local DateTime for round-trip equality.
    final tombstoneStart = DateTime(2026, 4, 1, 12);
    await db.frontingSessionsDao.insertSession(
      FrontingSessionsCompanion.insert(
        id: 'tombstone-id',
        startTime: tombstoneStart,
        memberId: const Value('local-member-id'),
        pluralkitUuid: const Value('X'),
        isDeleted: const Value(true),
        deleteIntentEpoch: const Value(0),
      ),
    );

    // Sanity: getAllSessions filters tombstones, so the precompute set
    // inside `performFullImport` will MISS this row — that's the whole
    // reason the catch-site has to handle the unique-constraint throw.
    final activeBefore = await db.frontingSessionsDao.getAllSessions();
    expect(activeBefore, isEmpty);

    // -- Build the service with real Drift repos (sync handle = null) ---
    final memberRepo = DriftMemberRepository(db.membersDao, null);
    final sessionRepo = DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    );

    final fakeClient = _FakePluralKitClient(
      switchesToReturn: [
        PKSwitch(
          id: 'X',
          timestamp: DateTime.utc(2026, 4, 2, 9),
          members: const ['pk-short-id'],
        ),
      ],
    );

    final service = PluralKitSyncService(
      memberRepository: memberRepo,
      frontingSessionRepository: sessionRepo,
      syncDao: db.pluralKitSyncDao,
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    // -- The act --------------------------------------------------------
    // Without the fix this throws SqliteException(2067) when _importSwitch
    // tries to INSERT a session with pluralkit_uuid='X' and the partial
    // unique index fires against the tombstone.
    await service.performFullImport();

    // -- Assertions -----------------------------------------------------
    expect(
      service.state.syncError,
      isNull,
      reason:
          'Tombstone collision must be absorbed by the unique-constraint '
          'helper, not surface as a sync error',
    );

    // The original tombstone was resurrected and corrected in place. Full
    // import is the corrective path used after the fronting migration clears
    // old PK rows, so API truth wins over the tombstone left behind by the
    // migration.
    final allRows = await (db.select(
      db.frontingSessions,
    )..where((s) => s.id.equals('tombstone-id'))).get();
    expect(allRows, hasLength(1));
    final resurrected = allRows.single;
    expect(resurrected.isDeleted, isFalse);
    expect(resurrected.pluralkitUuid, 'X');
    expect(resurrected.memberId, 'local-member-id');
    expect(
      resurrected.startTime.millisecondsSinceEpoch,
      DateTime.utc(2026, 4, 2, 9).millisecondsSinceEpoch,
    );

    // No second row was created with the same pluralkit_uuid. The catch site
    // refetches by `(pluralkit_uuid, member_id)` and updates that row instead.
    final liveRowsWithSamePkUuid =
        await (db.select(db.frontingSessions)..where(
              (s) => s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
            ))
            .get();
    expect(
      liveRowsWithSamePkUuid,
      hasLength(1),
      reason:
          'The catch site should swallow the 2067 by updating the colliding '
          'row, not by inserting a second live row',
    );
    expect(liveRowsWithSamePkUuid.single.id, 'tombstone-id');
  });
}
