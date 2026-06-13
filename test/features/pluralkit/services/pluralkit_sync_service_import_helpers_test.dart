/// 2026-06 CRDT remediation wave 2, family
/// `pk-import-canonicalization-destruction` — shared infrastructure unit tests.
///
/// Covers the three reusable helpers the later F03/F22/F10 steps wrap their
/// import transactions with:
///
///  (1) `_tombstoneImporterArtifact(rowId)` — clears the PK link FIRST, then
///      soft deletes, so an importer cleanup tombstone never carries a PK link
///      or a `deleteIntentEpoch` stamp (and so `getDeletedLinkedSessions`
///      never selects it for a PluralKit-side DELETE).
///  (2) `_captureImportEmissions(body)` — wraps a PK-import Drift transaction in
///      `suppressAndCapture` and replays post-commit, so ZERO ops reach the FFI
///      path when the wrapped txn throws, and exactly the captured multiset (in
///      capture order) replays on success.
///  (3) `_liveLinkedSwitchUuids(rows)` — the set of `pluralkit_uuid` values on
///      live (non-deleted, uuid-shaped) rows, the switch-level cascade-guard
///      input mirroring `_memberIdsWithLiveLinkedSessions`.
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_fs;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock (mirrors pk_canonicalization_safety_test.dart)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final Map<String, String?> _store = {};

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

// ---------------------------------------------------------------------------
// Minimal fake client — the helpers under test never touch the network, but
// `PluralKitSyncService` requires a `clientFactory`.
// ---------------------------------------------------------------------------

class _FakeClient implements PluralKitClient {
  @override
  String get currentToken => 'fake-token';
  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');
  @override
  Future<List<PKMember>> getMembers() async => const [];
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async =>
      const [];
  @override
  Future<PKSwitch> getSwitch(String switchRef) => throw UnimplementedError();
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(String groupRef, List<String> memberRefs) =>
      throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) => throw UnimplementedError();
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
  Future<PKSwitch> updateSwitchMembers(String switchId, List<String> memberIds) =>
      throw UnimplementedError();
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

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Build the service with the fronting-session repository wired WITH
/// `pkSyncDao` — the production wiring, so `deleteSession`'s intent stamping is
/// live and a regression would surface as a non-null `deleteIntentEpoch`.
({PluralKitSyncService service, DriftFrontingSessionRepository sessionRepo})
_makeService(AppDatabase db) {
  final memberRepo = DriftMemberRepository(db.membersDao, null);
  final sessionRepo = DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
    pkSyncDao: db.pluralKitSyncDao,
  );
  final service = PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => _FakeClient(),
  );
  return (service: service, sessionRepo: sessionRepo);
}

domain_fs.FrontingSession _session({
  required String id,
  String? memberId = 'local-a',
  String? pluralkitUuid,
  bool isDeleted = false,
}) => domain_fs.FrontingSession(
  id: id,
  startTime: DateTime.utc(2026, 1, 1, 10),
  endTime: DateTime.utc(2026, 1, 1, 11),
  memberId: memberId,
  pluralkitUuid: pluralkitUuid,
  isDeleted: isDeleted,
);

