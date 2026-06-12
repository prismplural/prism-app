/// 2026-06 PK audit M1 (wave 4) — service-level pull mutual exclusion.
///
/// The audit's verified defects, each pinned here against the REAL entry
/// points (no seams that bypass the gate):
///
/// (a) `syncRecentData`'s first-sync branch awaited a token read BEFORE
///     `performFullImport` claimed `isSyncing`, so two concurrent callers
///     could both enter; the loser silently no-op'd inside the import yet
///     still stamped `lastManualSyncDate` and emitted a successful
///     `PkSyncCompleted(0,0)` that never ran.
/// (b) the 60s manual cooldown was UI-advisory only — the fronting screen's
///     sync button called `syncRecentData(isManual: true)` with no check.
/// (c) `importFromFile` had no re-entrancy guard at all.
/// (d) `pollFrontersOnly` checked `isSyncing` but never claimed it, so a
///     poll-driven sweep could interleave with an in-flight incremental
///     sweep (two independent in-memory active maps re-closing rows at
///     different timestamps).
///
/// The fix is a single synchronous `_pullInFlight` gate claimed with no
/// awaits between check and set at every pull entry point, plus in-service
/// cooldown enforcement via [PkManualSyncCooldownException]. These tests
/// drive a REAL hang (a Completer-gated fake client) so the loser races the
/// winner through the genuine await gaps.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/fake_repositories.dart';
import '../../../helpers/pluralkit_fake_client.dart';

// ---------------------------------------------------------------------------
// Secure-storage stub (same shape as the neighbouring service tests).
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final Map<String, String?> store = {};

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    store.clear();
  }
}

// ---------------------------------------------------------------------------
// Gated client: getSystem can be held on a Completer so a pull genuinely
// hangs mid-flight while a second caller races it.
// ---------------------------------------------------------------------------

class _GatedClient extends FakePluralKitClient {
  /// While non-null, [getSystem] parks on this future after incrementing
  /// [getSystemEntered]. Set AFTER setup (setToken also calls getSystem).
  Completer<void>? holdGetSystem;

  /// When non-null, [getSystem] throws this instead of returning.
  Object? throwOnGetSystem;

  /// Incremented BEFORE the hold, so tests can poll "the pull reached the
  /// hang point" without racing the counter in [getSystemCallCount] (which
  /// the base class increments only when the call completes).
  int getSystemEntered = 0;

  /// The shared helper fake doesn't count fronters calls; the poll tests
  /// assert "busy poll never touches the network" off this.
  int getCurrentFrontersCallCount = 0;

  @override
  Future<PKSystem> getSystem() async {
    getSystemEntered++;
    final hold = holdGetSystem;
    if (hold != null) await hold.future;
    final error = throwOnGetSystem;
    if (error != null) throw error;
    return super.getSystem();
  }

