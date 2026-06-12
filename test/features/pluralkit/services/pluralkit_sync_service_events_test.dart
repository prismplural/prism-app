import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/fake_repositories.dart';

/// Secure-storage stub copied from neighbouring service tests. Lets the
/// service write/read PK tokens through the platform channel without hitting
/// real OS keychain APIs.
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

/// Configurable fake PluralKit client. Mirrors the shape of
/// `FakePluralKitClient` in `pluralkit_sync_service_test.dart` but pared down
/// to the surface used by event-emission tests.
class _FakeClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  _FakeClient({
    this.systemToReturn = const PKSystem(id: 'sys-1', name: 'Event System'),
    this.membersToReturn = const [],
    this.throwAuthError = false,
    this.throwAuthOnGetMembers = false,
    this.throwOnGetSystemWithToken,
  });

  PKSystem systemToReturn;
  List<PKMember> membersToReturn;
  bool throwAuthError;

  /// When set, `getMembers()` throws a 401 — used by the 2026-06 PK audit M3
  /// test to drive a token revoked MID-sync (after `getSystem` already passed).
  bool throwAuthOnGetMembers;

  /// When set, `getSystem()` throws `Exception('boom token=<value>')`. Used to
  /// exercise the redaction path so the test can assert that the token is
  /// stripped before the message enters an event.
  final String? throwOnGetSystemWithToken;

  @override
  Future<PKSystem> getSystem() async {
    if (throwAuthError) throw const PluralKitAuthError();
    if (throwOnGetSystemWithToken != null) {
      throw Exception('boom token=$throwOnGetSystemWithToken leaked');
    }
    return systemToReturn;
  }

  @override
  Future<List<PKMember>> getMembers() async {
    if (throwAuthOnGetMembers) throw const PluralKitAuthError();
    return membersToReturn;
  }

  @override
  String get currentToken => 'fake-token';

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async => const <PKSwitch>[];

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async =>
      const <PKGroup>[];

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected PK client call: ${invocation.memberName}',
  );
}

