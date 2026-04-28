/// Integration test: regression coverage for the PluralKit sync unique-
/// constraint catch-site (Layer 1 — synchronous in-process DB).
///
/// GIVEN: an in-memory AppDatabase with a soft-deleted fronting_session whose
///        `pluralkit_uuid = 'X'` and `is_deleted = 1`. This represents the
///        "PK link still attached, mid delete-push" tombstone state — the
///        partial unique index on `pluralkit_uuid` does NOT exclude tombstones,
///        so any future INSERT carrying the same UUID will collide.
/// WHEN:  `performFullImport` is called with a fake PK client serving a single
///        switch whose `id = 'X'`.
/// THEN:  the call returns without throwing, no new (`is_deleted = 0`) row is
///        created with the same `pluralkit_uuid`, and the tombstone is left
///        unchanged.
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
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
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

  test(
    'performFullImport tolerates a tombstoned PK-linked session colliding '
    'on the partial unique index',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // -- Seed a tombstone row carrying pluralkit_uuid='X' ---------------
      // We bypass the repository sync hooks here — this models a row that
      // already exists in the local DB after a soft-delete that hasn't yet
      // pushed up to the relay (and thus hasn't had its PK link cleared).
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

      // The original tombstone is unchanged.
      final allRows = await (db.select(
        db.frontingSessions,
      )..where((s) => s.id.equals('tombstone-id'))).get();
      expect(allRows, hasLength(1));
      final tombstone = allRows.single;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.pluralkitUuid, 'X');
      expect(tombstone.startTime, tombstoneStart);

      // No new live row was created with the same pluralkit_uuid. (The
      // catch site treats a unique-constraint violation as a duplicate, so
      // the import should noop on this switch rather than insert.)
      final liveRowsWithSamePkUuid = await (db.select(db.frontingSessions)
            ..where(
              (s) =>
                  s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
            ))
          .get();
      expect(
        liveRowsWithSamePkUuid,
        isEmpty,
        reason:
            'The catch site should swallow the 2067, not let a new live row '
            'land alongside the tombstone',
      );
    },
  );
}
