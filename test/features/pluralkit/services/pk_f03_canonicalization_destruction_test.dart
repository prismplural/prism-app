/// 2026-06 CRDT remediation wave 2, family
/// `pk-import-canonicalization-destruction` — F03 (CRITICAL).
///
/// F03: the corrective full import's canonicalization pass soft-deleted stale
/// PK-linked fan-out rows WITHOUT clearing the PK link first, so `deleteSession`
/// stamped a `deleteIntentEpoch` and the next push-enabled sync issued a REAL
/// `DELETE /switches/{uuid}` against the user's PluralKit account — destroying a
/// switch a LIVE canonical row still referenced, cascading into ever more
/// destruction. The remediation:
///
///  (1) routes the canonicalization tombstone through
///      `_tombstoneImporterArtifact` (clear link FIRST → no intent stamp);
///  (2)/(3) wrap the canonicalization AND per-switch sweep transactions in the
///      capture-replay seam so zero CRDT ops leak to peers on a mid-loop throw;
///  (4) adds a switch-level cascade guard to `_pushPendingSwitchDeletions` so a
///      switch still referenced by a live local row is never DELETEd from PK;
///  (5) mirrors that guard in `previewPendingDestructivePush` so the confirm
///      dialog's count matches the real push.
///
/// The canonicalization happy-path (adopt-in-place / H4-skip / rescue-artifact
/// tombstone-with-link-cleared) is covered in `pk_canonicalization_safety_test`
/// and the full A→A+B→A rescue fan-out (now with `pkSyncDao` wired) in
/// `data_import_service_legacy_rescue_test`. This file pins the cascade guard
/// (4)/(5) and the capture-replay (2)/(3) leak-on-throw contract.
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
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Secure-storage mock (mirrors pk_mass_deletion_breaker_test.dart)
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
// Recording client. The cascade guard lives INSIDE the sole-fronter DELETE
// branch (so it never regresses the legitimate H2 members-PATCH), which runs
// AFTER the per-candidate snapshot GET — so the guarded candidate IS `getSwitch`-
// ed, but no `deleteSwitch`/`updateSwitchMembers` mutation may follow. Records
// every call so the tests can pin exactly which PK endpoints were reached.
// ---------------------------------------------------------------------------

class _CountingClient implements PluralKitClient {
  final List<String> deletedSwitches = [];
  final List<String> patchedSwitches = [];
  final List<String> getSwitchCalls = [];

  /// PK-side switch snapshots served by [getSwitch], keyed by uuid. A
  /// sole-fronter snapshot drives the H2 DELETE branch (no co-fronters to
  /// PATCH down to). Absent → 404 (switch gone, clears link without delete).
  final Map<String, PKSwitch> switchSnapshots = {};

  @override
  Future<PKSwitch> getSwitch(String switchRef) async {
    final ref = switchRef.trim();
    getSwitchCalls.add(ref);
    final snapshot = switchSnapshots[ref];
    if (snapshot == null) {
      throw const PluralKitApiError(404, '{"code":20007}', code: 20007);
    }
    return snapshot;
  }

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    patchedSwitches.add(switchId);
    return PKSwitch(
      id: switchId,
      timestamp: DateTime.utc(2026, 1, 1),
      members: memberIds,
    );
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    deletedSwitches.add(switchId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unused by F03 cascade-guard tests: ${invocation.memberName}',
  );
}

/// A push service that records every `pushSwitchDeletion` call. The cascade
/// guard must skip BEFORE this is reached, so the guarded candidate must never
/// appear here.
class _RecordingPushService extends PkPushService {
  const _RecordingPushService(this.pushed);

  final List<String> pushed;

  @override
  Future<void> pushSwitchDeletion(
    String sessionId,
    String pkSwitchId,
    PluralKitClient client,
  ) async {
    pushed.add(pkSwitchId);
  }
}

