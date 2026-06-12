/// Integration test: PluralKit corrective re-import tombstone semantics.
///
/// H5 widened the corrective preserve branch to ANY still-linked tombstone:
/// `is_deleted` syncs but `delete_intent_epoch` is device-local, so a peer's
/// delete arrives intent-less and the old rule resurrected it (undoing the
/// delete everywhere). Rescue/migration tombstones still rebuild because
/// cleanup clears the PK link BEFORE tombstoning (C1).
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
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

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
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  _FakePluralKitClient({required this.switchesToReturn});

  final List<PKSwitch> switchesToReturn;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

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
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
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
    final originalDeleteStartedAt = DateTime.utc(
      2026,
      4,
      1,
      13,
    ).millisecondsSinceEpoch;
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
      bus: PkSyncEventBus(),
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
      reason:
          'corrective import must NOT clear is_deleted on a row whose '
          'deleteIntentEpoch is non-null (user explicitly deleted this row)',
    );
    expect(
      preserved.deleteIntentEpoch,
      0,
      reason:
          'deleteIntentEpoch must remain populated so the queued '
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

  test('corrective re-import preserves an INTENT-LESS tombstone with the '
      'link intact (peer-synced delete, 2026-06 PK audit H5)', () async {
    // The H5 regression guard (this test previously asserted resurrection):
    // a peer's delete arrives intent-less with the link intact, and reviving
    // it aborted the originating device's real PK DELETE. Any still-linked
    // tombstone must be preserved; cleanup tombstones are link-cleared (C1)
    // and never reach this branch.
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
        // No deleteIntentEpoch / deletePushStartedAt: this is what a
        // PEER-synced delete looks like locally — the intent stamp never
        // leaves the device that initiated the delete.
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
      bus: PkSyncEventBus(),
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    final result = await service.performOneTimeFullImport(token: 'test-token');

    // H5: the peer-synced tombstone survives the corrective import.
    final row = await db.frontingSessionsDao.getSessionById('tombstone-id');
    expect(row, isNotNull);
    expect(
      row!.isDeleted,
      isTrue,
      reason:
          'H5: an intent-less tombstone with the PK link intact is a '
          'peer-synced delete — resurrecting it here would propagate back '
          'and abort the originating device\'s pending PK deletion',
    );
    expect(row.deleteIntentEpoch, isNull,
        reason: 'no intent stamp is added — intent stays device-local');
    expect(row.pluralkitUuid, 'X', reason: 'link left intact');
    expect(
      row.startTime.millisecondsSinceEpoch,
      DateTime(2026, 4, 1, 12).millisecondsSinceEpoch,
      reason: 'tombstone untouched — no API-truth rewrite on a preserved row',
    );

    // No parallel live row was inserted for the same switch entrant.
    final liveRowsWithSamePkUuid =
        await (db.select(db.frontingSessions)..where(
              (s) => s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
            ))
            .get();
    expect(liveRowsWithSamePkUuid, isEmpty);

    expect(
      result.tombstonePreservedCount,
      1,
      reason:
          'H5: peer-synced tombstone preservation is surfaced in the '
          'import-result UI alongside intent-stamped ones',
    );
  });

  test('corrective re-import REBUILDS a link-cleared, intent-less tombstone '
      'at the deterministic id (importer/migration cleanup — 2026-06 PK '
      'audit H5 discriminator)', () async {
    // C1-idiom cleanup (e.g. migration step 6) leaves a link-cleared,
    // intent-less tombstone AT the deterministic row id, so the sweep still
    // finds it by id. Post-migration re-import is a documented recovery
    // flow: this shape must REBUILD, not preserve.
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

    const switchId = 'X';
    final deterministicId = derivePkSessionId(switchId, 'pk-member-uuid');
    await db.frontingSessionsDao.insertSession(
      FrontingSessionsCompanion.insert(
        id: deterministicId,
        startTime: DateTime(2026, 4, 1, 12),
        memberId: const Value('local-member-id'),
        // Link cleared before deletion (importer cleanup idiom); no intent.
        isDeleted: const Value(true),
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
          id: switchId,
          timestamp: DateTime.utc(2026, 4, 2, 9),
          members: const ['pk-short-id'],
        ),
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

    final result = await service.performOneTimeFullImport(token: 'test-token');

    final row = await db.frontingSessionsDao.getSessionById(deterministicId);
    expect(row, isNotNull);
    expect(row!.isDeleted, isFalse,
        reason: 'importer-cleanup tombstones rebuild from the API');
    expect(row.pluralkitUuid, switchId, reason: 'link restored to the switch');
    expect(
      row.startTime.millisecondsSinceEpoch,
      DateTime.utc(2026, 4, 2, 9).millisecondsSinceEpoch,
      reason: 'API truth rewrites the rebuilt row',
    );
    expect(result.tombstonePreservedCount, 0,
        reason: 'a rebuild is not a preservation');
  });

  test('link-cleared tombstone (canonicalization / zero-length-close '
      'style) does not block a fresh canonical row', () async {
    // Interaction guard for H5: link-cleared tombstones (canonicalization /
    // zero-length-close) live at random row ids with null uuids, so both
    // entrant lookups miss them and the sweep creates a FRESH live row
    // rather than resurrecting or being blocked.
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

    // A canonicalization-style tombstone: random row id, link CLEARED.
    await db.frontingSessionsDao.insertSession(
      FrontingSessionsCompanion.insert(
        id: 'legacy-rescue-tombstone',
        startTime: DateTime(2026, 4, 1, 12),
        memberId: const Value('local-member-id'),
        // pluralkitUuid deliberately absent (null) — cleared before
        // tombstoning per the C1 idiom.
        isDeleted: const Value(true),
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
      bus: PkSyncEventBus(),
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => fakeClient,
    );

    final result = await service.performOneTimeFullImport(token: 'test-token');

    // The link-cleared tombstone is untouched...
    final tombstone = await db.frontingSessionsDao.getSessionById(
      'legacy-rescue-tombstone',
    );
    expect(tombstone, isNotNull);
    expect(tombstone!.isDeleted, isTrue);
    expect(tombstone.pluralkitUuid, isNull);

    // ...and a FRESH live row was created for the API switch — the
    // tombstone neither blocked the import nor got resurrected.
    final liveRows =
        await (db.select(db.frontingSessions)..where(
              (s) => s.pluralkitUuid.equals('X') & s.isDeleted.equals(false),
            ))
            .get();
    expect(liveRows, hasLength(1));
    expect(liveRows.single.memberId, 'local-member-id');
    expect(
      liveRows.single.startTime.millisecondsSinceEpoch,
      DateTime.utc(2026, 4, 2, 9).millisecondsSinceEpoch,
    );

    expect(
      result.tombstonePreservedCount,
      0,
      reason:
          'a link-cleared tombstone never reaches the collision branch — '
          'nothing was "preserved", a new row was simply created',
    );
  });
}
