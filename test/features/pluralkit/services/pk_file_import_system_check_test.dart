/// 2026-06 PK audit H8: system-identity check on file import.
///
/// `importFromFileWithToken` used to call `client.getSystem()` and DISCARD
/// the result, writing members/groups right after — so a wrong file plus a
/// valid token merged a foreign roster irreversibly (and the rows later
/// became push-eligible). `importFromFile` (no-token path) had no check at
/// all.
///
/// New contract, pinned here:
/// - token path: the export's system identity is compared against the
///   token's system BEFORE any write. UUID comparison is preferred when both
///   sides carry one (short ids become user-changeable with PK Premium);
///   short id is the fallback. Mismatch throws [PkFileSystemMismatchError]
///   with both names/ids — before a single member row is written.
/// - no-token path: if the app is LINKED (sync DAO has a systemId), the
///   export must match the linked system (short-id comparison — the DAO only
///   stores the short id). If not linked, any file is allowed.
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
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
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
// Fake PluralKitClient — configurable system identity, empty switch history.
// ---------------------------------------------------------------------------

class _FakePluralKitClient implements PluralKitClient {
  _FakePluralKitClient({required this.system});

  final PKSystem system;
  int getSystemCallCount = 0;

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKSystem> getSystem() async {
    getSystemCallCount++;
    return system;
  }

  @override
  Future<List<PKMember>> getMembers() async => const [];

  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async => const [];