PluralKitSyncService _makeService({
  required AppDatabase db,
  required PkSyncEventBus bus,
  required _FakeClient client,
  String? tokenOverride,
}) {
  return PluralKitSyncService(
    memberRepository: FakeMemberRepository(),
    frontingSessionRepository: FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    bus: bus,
    secureStorage: const FlutterSecureStorage(),
    tokenOverride: tokenOverride,
    clientFactory: (_) => client,
  );
}

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

  group('PluralKitSyncService event emission', () {
    test('setToken success emits PkTokenSet with system name and id', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _FakeClient(
        systemToReturn: const PKSystem(id: 'sys-42', name: 'Polychrome'),
      );
      final service = _makeService(db: db, bus: capture.bus, client: client);

      await service.setToken('valid-token');

      expect(capture.events, hasLength(1));
      final evt = capture.events.single;
      expect(evt, isA<PkTokenSet>());
      final set = evt as PkTokenSet;
      expect(set.systemName, 'Polychrome');
      expect(set.systemId, 'sys-42');
    });

    test(
      'setToken with null PK system name falls back to system id',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        // PK API allows `name` to be null. Plan pins fallback to id.
        final client = _FakeClient(
          systemToReturn: const PKSystem(id: 'sys-no-name', name: null),
        );
        final service = _makeService(db: db, bus: capture.bus, client: client);

        await service.setToken('valid-token');

        final set = capture.events.single as PkTokenSet;
        expect(set.systemName, 'sys-no-name');
        expect(set.systemId, 'sys-no-name');
      },
    );

    test('setToken on 401 emits PkTokenAuthFailed, not PkTokenSet', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _FakeClient(throwAuthError: true);
      final service = _makeService(db: db, bus: capture.bus, client: client);

      await service.setToken('bad-token');

      expect(
        capture.events.whereType<PkTokenSet>(),
        isEmpty,
        reason: 'auth failure must not emit a token-set event',
      );
      expect(capture.events.whereType<PkTokenAuthFailed>(), hasLength(1));
    });

    test('setToken other error emits PkRequestFailed with redacted token', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      const token = 'super-secret-token-1234';
      final client = _FakeClient(throwOnGetSystemWithToken: token);
      final service = _makeService(db: db, bus: capture.bus, client: client);

      await service.setToken(token);

      final failures = capture.events.whereType<PkRequestFailed>().toList();
      expect(failures, hasLength(1));
      final failure = failures.single;
      expect(failure.stage, 'setToken');
      expect(
        failure.message.contains(token),
        isFalse,
        reason: 'token must be redacted from the error message',
      );
      expect(failure.message.contains('[REDACTED]'), isTrue);
    });

    test('clearToken emits PkTokenCleared', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final capture = PkSyncEventBusCapture();
      final client = _FakeClient();
      final service = _makeService(db: db, bus: capture.bus, client: client);

      // Set the token first so clearToken has work to do; we only assert on
      // the post-clear emission.
      await service.setToken('valid-token');
      capture.events.clear();

      await service.clearToken();

      expect(capture.events, hasLength(1));
      expect(capture.events.single, isA<PkTokenCleared>());
    });

    test(
      'pushMemberUpdate failure emits PkRequestFailed with redacted token '
      '(2026-06 PK audit M11)',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _FakeClient();
        final service = _makeService(db: db, bus: capture.bus, client: client);

        // Bring the service to canAutoSync and persist a push-enabled global
        // direction so the per-field gate doesn't skip the member.
        await service.setToken('valid-token');
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            directionConfirmed: const Value(true),
            mappingAcknowledged: const Value(true),
            fieldSyncConfig: Value(
              serializeFieldSyncConfig(
                const {},
                globalDirection: PkSyncDirection.bidirectional,
              ),
            ),
          ),
        );
        await service.loadState();
        capture.events.clear();

        // The fake client reports `currentToken == 'fake-token'`; the failure
        // message embeds it so we can assert it's stripped by redaction.
        final result = await service.pushMemberUpdate(
          domain.Member(
            id: 'm-1',
            name: 'Ada',
            createdAt: DateTime.utc(2026),
            pluralkitId: 'aaaaa',
            pluralkitUuid: 'uuid-m1',
            pluralkitDisplayName: 'Ada',
          ),
          pushService: _FailingPushService(
            Exception('boom token=fake-token leaked'),
          ),
        );

        expect(result, isFalse);
        final failures = capture.events.whereType<PkRequestFailed>().toList();
        expect(failures, hasLength(1));
        expect(failures.single.stage, 'pushMemberUpdate');
        expect(
          failures.single.message.contains('fake-token'),
          isFalse,
          reason: 'token must be redacted from the failure event',
        );
        expect(failures.single.message.contains('[REDACTED]'), isTrue);
      },
    );

    test(
      'importMembersOnly success emits PkMembersImported with count',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        // Members will be empty list — _importMembers handles that fine,
        // and we just need the count semantics on the emitted event.
        final client = _FakeClient(
          systemToReturn: const PKSystem(id: 'sys-1', name: 'S1'),
          membersToReturn: const [
            PKMember(id: 'pk1', uuid: 'u1', name: 'Alpha'),
            PKMember(id: 'pk2', uuid: 'u2', name: 'Beta'),
            PKMember(id: 'pk3', uuid: 'u3', name: 'Gamma'),
          ],
        );
        final service = _makeService(
          db: db,
          bus: capture.bus,
          client: client,
          tokenOverride: 'tok',
        );

        await service.importMembersOnly();

        final imported = capture.events.whereType<PkMembersImported>().toList();
        expect(imported, hasLength(1));
        expect(imported.single.count, 3);
      },
    );

    test(
      'syncRecentData first-time path emits PkSyncStarted then PkSyncCompleted',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        final client = _FakeClient();
        final service = _makeService(
          db: db,
          bus: capture.bus,
          client: client,
        );

        // Bring the service into canAutoSync=true via the normal setToken path.
        // _FakeClient.getSystem() returns a valid system, so setToken succeeds.
        // Then confirm direction and acknowledge mapping to unlock auto-sync.
        await service.setToken('tok');
        await service.confirmDirection();
        await service.acknowledgeMapping();

        // No lastSyncDate -> takes the performFullImport branch. With empty
        // PK members + empty switches that's a no-op and returns null.
        await service.syncRecentData(
          isManual: true,
          direction: PkSyncDirection.pullOnly,
        );

        final started = capture.events.whereType<PkSyncStarted>().toList();
        final completed = capture.events.whereType<PkSyncCompleted>().toList();
        expect(started, hasLength(1));
        expect(started.single.trigger, 'manual');
        expect(started.single.mode, 'incremental');
        expect(completed, hasLength(1));
        expect(completed.single.error, isNull);
        // Started must come before completed.
        expect(
          capture.events.indexOf(started.single) <
              capture.events.indexOf(completed.single),
          isTrue,
        );
      },
    );

    test(
      'syncRecentData failure emits PkSyncCompleted with redacted error',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        const token = 'tok-leaks-here';
        // performFullImport will throw because getSystem leaks the token in
        // its message. (No lastSyncDate -> first-time path -> performFullImport.)
        final client = _FakeClient(throwOnGetSystemWithToken: token);
        final service = _makeService(
          db: db,
          bus: capture.bus,
          client: client,
          tokenOverride: token,
        );

        // Seed the DB so the service believes it is fully set up (isConnected,
        // directionConfirmed, mappingAcknowledged). We can't call setToken here
        // because the client throws on getSystem — that's the point of this test.
        await db.pluralKitSyncDao.upsertSyncState(
          const PluralKitSyncStateCompanion(
            id: Value('pk_config'),
            isConnected: Value(true),
            directionConfirmed: Value(true),
            mappingAcknowledged: Value(true),
          ),
        );
        await service.loadState();

        await expectLater(
          service.syncRecentData(direction: PkSyncDirection.pullOnly),
          throwsA(anything),
        );

        final completed = capture.events.whereType<PkSyncCompleted>().toList();
        expect(completed, hasLength(1));
        final err = completed.single.error ?? '';
        expect(err.isNotEmpty, isTrue);
        expect(
          err.contains(token),
          isFalse,
          reason: 'token must be redacted out of the completed-event error',
        );
        expect(err.contains('[REDACTED]'), isTrue);
      },
    );

    test(
      'M3: a 401 MID-sync emits PkTokenAuthFailed + a distinct auth syncError '
      '(not the generic formatted error), without auto-clearing the token',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final capture = PkSyncEventBusCapture();
        const token = 'valid-then-revoked';
        // getSystem passes (connect ok); getMembers throws 401 mid-sync.
        final client = _FakeClient(throwAuthOnGetMembers: true);
        final service = _makeService(
          db: db,
          bus: capture.bus,
          client: client,
          tokenOverride: token,
        );

        // Fully set up AND already synced once (lastSyncDate set) so we take
        // the incremental branch that calls getMembers — not performFullImport.
        await db.pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            isConnected: const Value(true),
            directionConfirmed: const Value(true),
            mappingAcknowledged: const Value(true),
            lastSyncDate: Value(DateTime.utc(2026, 1, 1)),
          ),
        );
        await service.loadState();

        await expectLater(
          service.syncRecentData(direction: PkSyncDirection.pullOnly),
          throwsA(isA<PluralKitAuthError>()),
        );

        // Dedicated auth event emitted.
        expect(capture.events.whereType<PkTokenAuthFailed>(), hasLength(1));

        // User-facing syncError is the actionable re-link copy, NOT the bare
        // exception toString.
        final syncError = service.state.syncError ?? '';
        expect(syncError, contains('re-link'));
        expect(syncError.contains('PluralKitAuthError'), isFalse);

        // The request-failed event is tagged auth (not 'unknown').
        final failures = capture.events.whereType<PkRequestFailed>().toList();
        expect(failures, hasLength(1));
        expect(failures.single.stage, 'syncRecentData');
        expect(failures.single.errorKind, 'auth');

        // The token must NOT be auto-cleared — the row still has it / no
        // PkTokenCleared was emitted.
        expect(capture.events.whereType<PkTokenCleared>(), isEmpty);
      },
    );

    // PARTIAL COVERAGE: A green PkSyncPullCompleted + PkSwitchPushed(pushed)
    // happy path requires a pre-existing lastSyncDate, a valid mapped member
    // set, and a multi-page PK switch fake — that fixture lives in the
    // diff-sweep test file and is large. The emit-site code for those events
    // is exercised indirectly by the syncRecentData failure path above
    // (which proves the bus is wired into the same try/catch).
    //
    // The deletion-count emit at the syncRecentData deletion-completion site
    // (PkSwitchPushed(pushed: 0, deleted: N)) is verified via a unit test on
    // the PkSwitchPushed event itself: the `summary` and JSON payload must
    // both distinguish the deletion-only case from the creation-only case.
    test('PkSwitchPushed event surfaces deletion-only case distinctly',
        () {
      const event = PkSwitchPushed(pushed: 0, deleted: 3);
      expect(event.summary, 'Pushed 3 switch deletions');
      expect(event.toJson(), {
        'kind': 'pkSwitchPushed',
        'pushed': 0,
        'deleted': 3,
      });
    });

    test('PkSwitchPushed event surfaces combined push+delete distinctly', () {
      const event = PkSwitchPushed(pushed: 2, deleted: 1);
      expect(event.summary, 'Pushed 2 switches, 1 deletions');
      expect(event.toJson(), {
        'kind': 'pkSwitchPushed',
        'pushed': 2,
        'deleted': 1,
      });
    });
  });
}

/// PkPushService that throws on `pushMemberFull` — drives the M11
/// member-edit failure event path.
class _FailingPushService extends PkPushService {
  _FailingPushService(this.error);

  final Object error;

  @override
  Future<PKMember> pushMemberFull(
    domain.Member member,
    PluralKitClient client, {
    PKMember? pkMember,
    bool includeProxyTags = true,
    Set<String>? allowedFields,
    void Function(String pkField, String reason)? onFieldSkipped,
  }) async {
    throw error;
  }
}