// ---------------------------------------------------------------------------
// Full-import fake client: drives the REAL `performFullImport` →
// `_runFullImportWithClient` → canonicalization + `_runDiffSweep` path so the
// capture-replay WIRING (fix items 2/3) is exercised end-to-end, not via a
// synthetic body. Members resolve from the local DB; this only needs to serve
// the system, an empty member list, and the switch pages.
// ---------------------------------------------------------------------------

class _FakePkClient implements PluralKitClient {
  _FakePkClient(this.switchPages);

  /// Newest-first pages, popped in order; `[]` ends pagination.
  final List<List<PKSwitch>> switchPages;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async => const PKSystem(id: 'sys', name: 'T');

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) async {
    if (switchPages.isEmpty) return const [];
    return switchPages.removeAt(0);
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unused by F03 import-path tests: ${invocation.memberName}',
  );
}

// ---------------------------------------------------------------------------
// Forwarding fronting-session repository that throws on the Nth
// [clearPluralKitLink] or the Nth [createSession]. Both faults fire INSIDE a
// capture-wrapped import transaction:
//  - clearPluralKitLink: the canonicalization pass tombstones each artifact via
//    `_tombstoneImporterArtifact` (clearPluralKitLink → deleteSession), so a
//    mid-loop clear failure reproduces a throw inside the canonicalization txn
//    (item 2 wrapper);
//  - createSession: the per-switch sweep opens entrant rows via createSession,
//    so a mid-txn create failure reproduces a throw inside the sweep txn
//    (item 3 wrapper).
// In both cases the wrapper must drop every captured op on throw — zero ops to
// the FFI/capture path, nothing committed.
// ---------------------------------------------------------------------------

class _FaultingRepo implements FrontingSessionRepository {
  _FaultingRepo({
    required this.delegate,
    this.throwOnClearCount,
    this.throwOnCreateCount,
  });

  final FrontingSessionRepository delegate;

  /// 1-based: the Nth [clearPluralKitLink] throws; 1..(N-1) delegate normally.
  final int? throwOnClearCount;

  /// 1-based: the Nth [createSession] throws; 1..(N-1) delegate normally.
  final int? throwOnCreateCount;

  int _clearCalls = 0;
  int _createCalls = 0;

  @override
  Future<void> clearPluralKitLink(String id) async {
    _clearCalls++;
    if (_clearCalls == throwOnClearCount) {
      throw StateError('flaky clearPluralKitLink failure on call $_clearCalls');
    }
    return delegate.clearPluralKitLink(id);
  }

  @override
  Future<void> createSession(domain_fs.FrontingSession session) async {
    _createCalls++;
    if (_createCalls == throwOnCreateCount) {
      throw StateError('flaky createSession failure on call $_createCalls');
    }
    return delegate.createSession(session);
  }