  @override
  Future<PKSwitch?> getCurrentFronters() async {
    getCurrentFrontersCallCount++;
    return super.getCurrentFronters();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

PluralKitSyncService _makeService({
  required AppDatabase db,
  required _GatedClient client,
  required PkSyncEventBus bus,
}) {
  return PluralKitSyncService(
    memberRepository: FakeMemberRepository(),
    frontingSessionRepository: FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    bus: bus,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
  );
}

/// Connect + confirm direction + acknowledge mapping so `canAutoSync` is true
/// and `lastSyncDate` is null (the first-sync branch).
Future<void> _connect(PluralKitSyncService service) async {
  await service.setToken('valid-token');
  await service.confirmDirection();
  await service.acknowledgeMapping();
}

/// Pump the event loop until [condition] holds (bounded so a regression fails
/// the test instead of deadlocking it).
Future<void> _pumpUntil(bool Function() condition, {int maxTurns = 200}) async {
  for (var i = 0; i < maxTurns; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition not reached after $maxTurns event-loop turns');
}

PkFileExport _export({int switches = 1}) => PkFileExport(
  system: const PKSystem(id: 'pk-system', name: 'Test PK System'),
  members: const [PKMember(id: 'pkf01', uuid: 'uuid-file-1', name: 'FileM')],
  groups: const [],
  switches: [
    for (var i = 0; i < switches; i++)
      PkFileSwitch(
        timestamp: DateTime.utc(2026, 1, 1 + i),
        memberIds: const ['pkf01'],
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();

  setUp(() {
    storageStub.setup();
    markPkBusMainIsolate();
  });
  tearDown(() {
    storageStub.teardown();
    resetPkBusMainIsolateForTest();
  });

  group('M1 — concurrent double entry (the audit scenario)', () {
    test(
      'second syncRecentData caller during the first-sync await gap is busy: '
      'no cooldown stamp, no phantom PkSyncCompleted',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _GatedClient();
        final service = _makeService(db: db, client: client, bus: capture.bus);
        await _connect(service);
        expect(service.state.lastSyncDate, isNull);

        // Park the first caller deep inside the full import (after the
        // first-sync branch's token-read await gap — the exact window the
        // audit exploited).
        client.holdGetSystem = Completer<void>();
        final winner = service.syncRecentData(isManual: true);
        await _pumpUntil(() => client.getSystemEntered >= 1);
        expect(service.pullInFlightForTesting, isTrue);

        // The loser must observe "busy" SYNCHRONOUSLY: null result, and —
        // the actual audit bug — NO lastManualSyncDate stamp and NO
        // successful PkSyncCompleted(0,0) for a sync that never ran.
        final loserResult = await service.syncRecentData(isManual: true);
        expect(loserResult, isNull);

        final rowMidFlight = await db.pluralKitSyncDao.getSyncState();
        expect(
          rowMidFlight.lastManualSyncDate,
          isNull,
          reason: 'the busy loser must not stamp the manual-sync cooldown',
        );
        expect(
          capture.events.whereType<PkSyncCompleted>(),
          isEmpty,
          reason: 'the busy loser must not emit a phantom success event',
        );
        // Exactly one PkSyncStarted — the winner's. The loser bails before
        // any bus emission.
        expect(capture.events.whereType<PkSyncStarted>(), hasLength(1));

        // Release the winner; IT completes and stamps.
        client.holdGetSystem!.complete();
        await winner;
        expect(service.pullInFlightForTesting, isFalse);

        final rowAfter = await db.pluralKitSyncDao.getSyncState();
        expect(rowAfter.lastManualSyncDate, isNotNull);
        final completions = capture.events
            .whereType<PkSyncCompleted>()
            .toList();
        expect(completions, hasLength(1));
        expect(completions.single.error, isNull);
      },
    );

    test('pollFrontersOnly no-ops while a pull is in flight (defect d)', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _GatedClient();
      final service = _makeService(db: db, client: client, bus: capture.bus);
      await _connect(service);

      client.holdGetSystem = Completer<void>();
      final winner = service.syncRecentData();
      await _pumpUntil(() => client.getSystemEntered >= 1);

      // Pre-fix, the poll passed the bare isSyncing CHECK in this window
      // (the winner held the gate but the poll never claimed anything) and
      // ran a second sweep against the same rows.
      final outcome = await service.pollFrontersOnly();
      expect(outcome, PkPollOutcome.skipped);
      expect(
        client.getCurrentFrontersCallCount,
        0,
        reason: 'a busy poll must bail before touching the network',
      );

      client.holdGetSystem!.complete();
      await winner;

      // After the pull releases the gate, polling works again (and is a
      // healthy skip here because the fake reports no current fronters).
      final after = await service.pollFrontersOnly();
      expect(after, PkPollOutcome.skipped);
      expect(client.getCurrentFrontersCallCount, 1);
    });

    test('importFromFile is rejected while a pull is in flight (defect c)', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _GatedClient();
      final memberRepo = FakeMemberRepository();
      final service = PluralKitSyncService(
        memberRepository: memberRepo,
        frontingSessionRepository: FakeFrontingSessionRepository(),
        syncDao: db.pluralKitSyncDao,
        bus: capture.bus,
        secureStorage: const FlutterSecureStorage(),
        clientFactory: (_) => client,
      );
      await _connect(service);

      client.holdGetSystem = Completer<void>();
      final winner = service.syncRecentData();
      await _pumpUntil(() => client.getSystemEntered >= 1);

      // Pre-fix this method had NO guard at all and would import members
      // concurrently with the in-flight sweep.
      final result = await service.importFromFile(_export(switches: 2));
      expect(result.membersImported, 0);
      expect(result.groupsImported, 0);
      expect(result.switchesSkipped, 2);
      expect(
        await memberRepo.getAllMembers(),
        isEmpty,
        reason: 'a busy file import must not write any members',
      );

      client.holdGetSystem!.complete();
      await winner;
    });

    test(
      'importFromFileWithToken returns the busy sentinel while a pull is in '
      'flight',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _GatedClient();
        final memberRepo = FakeMemberRepository();
        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: FakeFrontingSessionRepository(),
          syncDao: db.pluralKitSyncDao,
          bus: capture.bus,
          secureStorage: const FlutterSecureStorage(),
          clientFactory: (_) => client,
        );
        await _connect(service);

        client.holdGetSystem = Completer<void>();
        final winner = service.syncRecentData();
        await _pumpUntil(() => client.getSystemEntered >= 1);

        final result = await service.importFromFileWithToken(
          _export(switches: 1),
        );
        expect(result.membersImported, 0);
        expect(result.frontingImported, isFalse);
        expect(result.canonicalizationSafe, isFalse);
        expect(await memberRepo.getAllMembers(), isEmpty);

        client.holdGetSystem!.complete();
        await winner;
      },
    );

    test(
      'importMembersOnly and performOneTimeFullImport throw while a pull is '
      'in flight',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _GatedClient();
        final service = _makeService(db: db, client: client, bus: capture.bus);
        await _connect(service);

        client.holdGetSystem = Completer<void>();
        final winner = service.syncRecentData();
        await _pumpUntil(() => client.getSystemEntered >= 1);

        await expectLater(
          service.importMembersOnly(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          service.performOneTimeFullImport(token: 'other-token'),
          throwsA(isA<StateError>()),
        );

        client.holdGetSystem!.complete();
        await winner;
      },
    );

    test('a failed pull releases the gate (no permanent lockout)', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _GatedClient();
      final service = _makeService(db: db, client: client, bus: capture.bus);
      await _connect(service);
      // Arm the failure AFTER setup — setToken also routes through getSystem.
      client.throwOnGetSystem = Exception('network down');

      await expectLater(service.syncRecentData(), throwsA(isA<Exception>()));
      expect(
        service.pullInFlightForTesting,
        isFalse,
        reason: 'the finally must release the gate on the error path',
      );

      // And the next pull genuinely runs (claims, reaches the client again).
      client.throwOnGetSystem = null;
      await service.syncRecentData();
      expect(service.state.lastSyncDate, isNotNull);
    });
  });

  group('M1 — manual cooldown enforced in-service', () {
    test(
      'second manual syncRecentData within 60s throws '
      'PkManualSyncCooldownException; auto sync is never cooled down',
      () async {
        final db = _makeDb();
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _GatedClient();
        final service = _makeService(db: db, client: client, bus: capture.bus);
        await _connect(service);

        await service.syncRecentData(isManual: true);
        expect(service.state.lastManualSyncDate, isNotNull);

        // Pre-fix this fired a full network round-trip on every tap — the
        // fronting screen's sync button checks nothing.
        await expectLater(
          service.syncRecentData(isManual: true),
          throwsA(
            isA<PkManualSyncCooldownException>().having(
              (e) => e.remaining,
              'remaining',
              greaterThan(Duration.zero),
            ),
          ),
        );

        // The cooldown rate-limits the USER, never the auto cadence.
        await service.syncRecentData(); // isManual: false — must not throw.

        // The rejected manual attempt must not have re-stamped the cooldown
        // or emitted any sync events of its own: exactly two started/completed
        // pairs (the manual winner + the auto run).
        expect(capture.events.whereType<PkSyncStarted>(), hasLength(2));
        expect(capture.events.whereType<PkSyncCompleted>(), hasLength(2));
      },
    );

    test('syncLiveFrontersOnly honors the same in-service cooldown', () async {
      final db = _makeDb();
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _GatedClient();
      final service = _makeService(db: db, client: client, bus: capture.bus);
      await _connect(service);

      await service.syncRecentData(isManual: true);

      await expectLater(
        service.syncLiveFrontersOnly(
          direction: PkSyncDirection.pullOnly,
          isManual: true,
        ),
        throwsA(isA<PkManualSyncCooldownException>()),
      );

      // Automatic live polls keep working.
      final auto = await service.syncLiveFrontersOnly(
        direction: PkSyncDirection.pullOnly,
      );
      expect(auto, isNotNull);
    });

    test('cooldown exception renders a user-facing wait message', () {
      expect(
        PkManualSyncCooldownException(
          const Duration(seconds: 42, milliseconds: 1),
        ).toString(),
        contains('43 more seconds'),
      );
      expect(
        PkManualSyncCooldownException(
          const Duration(milliseconds: 300),
        ).toString(),
        contains('1 more second'),
      );
    });
  });
}