  @override
  Future<PKSwitch> getSwitch(String switchRef) => throw UnimplementedError();

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

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
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _fileSystemUuid = 'aaaaaaaa-1111-2222-3333-444444444444';
const _otherSystemUuid = 'bbbbbbbb-5555-6666-7777-888888888888';

PkFileExport _makeExport({
  required PKSystem system,
  List<PKMember>? members,
}) {
  return PkFileExport(
    system: system,
    members:
        members ??
        const [
          PKMember(
            id: 'memaa',
            uuid: 'cccccccc-0000-0000-0000-000000000001',
            name: 'File Member',
          ),
        ],
    groups: const [],
    switches: const [],
  );
}

({
  AppDatabase db,
  PluralKitSyncService service,
  _FakePluralKitClient client,
})
_makeHarness({required PKSystem tokenSystem}) {
  final db = AppDatabase(NativeDatabase.memory());
  final client = _FakePluralKitClient(system: tokenSystem);
  final service = PluralKitSyncService(
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    secureStorage: const FlutterSecureStorage(),
    tokenOverride: 'test-token',
    clientFactory: (_) => client,
  );
  return (db: db, service: service, client: client);
}

Future<int> _memberRowCount(AppDatabase db) async =>
    (await db.select(db.members).get()).length;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('H8: importFromFileWithToken system check', () {
    test('mismatched system throws BEFORE any member write', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'tokaa',
          uuid: _otherSystemUuid,
          name: 'Token System',
        ),
      );
      addTearDown(h.db.close);

      final export = _makeExport(
        system: const PKSystem(
          id: 'filaa',
          uuid: _fileSystemUuid,
          name: 'File System',
        ),
      );

      await expectLater(
        h.service.importFromFileWithToken(export, token: 'test-token'),
        throwsA(isA<PkFileSystemMismatchError>()),
      );

      expect(
        await _memberRowCount(h.db),
        0,
        reason:
            'H8: the identity check must run before _importMembers — a '
            'foreign roster must never be merged',
      );
      expect(h.client.getSystemCallCount, 1,
          reason: 'the token system WAS fetched (and compared, not discarded)');
      expect(h.service.state.isSyncing, isFalse,
          reason: 'error path must clear the isSyncing claim');
      expect(h.service.state.syncError, contains('different PluralKit system'));
    });

    test('mismatch error message names both systems', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'tokaa',
          uuid: _otherSystemUuid,
          name: 'Token System',
        ),
      );
      addTearDown(h.db.close);

      final export = _makeExport(
        system: const PKSystem(
          id: 'filaa',
          uuid: _fileSystemUuid,
          name: 'File System',
        ),
      );

      Object? thrown;
      try {
        await h.service.importFromFileWithToken(export, token: 'test-token');
      } catch (e) {
        thrown = e;
      }
      // The provider renders errors as 'Import failed: $e' — the toString
      // must therefore be human-readable and identify both sides.
      final message = thrown.toString();
      expect(message, contains('File System'));
      expect(message, contains('Token System'));
      expect(message, contains(_fileSystemUuid));
      expect(message, contains(_otherSystemUuid));
    });

    test('matching system (by uuid) proceeds and imports members', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'tokaa',
          uuid: _fileSystemUuid,
          name: 'Same System',
        ),
      );
      addTearDown(h.db.close);

      final export = _makeExport(
        system: const PKSystem(
          id: 'tokaa',
          uuid: _fileSystemUuid,
          name: 'Same System',
        ),
      );

      final result = await h.service.importFromFileWithToken(
        export,
        token: 'test-token',
      );

      expect(result.membersImported, 1);
      expect(await _memberRowCount(h.db), 1);
    });

    test(
        'uuid match wins over divergent short ids (PK Premium short-id '
        'change)', () async {
      // PK Premium makes short ids user-changeable: an old export can carry
      // a short id that no longer matches the live system. The uuid is the
      // stable key, so when BOTH sides carry one it decides.
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'newid',
          uuid: _fileSystemUuid,
          name: 'Renamed System',
        ),
      );
      addTearDown(h.db.close);

      final export = _makeExport(
        system: const PKSystem(
          id: 'oldid',
          uuid: _fileSystemUuid,
          name: 'Old Export Name',
        ),
      );

      final result = await h.service.importFromFileWithToken(
        export,
        token: 'test-token',
      );

      expect(result.membersImported, 1);
      expect(await _memberRowCount(h.db), 1);
    });

    test('matching short id but DIFFERENT uuid is a mismatch', () async {
      // The dual of the test above: a recycled/changed short id must not let
      // a foreign system through when the uuids disagree.
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'sysaa',
          uuid: _otherSystemUuid,
          name: 'Stranger',
        ),
      );
      addTearDown(h.db.close);

      final export = _makeExport(
        system: const PKSystem(
          id: 'sysaa',
          uuid: _fileSystemUuid,
          name: 'Mine',
        ),
      );

      await expectLater(
        h.service.importFromFileWithToken(export, token: 'test-token'),
        throwsA(isA<PkFileSystemMismatchError>()),
      );
      expect(await _memberRowCount(h.db), 0);
    });

    test('short-id fallback applies when the export lacks a uuid', () async {
      // Legacy/partial export root without a uuid: fall back to short id.
      // Same short id → allowed; different short id → blocked.
      final h = _makeHarness(
        tokenSystem: const PKSystem(
          id: 'sysaa',
          uuid: _otherSystemUuid,
          name: 'Token System',
        ),
      );
      addTearDown(h.db.close);

      final matching = _makeExport(
        system: const PKSystem(id: 'sysaa', name: 'No-uuid Export'),
      );
      final result = await h.service.importFromFileWithToken(
        matching,
        token: 'test-token',
      );
      expect(result.membersImported, 1);

      final foreign = _makeExport(
        system: const PKSystem(id: 'syszz', name: 'Foreign Export'),
      );
      await expectLater(
        h.service.importFromFileWithToken(foreign, token: 'test-token'),
        throwsA(isA<PkFileSystemMismatchError>()),
      );
    });
  });

  group('H8: importFromFile (no token) linked-system check', () {
    test('unlinked app allows any file', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(id: 'unusd', name: 'Unused'),
      );
      addTearDown(h.db.close);
      // No sync-state seeding: getSyncState() returns the default row with
      // systemId == null — the app is not linked.

      final export = _makeExport(
        system: const PKSystem(
          id: 'anyid',
          uuid: _fileSystemUuid,
          name: 'Anyone',
        ),
      );

      final result = await h.service.importFromFile(export);

      expect(result.membersImported, 1);
      expect(await _memberRowCount(h.db), 1);
    });

    test('linked app rejects a foreign file before any write', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(id: 'unusd', name: 'Unused'),
      );
      addTearDown(h.db.close);

      // Link the app to sys 'linkd' (only the short id is persisted — that
      // is all setToken stores).
      await h.db.pluralKitSyncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          systemId: Value('linkd'),
          isConnected: Value(true),
        ),
      );

      final export = _makeExport(
        system: const PKSystem(
          id: 'forgn',
          uuid: _fileSystemUuid,
          name: 'Foreign System',
        ),
      );

      await expectLater(
        h.service.importFromFile(export),
        throwsA(isA<PkFileSystemMismatchError>()),
      );
      expect(await _memberRowCount(h.db), 0,
          reason: 'H8: the check must precede _importMembers');
      expect(h.service.state.isSyncing, isFalse,
          reason: 'the isSyncing claim is released before the throw');
    });

    test('linked app accepts a file from the linked system', () async {
      final h = _makeHarness(
        tokenSystem: const PKSystem(id: 'unusd', name: 'Unused'),
      );
      addTearDown(h.db.close);

      await h.db.pluralKitSyncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          systemId: Value('linkd'),
          isConnected: Value(true),
        ),
      );

      final export = _makeExport(
        system: const PKSystem(
          id: 'linkd',
          uuid: _fileSystemUuid,
          name: 'My System',
        ),
      );

      final result = await h.service.importFromFile(export);

      expect(result.membersImported, 1);
      expect(await _memberRowCount(h.db), 1);
    });
  });
}