  // -- All other interface methods: delegate verbatim -----------------------
  @override
  Future<List<domain_fs.FrontingSession>> getAllSessions() =>
      delegate.getAllSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getFrontingSessions() =>
      delegate.getFrontingSessions();
  @override
  Stream<List<domain_fs.FrontingSession>> watchAllSessions() =>
      delegate.watchAllSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getActiveSessions() =>
      delegate.getActiveSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getAllActiveSessionsUnfiltered() =>
      delegate.getAllActiveSessionsUnfiltered();
  @override
  Stream<List<domain_fs.FrontingSession>> watchActiveSessions() =>
      delegate.watchActiveSessions();
  @override
  Future<domain_fs.FrontingSession?> getActiveSession() =>
      delegate.getActiveSession();
  @override
  Stream<domain_fs.FrontingSession?> watchActiveSession() =>
      delegate.watchActiveSession();
  @override
  Stream<domain_fs.FrontingSession?> watchActiveSleepSession() =>
      delegate.watchActiveSleepSession();
  @override
  Stream<List<domain_fs.FrontingSession>> watchAllSleepSessions() =>
      delegate.watchAllSleepSessions();
  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) => delegate.getSleepStats(since: since, until: until);
  @override
  Stream<List<domain_fs.FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) => delegate.watchRecentSleepSessions(limit: limit);
  @override
  Future<domain_fs.FrontingSession?> getSessionById(String id) =>
      delegate.getSessionById(id);
  @override
  Stream<domain_fs.FrontingSession?> watchSessionById(String id) =>
      delegate.watchSessionById(id);
  @override
  Future<List<domain_fs.FrontingSession>> getSessionsForMember(
    String memberId,
  ) => delegate.getSessionsForMember(memberId);
  @override
  Future<List<domain_fs.FrontingSession>> getRecentSessions({int limit = 20}) =>
      delegate.getRecentSessions(limit: limit);
  @override
  Future<List<domain_fs.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) => delegate.getRecentSleepSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchRecentSessions({
    int limit = 20,
  }) => delegate.watchRecentSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) => delegate.watchRecentAllSessions(limit: limit);
  @override
  Stream<List<domain_fs.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) => delegate.watchSessionsOverlappingRange(start, end);
  @override
  Future<void> updateSession(domain_fs.FrontingSession session) =>
      delegate.updateSession(session);
  @override
  Future<void> endSession(String id, DateTime endTime) =>
      delegate.endSession(id, endTime);
  @override
  Future<void> deleteSession(String id) => delegate.deleteSession(id);
  @override
  Future<List<domain_fs.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) => delegate.getSessionsBetween(start, end);
  @override
  Future<int> getCount() => delegate.getCount();
  @override
  Future<int> getFrontingCount() => delegate.getFrontingCount();
  @override
  Future<List<domain_fs.FrontingSession>> getDeletedLinkedSessions() =>
      delegate.getDeletedLinkedSessions();
  @override
  Future<List<domain_fs.FrontingSession>> getDeletedSleepSessions() =>
      delegate.getDeletedSleepSessions();
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      delegate.stampDeletePushStartedAt(id, timestampMs);
  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) => delegate.getMemberFrontingCounts(
    recentLimit: recentLimit,
    startHour: startHour,
    endHour: endHour,
    withinDays: withinDays,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

domain.Member _member({
  required String localId,
  String pkShortId = 'pkA',
  String pkUuid = 'uuid-a',
}) => domain.Member(
  id: localId,
  name: 'Member $localId',
  emoji: '❔',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  pluralkitId: pkShortId,
  pluralkitUuid: pkUuid,
);

({
  PluralKitSyncService service,
  DriftFrontingSessionRepository sessionRepo,
  DriftMemberRepository memberRepo,
})
_makeService(AppDatabase db, PluralKitClient client) {
  final memberRepo = DriftMemberRepository(
    db.membersDao,
    null,
    pkSyncDao: db.pluralKitSyncDao,
  );
  // Repository wired WITH `pkSyncDao` so `deleteSession`'s intent stamping is
  // live and a real deletion candidate can be produced.
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
    clientFactory: (_) => client,
  );
  return (service: service, sessionRepo: sessionRepo, memberRepo: memberRepo);
}

domain_fs.FrontingSession _session({
  required String id,
  required String pluralkitUuid,
  String memberId = 'local-a',
  bool open = false,
}) => domain_fs.FrontingSession(
  id: id,
  startTime: DateTime.utc(2026, 1, 1, 10),
  endTime: open ? null : DateTime.utc(2026, 1, 1, 11),
  memberId: memberId,
  pluralkitUuid: pluralkitUuid,
);

