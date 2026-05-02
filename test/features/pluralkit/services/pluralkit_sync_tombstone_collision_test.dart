/// Integration test: PluralKit corrective re-import tombstone semantics.
///
/// PR E2 (WS3 step 4 / review #3) changes how the corrective re-import
/// path treats a tombstoned row whose deterministic id collides with an
/// API entrant. The old behavior unconditionally resurrected the row and
/// cleared `isDeleted`, `deleteIntentEpoch`, and `deletePushStartedAt` —
/// which silently undid any user-initiated delete that hadn't yet pushed
/// to PluralKit. The new behavior:
/// - If `deleteIntentEpoch != null` (user explicitly deleted, push queued):
///   leave the tombstone intact, increment `tombstonePreservedCount`, and
///   surface in the import-result UI.
/// - If `deleteIntentEpoch == null` (rescue/migration tombstone): keep the
///   resurrection behavior — that path explicitly relies on corrective
///   re-import to undelete with API truth.
///
/// The composite partial unique index on `(pluralkit_uuid, member_id)`
/// from schema v7 still protects against duplicate live rows when member
/// resolution succeeds (non-null `member_id`); SQLite treats NULL != NULL
/// in unique indexes, so unresolvable-member tombstones bypass the
/// DB-level guard. The application-layer `getDeletedLinkedSessions` check
/// remains the primary guard for that case.
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

  test('corrective re-import on a row with deleteIntentEpoch != null '
      'preserves the user tombstone (WS3 step 4 / review #3)', () async {
    // PR E2 changed the corrective entrant-collision path: a tombstone whose
    // `deleteIntentEpoch` is non-null is treated as an explicit user delete
    // (queued to push to PluralKit). We must NOT silently resurrect it on
    // re-import — the user's intent wins, and the import-result UI surfaces
    // the count via `tombstonePreservedCount`. This test was previously the
    // resurrection-behavior regression guard; PR E2 inverts the assertion.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // -- Seed the local member that the PK switch refers to ---------------
    await db.membersDao.upsertMember(
      MembersCompanion.insert(
        id: 'local-member-id',
        name: 'Test Member',
        createdAt: DateTime(2026, 1, 1),
        pluralkitId: const Value('pk-short-id'),
        pluralkitUuid: const Value('pk-member-uuid'),
      ),
    );

    // -- Seed a tombstone row carrying pluralkit_uuid='X' with explicit
    // delete-intent metadata (deleteIntentEpoch + deletePushStartedAt) so
    // the corrective path can recognize this as a user-initiated delete.
    final tombstoneStart = DateTime(2026, 4, 1, 12);
    final originalDeleteStartedAt = DateTime.utc(2026, 4, 1, 13)
        .millisecondsSinceEpoch;
    await db.frontingSessionsDao.insertSession(
      FrontingSessionsCompanion.insert(
        id: 'tombstone-id',
        startTime: tombstoneStart,
        memberId: const Value('local-member-id'),
        pluralkitUuid: const Value('X'),
        isDeleted: const Value(true),
        deleteIntentEpoch: const Value(0),
        deletePushStartedAt: Value(originalDeleteStartedAt),
      ),
    );

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
    // Use the one-time-import path so we get the result struct back; the
    // corrective entrant collision branch is identical to performFullImport.
    final result = await service.performOneTimeFullImport(token: 'test-token');

    // -- Assertions -----------------------------------------------------
    expect(
      service.state.syncError,
      isNull,
      reason: 'preserving a tombstone is not an error condition',
    );

    // PR E2: the tombstone was preserved, not resurrected.
    final allRows = await (db.select(
      db.frontingSessions,
    )..where((s) => s.id.equals('tombstone-id'))).get();
    expect(allRows, hasLength(1));
    final preserved = allRows.single;
    expect(
      preserved.isDeleted,
      isTrue,
      reason: 'corrective import must NOT clear is_deleted on a row whose '
          'deleteIntentEpoch is non-null (user explicitly deleted this row)',
    );
    expect(
      preserved.deleteIntentEpoch,
      0,
      reason: 'deleteIntentEpoch must remain populated so the queued '
          'PluralKit DELETE still pushes',
    );
    expect(
      preserved.deletePushStartedAt,
      originalDeleteStartedAt,
      reason: 'deletePushStartedAt is left intact (R6 lease unchanged)',
    );
    expect(
      preserved.pluralkitUuid,
      'X',
      reason: 'PK link is left intact for the eventual DELETE push',
    );

    // No live row was created — corrective path skipped the resurrection.
    final liveRowsWithSamePkUuid =
        await (db.select(db.frontingSessions)..where(
              (s) => s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
            ))
            .get();
    expect(
      liveRowsWithSamePkUuid,
      isEmpty,
      reason:
          'No live row should exist — the user tombstone was preserved, '
          'not resurrected, and no parallel row was inserted',
    );

    // The result struct surfaces the count for the import-result UI.
    expect(
      result.tombstonePreservedCount,
      1,
      reason: 'tombstonePreservedCount must report the preserved tombstone',
    );
    expect(result.switchesImported, 1);
    expect(result.unmappedMemberReferences, 0);
    expect(result.zeroLengthCloseSkipped, 0);
  });

  test('corrective re-import without explicit delete intent still '
      'resurrects (rescue/migration tombstone path)', () async {
    // Companion to the test above. A tombstone with `deleteIntentEpoch ==
    // null` is *not* a user-initiated delete — it's a soft-delete left
    // behind by the rescue/migration path that explicitly relies on
    // corrective re-import to undelete with API truth. PR E2 must keep
    // that path working.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.membersDao.upsertMember(
      MembersCompanion.insert(
        id: 'local-member-id',
        name: 'Test Member',
        createdAt: DateTime(2026, 1, 1),
        pluralkitId: const Value('pk-short-id'),
        pluralkitUuid: const Value('pk-member-uuid'),
      ),
    );

    await db.frontingSessionsDao.insertSession(
      FrontingSessionsCompanion.insert(
        id: 'tombstone-id',
        startTime: DateTime(2026, 4, 1, 12),
        memberId: const Value('local-member-id'),
        pluralkitUuid: const Value('X'),
        isDeleted: const Value(true),
        // No deleteIntentEpoch / deletePushStartedAt: this is a
        // migration-style tombstone, not a user delete.
      ),
    );

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

    final result = await service.performOneTimeFullImport(token: 'test-token');

    // No user intent → corrective path resurrects (existing behavior).
    final row = await db.frontingSessionsDao.getSessionById('tombstone-id');
    expect(row, isNotNull);
    expect(row!.isDeleted, isFalse);
    expect(
      row.startTime.millisecondsSinceEpoch,
      DateTime.utc(2026, 4, 2, 9).millisecondsSinceEpoch,
    );
    expect(
      result.tombstonePreservedCount,
      0,
      reason: 'no preserved tombstone — this row had no user-delete intent',
    );
  });
}