const _switchUuidA = '1f1f1f1f-0000-4000-8000-000000000001';
const _switchUuidB = '2f2f2f2f-0000-4000-8000-000000000002';
const _rowIdA = '11111111-2222-4333-8444-555555555555';
const _rowIdB = '99999999-aaaa-4bbb-8ccc-dddddddddddd';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('_liveLinkedSwitchUuids', () {
    test('collects trimmed switch uuids only from live, uuid-linked rows', () {
      final db = _makeDb();
      addTearDown(db.close);
      final service = _makeService(db).service;

      final rows = <domain_fs.FrontingSession>[
        // live + uuid-linked → included (also proves trimming).
        _session(id: _rowIdA, pluralkitUuid: '  $_switchUuidA  '),
        // duplicate uuid on a second live row → still one set entry.
        _session(id: 'dup', pluralkitUuid: _switchUuidA),
        // a second distinct live uuid → included.
        _session(id: _rowIdB, pluralkitUuid: _switchUuidB),
        // deleted row → excluded even though uuid-linked.
        _session(id: 'gone', pluralkitUuid: _switchUuidB, isDeleted: true),
        // non-uuid pk ref (synthetic/file id) → excluded by the strict gate.
        _session(id: 'file', pluralkitUuid: 'not-a-uuid'),
        // unlinked row → excluded.
        _session(id: 'bare', pluralkitUuid: null),
      ];

      final result = service.debugLiveLinkedSwitchUuids(rows);
      expect(result, {_switchUuidA, _switchUuidB});
    });

    test('returns an empty set when no live row is uuid-linked', () {
      final db = _makeDb();
      addTearDown(db.close);
      final service = _makeService(db).service;

      final result = service.debugLiveLinkedSwitchUuids([
        _session(id: 'd', pluralkitUuid: _switchUuidA, isDeleted: true),
        _session(id: 'bare', pluralkitUuid: null),
      ]);
      expect(result, isEmpty);
    });
  });

  group('_tombstoneImporterArtifact', () {
    test(
      'clears the PK link then soft-deletes, stamping NO delete intent and '
      'leaving the row out of getDeletedLinkedSessions',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo) = _makeService(db);

        await sessionRepo.createSession(
          _session(id: _rowIdA, pluralkitUuid: _switchUuidA),
        );

        await service.debugTombstoneImporterArtifact(_rowIdA);

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw, hasLength(1));
        final row = raw.single;
        expect(row.isDeleted, isTrue, reason: 'row is tombstoned');
        expect(
          row.pluralkitUuid,
          anyOf(isNull, ''),
          reason: 'PK link cleared before the soft delete',
        );
        expect(
          row.deleteIntentEpoch,
          isNull,
          reason: 'importer cleanup must never queue a PK API deletion',
        );
        expect(
          await sessionRepo.getDeletedLinkedSessions(),
          isEmpty,
          reason: 'a link-cleared tombstone is not a deletion candidate',
        );
      },
    );

    test(
      'contrast: a plain deleteSession on a still-linked row DOES stamp intent '
      '(proves the helper avoids it by clearing the link first)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo) = _makeService(db);

        await sessionRepo.createSession(
          _session(id: _rowIdA, pluralkitUuid: _switchUuidA),
        );

        // No link-clear: deleteSession sees a linked row and stamps intent.
        await sessionRepo.deleteSession(_rowIdA);

        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw.single.deleteIntentEpoch, isNotNull);
        expect(await sessionRepo.getDeletedLinkedSessions(), hasLength(1));
      },
    );
  });

  group('_captureImportEmissions', () {
    test(
      'on a thrown txn: ZERO ops reach the FFI path and no row is written',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo) = _makeService(db);

        final reached = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(reached.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await expectLater(
          service.debugCaptureImportEmissions<void>(() async {
            await db.transaction(() async {
              await sessionRepo.createSession(
                _session(id: _rowIdA, pluralkitUuid: _switchUuidA),
              );
              throw StateError('mid-loop failure');
            });
          }),
          throwsA(isA<StateError>()),
        );

        // suppressAndCapture intercepted the in-txn emission, and the throw
        // propagated before replay — so the global FFI sink saw nothing.
        expect(
          reached,
          isEmpty,
          reason: 'no op may reach the FFI path on rollback',
        );
        // Drift rolled the transaction back — the row is gone.
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw, isEmpty, reason: 'transaction rolled back');
      },
    );

    test(
      'on success: replays exactly the captured multiset, in capture order',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo) = _makeService(db);

        final replayed = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(replayed.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        // Two artifact rows tombstoned via the family helper inside the txn:
        // each emits one pluralkit_uuid=null update (clearPluralKitLink) then
        // one delete — four ops total, in row order.
        await service.debugCaptureImportEmissions<void>(() async {
          await db.transaction(() async {
            await sessionRepo.createSession(
              _session(id: _rowIdA, pluralkitUuid: _switchUuidA),
            );
            await sessionRepo.createSession(
              _session(id: _rowIdB, pluralkitUuid: _switchUuidB),
            );
            await service.debugTombstoneImporterArtifact(_rowIdA);
            await service.debugTombstoneImporterArtifact(_rowIdB);
          });
        });

        // Every emission inside the wrapper body is captured then replayed
        // post-commit — the two creates and both clear+delete pairs. Assert
        // the exact ordered shape of every replayed op.
        final shape = replayed
            .map((op) => '${op.opType.name}:${op.entityId}')
            .toList();
        expect(shape, [
          'create:$_rowIdA',
          'create:$_rowIdB',
          'update:$_rowIdA', // clearPluralKitLink → pluralkit_uuid=null
          'delete:$_rowIdA',
          'update:$_rowIdB',
          'delete:$_rowIdB',
        ]);
        // The link-clear update carries exactly the nulled link field.
        final clearA = replayed.firstWhere(
          (op) => op.opType == SyncRecordOpType.update && op.entityId == _rowIdA,
        );
        expect(clearA.fields, {'pluralkit_uuid': null});

        // Local DB committed: both rows tombstoned, link cleared, no intent.
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw, hasLength(2));
        for (final row in raw) {
          expect(row.isDeleted, isTrue);
          expect(row.pluralkitUuid, anyOf(isNull, ''));
          expect(row.deleteIntentEpoch, isNull);
        }
      },
    );

    test('returns the body result and replays nothing when no op is emitted',
        () async {
      final db = _makeDb();
      addTearDown(db.close);
      final service = _makeService(db).service;

      final replayed = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(replayed.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final result = await service.debugCaptureImportEmissions<int>(() async {
        return 42;
      });

      expect(result, 42);
      expect(replayed, isEmpty);
    });
  });
}