// A real PK switch uuid (strict 8-4-4-4-12 hex) shared by the fan-out siblings.
const _sharedSwitchUuid = '1f1f1f1f-0000-4000-8000-000000000001';
const _tombstonedRowId = '11111111-2222-4333-8444-555555555555';
const _liveRowId = '99999999-aaaa-4bbb-8ccc-dddddddddddd';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('F03 switch-level cascade guard', () {
    test('a queued switch deletion whose uuid is still on a LIVE local row is '
        'NEVER pushed — pushSwitchDeletion uncalled, no PK mutation, onStaleLink '
        'fires', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final client = _CountingClient();
      final (:service, :sessionRepo, :memberRepo) = _makeService(db, client);
      await memberRepo.createMember(_member(localId: 'local-a'));
      await memberRepo.createMember(
        _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
      );

      // A fan-out sibling for member A that was tombstoned and intent-stamped
      // (the C1 residual): create it linked, then `deleteSession` it (stamps
      // intent, keeps the uuid) — exactly the deletion-candidate shape.
      await sessionRepo.createSession(
        _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
      );
      await sessionRepo.deleteSession(_tombstonedRowId);

      // A still-LIVE canonical row for member B referencing the SAME switch
      // uuid (a genuine cross-member fan-out: the composite uniqueness key is
      // (pluralkit_uuid, member_id), so the shared switch is legal here). Its
      // presence is what must hold the switch DELETE back.
      await sessionRepo.createSession(
        _session(
          id: _liveRowId,
          pluralkitUuid: _sharedSwitchUuid,
          memberId: 'local-b',
          open: true,
        ),
      );

      // PK's authoritative snapshot lists ONLY the departing member A — i.e. PK
      // and the device DISAGREE: locally B is still on this switch, but PK is
      // not. That drives the H2 logic to the SOLE-fronter DELETE branch, which
      // is exactly where deleting the switch would erase B's live PK history.
      // The cascade guard must refuse the DELETE there.
      client.switchSnapshots[_sharedSwitchUuid] = PKSwitch(
        id: _sharedSwitchUuid,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      // Sanity: the tombstoned row really is an eligible deletion candidate.
      final queued = await sessionRepo.getDeletedLinkedSessions();
      expect(
        queued.map((s) => s.id),
        contains(_tombstonedRowId),
        reason: 'control: the tombstoned row is a real deletion candidate',
      );

      final pushed = <String>[];
      final staleMessages = <String>[];
      final deleted = await service.debugPushPendingSwitchDeletions(
        client: client,
        onStaleLink: staleMessages.add,
        pushServiceOverride: _RecordingPushService(pushed),
      );

      expect(deleted, 0, reason: 'cascade guard skipped the only candidate');
      expect(
        pushed,
        isEmpty,
        reason: 'pushSwitchDeletion must never be reached for a guarded uuid',
      );
      expect(
        client.deletedSwitches,
        isEmpty,
        reason: 'no DELETE /switches against live PK history',
      );
      expect(
        client.patchedSwitches,
        isEmpty,
        reason: 'PK lists only the departing member → no co-fronter PATCH',
      );
      // The guard lives in the DELETE branch, so the candidate IS GETted (we
      // need the PK snapshot to know it is a sole-fronter divergence) — but no
      // mutation may follow.
      expect(
        client.getSwitchCalls,
        [_sharedSwitchUuid],
        reason:
            'the guarded candidate is GETted once (DELETE-branch placement) '
            'but never mutated',
      );
      expect(
        staleMessages,
        isNotEmpty,
        reason: 'the user is told via the stale-link channel',
      );

      // The live row is untouched; the tombstoned candidate keeps its link
      // (we did NOT clear it — a later explicit delete of the live row could
      // legitimately re-enable the push).
      final live = await sessionRepo.getSessionById(_liveRowId);
      expect(live, isNotNull);
      expect(live!.isDeleted, isFalse);
      expect(live.pluralkitUuid, _sharedSwitchUuid);
    });

    test('a case-variant live ref does NOT slip past the guard — the queued '
        'uuid and the live-row uuid differ only in hex case', () async {
      // `isPluralKitSwitchUuid` accepts mixed-case hex, so a queued candidate
      // and a live row can carry the SAME logical switch under different
      // casing. The guard must lowercase both sides or it would DELETE the
      // switch out from under the live row.
      final upperUuid = _sharedSwitchUuid.toUpperCase();

      final db = _makeDb();
      addTearDown(db.close);
      final client = _CountingClient();
      final (:service, :sessionRepo, :memberRepo) = _makeService(db, client);
      await memberRepo.createMember(_member(localId: 'local-a'));
      await memberRepo.createMember(
        _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
      );

      // Queued candidate carries the UPPERCASE form...
      await sessionRepo.createSession(
        _session(id: _tombstonedRowId, pluralkitUuid: upperUuid),
      );
      await sessionRepo.deleteSession(_tombstonedRowId);
      // ...while the live row carries the lowercase form of the same switch.
      await sessionRepo.createSession(
        _session(
          id: _liveRowId,
          pluralkitUuid: _sharedSwitchUuid,
          memberId: 'local-b',
          open: true,
        ),
      );

      // PK lists only the departing member → the push would reach the
      // sole-fronter DELETE branch where the case-normalized guard must fire.
      client.switchSnapshots[upperUuid] = PKSwitch(
        id: upperUuid,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      // Preview: the case-variant live ref makes this a live-referenced
      // candidate, so it is a member removal — not a full DELETE, not a skip.
      final preview = await service.previewPendingDestructivePush();
      expect(preview.switchesToDelete, 0);
      expect(preview.switchMemberRemovals, 1);
      expect(preview.switchesSkipped, 0);

      // Push: the cascade guard fires despite the case difference → no DELETE.
      final pushed = <String>[];
      final deleted = await service.debugPushPendingSwitchDeletions(
        client: client,
        pushServiceOverride: _RecordingPushService(pushed),
      );
      expect(deleted, 0);
      expect(pushed, isEmpty);
      expect(
        client.deletedSwitches,
        isEmpty,
        reason: 'a case-variant live ref must still hold the DELETE back',
      );
    });

    test(
      'previewPendingDestructivePush counts a live-referenced candidate as a '
      'switchMemberRemoval (a pushable PATCH), NOT as a skip — and that count '
      'forces the confirmation gate (hasRemovals && isSignificant)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final client = _CountingClient();
        final (:service, :sessionRepo, :memberRepo) = _makeService(db, client);
        await memberRepo.createMember(_member(localId: 'local-a'));
        await memberRepo.createMember(
          _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        );

        await sessionRepo.createSession(
          _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
        );
        await sessionRepo.deleteSession(_tombstonedRowId);
        await sessionRepo.createSession(
          _session(
            id: _liveRowId,
            pluralkitUuid: _sharedSwitchUuid,
            memberId: 'local-b',
            open: true,
          ),
        );

        final preview = await service.previewPendingDestructivePush();
        // The live-referenced candidate is NOT a full switch DELETE...
        expect(
          preview.switchesToDelete,
          0,
          reason: 'a live local row references this switch → no full DELETE',
        );
        // ...but the push CAN still PATCH the member off the switch (the H2
        // path runs before the sole-fronter cascade guard), so it must NOT be
        // bucketed with the can't-touch skips — count it as a member removal.
        expect(
          preview.switchMemberRemovals,
          1,
          reason: 'the push may PATCH the departing member off the PK switch',
        );
        expect(
          preview.switchesSkipped,
          0,
          reason: 'a pushable PATCH candidate is not a skip',
        );
        // Binding 2026-06-11 decision: ANY pending PK switch removal requires
        // explicit confirmation. The single member-removal must trip BOTH
        // gates even though it is below the legacy >=10 switch-delete threshold.
        expect(preview.hasRemovals, isTrue);
        expect(
          preview.isSignificant,
          isTrue,
          reason:
              'a lone live-referenced removal must surface the confirm dialog, '
              'not hide behind the >=10 switchesToDelete threshold',
        );
      },
    );

    test('with NO live sibling, the same candidate is NOT guarded — it deletes '
        'normally (proves the guard is the live-row reference, not a blanket '
        'block)', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final client = _CountingClient();
      final (:service, :sessionRepo, :memberRepo) = _makeService(db, client);
      await memberRepo.createMember(_member(localId: 'local-a'));

      await sessionRepo.createSession(
        _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
      );
      await sessionRepo.deleteSession(_tombstonedRowId);
      // No live row references the switch this time. Serve a sole-fronter
      // snapshot so the H2 path takes its DELETE branch.
      client.switchSnapshots[_sharedSwitchUuid] = PKSwitch(
        id: _sharedSwitchUuid,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        members: const ['pkA'],
      );

      // The preview (before the push, while the row is still queued) must agree:
      // no live sibling → one to delete, zero skipped.
      final previewBefore = await service.previewPendingDestructivePush();
      expect(previewBefore.switchesToDelete, 1);
      expect(previewBefore.switchesSkipped, 0);

      final pushed = <String>[];
      final deleted = await service.debugPushPendingSwitchDeletions(
        client: client,
        pushServiceOverride: _RecordingPushService(pushed),
      );

      expect(
        deleted,
        1,
        reason: 'no live sibling → the delete proceeds (sole-fronter DELETE)',
      );
      expect(pushed, [_sharedSwitchUuid]);
    });

    test(
      'the guard does NOT block the legitimate H2 members-PATCH path: PK still '
      'lists co-fronters → remove only the departing member, switch preserved',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final client = _CountingClient();
        final (:service, :sessionRepo, :memberRepo) = _makeService(db, client);
        await memberRepo.createMember(_member(localId: 'local-a'));
        await memberRepo.createMember(
          _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        );

        // A departs the shared switch (tombstoned), B stays (live local row).
        await sessionRepo.createSession(
          _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
        );
        await sessionRepo.deleteSession(_tombstonedRowId);
        await sessionRepo.createSession(
          _session(
            id: _liveRowId,
            pluralkitUuid: _sharedSwitchUuid,
            memberId: 'local-b',
            open: true,
          ),
        );

        // PK STILL lists both A and B on the switch — so the audit's H2 logic
        // PATCHes the switch down to [B] (a per-member removal, NOT a switch
        // DELETE). The cascade guard must NOT short-circuit this safe path.
        client.switchSnapshots[_sharedSwitchUuid] = PKSwitch(
          id: _sharedSwitchUuid,
          timestamp: DateTime.utc(2026, 1, 1, 10),
          members: const ['pkA', 'pkB'],
        );

        final deleted = await service.debugPushPendingSwitchDeletions(
          client: client,
        );

        expect(
          deleted,
          1,
          reason: 'the per-member removal completed via members PATCH',
        );
        expect(
          client.deletedSwitches,
          isEmpty,
          reason: 'the shared switch is preserved for the continuing member',
        );
        expect(
          client.patchedSwitches,
          [_sharedSwitchUuid],
          reason: 'only the departing member was removed, switch kept (H2)',
        );
      },
    );
  });

  group('F03 capture-replay leak-on-throw (canonicalization txn wrapper)', () {
    test(
      'a mid-loop throw inside the wrapped txn emits ZERO ops to the FFI path '
      'and tombstones nothing',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo, memberRepo: _) = _makeService(
          db,
          _CountingClient(),
        );

        // Two live, linked rows the body will tombstone via the family helper
        // before it throws.
        await sessionRepo.createSession(
          _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
        );
        await sessionRepo.createSession(
          _session(
            id: _liveRowId,
            pluralkitUuid: '2f2f2f2f-0000-4000-8000-000000000002',
          ),
        );

        final reached = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(reached.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await expectLater(
          service.debugCaptureImportEmissions<void>(() async {
            await db.transaction(() async {
              await service.debugTombstoneImporterArtifact(_tombstonedRowId);
              await service.debugTombstoneImporterArtifact(_liveRowId);
              throw StateError('canonicalization mid-loop failure');
            });
          }),
          throwsA(isA<StateError>()),
        );

        // No op leaked to peers, and the Drift rollback left both rows LIVE
        // with their links intact — nothing was destroyed.
        expect(
          reached,
          isEmpty,
          reason: 'no absorbing tombstone may leak to peers on rollback',
        );
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw, hasLength(2));
        for (final row in raw) {
          expect(row.isDeleted, isFalse, reason: 'transaction rolled back');
          expect(row.pluralkitUuid, isNotNull);
          expect(row.deleteIntentEpoch, isNull);
        }
      },
    );

    test(
      'on the success path the wrapper replays exactly one link-clear update + '
      'one delete per artifact row, in capture order',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final (:service, :sessionRepo, memberRepo: _) = _makeService(
          db,
          _CountingClient(),
        );

        await sessionRepo.createSession(
          _session(id: _tombstonedRowId, pluralkitUuid: _sharedSwitchUuid),
        );
        await sessionRepo.createSession(
          _session(
            id: _liveRowId,
            pluralkitUuid: '2f2f2f2f-0000-4000-8000-000000000002',
          ),
        );

        final replayed = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(replayed.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await service.debugCaptureImportEmissions<void>(() async {
          await db.transaction(() async {
            await service.debugTombstoneImporterArtifact(_tombstonedRowId);
            await service.debugTombstoneImporterArtifact(_liveRowId);
          });
        });

        final shape = replayed
            .map((op) => '${op.opType.name}:${op.entityId}')
            .toList();
        expect(shape, [
          'update:$_tombstonedRowId', // clearPluralKitLink → pluralkit_uuid=null
          'delete:$_tombstonedRowId',
          'update:$_liveRowId',
          'delete:$_liveRowId',
        ]);
        final clear = replayed.firstWhere(
          (op) =>
              op.opType == SyncRecordOpType.update &&
              op.entityId == _tombstonedRowId,
        );
        expect(clear.fields, {'pluralkit_uuid': null});

        // Local DB committed: both tombstoned, link cleared, NO delete intent.
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(raw, hasLength(2));
        for (final row in raw) {
          expect(row.isDeleted, isTrue);
          expect(row.pluralkitUuid, anyOf(isNull, ''));
          expect(row.deleteIntentEpoch, isNull);
        }
        expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
      },
    );
  });

  // These tests pin the capture-wrapper WIRING on the REAL import path. The
  // synthetic-body tests above prove the seam's behavior; these prove the seam
  // is actually installed around the canonicalization txn (item 2) and the
  // per-switch sweep txn (item 3). Removing either `_captureImportEmissions`
  // wrapper makes the in-txn emissions reach the capture sink BEFORE the Drift
  // rollback, so these go red — closing the reviewer's "a reverted wrapper
  // still passes" gap.
  group('F03 capture-wrapper wiring on the real import path', () {
    test(
      'a throw INSIDE the canonicalization txn (real performFullImport) leaks '
      'ZERO ops to the FFI path and tombstones nothing',
      () async {
        const staleUuidA = '3a3a3a3a-0000-4000-8000-00000000000a';
        const staleUuidB = '3b3b3b3b-0000-4000-8000-00000000000b';
        const freshSwitchUuid = '3c3c3c3c-0000-4000-8000-00000000000c';

        final db = _makeDb();
        addTearDown(db.close);
        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        await memberRepo.createMember(_member(localId: 'local-a'));

        final realRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        // Two stale PK-linked rows for A on switches the API will NOT report —
        // both become non-canonical and canonicalization tombstones each via
        // `_tombstoneImporterArtifact` (clearPluralKitLink → deleteSession).
        await realRepo.createSession(
          _session(id: _tombstonedRowId, pluralkitUuid: staleUuidA),
        );
        await realRepo.createSession(
          _session(id: _liveRowId, pluralkitUuid: staleUuidB),
        );

        // Throw on the 2nd clearPluralKitLink — i.e. mid-canonicalization,
        // after the first artifact's clear+delete and the second's clear has
        // begun. Without the wrapper, the first row's ops would already have
        // hit the sink.
        final flakyRepo = _FaultingRepo(
          delegate: realRepo,
          throwOnClearCount: 2,
        );

        // API truth: only sw-fresh (A enters). Both stale rows are
        // non-canonical → canonicalization tombstones both.
        final client = _FakePkClient([
          [
            PKSwitch(
              id: freshSwitchUuid,
              timestamp: DateTime.utc(2026, 1, 1, 10),
              members: const ['pkA'],
            ),
          ],
          const [],
        ]);

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: flakyRepo,
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => client,
        );
        await service.setToken('t');
        await service.confirmDirection();
        await service.acknowledgeMapping();

        final reached = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(reached.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await expectLater(
          service.performFullImport(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('flaky'),
            ),
          ),
        );

        // The canonicalization txn rolled back AND no op leaked: both stale
        // rows stay LIVE with links intact. (A reverted wrapper emits the
        // first row's clear+delete to the sink before the throw → fails.)
        expect(
          reached,
          isEmpty,
          reason:
              'item 2: the canonicalization txn must be wrapped — zero ops may '
              'reach the FFI/capture path when the txn rolls back',
        );
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        for (final id in [_tombstonedRowId, _liveRowId]) {
          final row = raw.firstWhere((r) => r.id == id);
          expect(row.isDeleted, isFalse, reason: '$id rolled back to live');
          expect(
            row.pluralkitUuid,
            isNotNull,
            reason: '$id keeps its PK link after rollback',
          );
          expect(row.deleteIntentEpoch, isNull);
        }
      },
    );

    test(
      'a throw INSIDE the per-switch sweep txn (real performFullImport) leaks '
      'ZERO ops and commits no entrant for that switch',
      () async {
        const switchUuid = '4d4d4d4d-0000-4000-8000-00000000000d';

        final db = _makeDb();
        addTearDown(db.close);
        final memberRepo = DriftMemberRepository(
          db.membersDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        await memberRepo.createMember(_member(localId: 'local-a'));
        await memberRepo.createMember(
          _member(localId: 'local-b', pkShortId: 'pkB', pkUuid: 'uuid-b'),
        );

        final realRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
          pkSyncDao: db.pluralKitSyncDao,
        );
        // One switch where BOTH A and B enter — the sweep opens two entrant
        // rows in a SINGLE per-switch transaction (createSession ×2). Fault the
        // 2nd createSession so the throw fires AFTER the first entrant's op was
        // captured: the wrapper must drop it (sink stays empty); a reverted
        // wrapper would have emitted the first create to the sink before the
        // throw.
        final flakyRepo = _FaultingRepo(
          delegate: realRepo,
          throwOnCreateCount: 2,
        );

        final client = _FakePkClient([
          [
            PKSwitch(
              id: switchUuid,
              timestamp: DateTime.utc(2026, 1, 1, 11),
              members: const ['pkA', 'pkB'],
            ),
          ],
          const [],
        ]);

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: flakyRepo,
          syncDao: db.pluralKitSyncDao,
          bus: PkSyncEventBus(),
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => client,
        );
        await service.setToken('t');
        await service.confirmDirection();
        await service.acknowledgeMapping();

        final reached = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(reached.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await expectLater(
          service.performFullImport(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('flaky'),
            ),
          ),
        );

        // No op leaked from the rolled-back sweep txn, and NEITHER entrant row
        // was committed. (A reverted sweep wrapper would have emitted the first
        // entrant's create to the sink before the 2nd create threw.)
        expect(
          reached,
          isEmpty,
          reason:
              'item 3: the per-switch sweep txn must be wrapped — zero ops may '
              'reach the FFI/capture path when the sweep txn rolls back',
        );
        final raw = await db.frontingSessionsDao
            .getAllSessionsIncludingDeleted();
        expect(
          raw.where((r) => r.pluralkitUuid == switchUuid),
          isEmpty,
          reason: 'the sweep txn rolled back — no entrant row persisted',
        );
      },
    );
  });
}
