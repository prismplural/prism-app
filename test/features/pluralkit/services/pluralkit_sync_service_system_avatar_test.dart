import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/fake_repositories.dart';

// ---------------------------------------------------------------------------
// Secure storage stub — copied shape from the existing PK tests.
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
    _store['prism_pluralkit_token'] = 'test-token';
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
// Fake PluralKitClient — only methods touched by importSystemAvatar.
// ---------------------------------------------------------------------------

class _FakePKClient implements PluralKitClient {
  PKSystem system = const PKSystem(id: 'sys-1', name: 'Test');

  @override
  Future<PKSystem> getSystem() async => system;

  @override
  void dispose() {}

  // Catch-all so we don't have to stub 15+ unused methods.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'Unexpected call in _FakePKClient: ${invocation.memberName}',
      );
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

PluralKitSyncService _makeService({
  required _FakePKClient client,
  required AppDatabase db,
  FakeSystemSettingsRepository? settingsRepo,
}) {
  return PluralKitSyncService(
    memberRepository: FakeMemberRepository(),
    frontingSessionRepository: FakeFrontingSessionRepository(),
    syncDao: db.pluralKitSyncDao,
    settingsRepository: settingsRepo,
    secureStorage: const FlutterSecureStorage(),
    clientFactory: (_) => client,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();

  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  group('importSystemAvatar', () {
    test('null avatarUrl from PK system returns false', () async {
      final db = _makeDb();
      addTearDown(db.close);

      // `importSystemAvatar` uses the shared `fetchAvatarBytes` helper with
      // no injectable http.Client, so this file can't exercise the real
      // network without a local HTTP server. The happy-path + MIME/oversize
      // guarding is already covered by `avatar_fetcher_test.dart` and the SP
      // importer test; here we focus on the branching logic of
      // `importSystemAvatar` itself: null/empty URL, missing settings repo,
      // and the not-connected StateError path.
      final settingsRepo = FakeSystemSettingsRepository();
      final client = _FakePKClient()
        ..system = const PKSystem(id: 'sys-1', name: 'Test');

      final service = _makeService(
        client: client,
        db: db,
        settingsRepo: settingsRepo,
      );

      final result = await service.importSystemAvatar();

      expect(result, isFalse);
      expect(settingsRepo.settings.systemAvatarData, isNull);
    });

    test('empty avatarUrl returns false without touching settings repo',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final settingsRepo = FakeSystemSettingsRepository();
      final client = _FakePKClient()
        ..system = const PKSystem(id: 'sys-1', name: 'Test', avatarUrl: '');

      final service = _makeService(
        client: client,
        db: db,
        settingsRepo: settingsRepo,
      );

      final result = await service.importSystemAvatar();
      expect(result, isFalse);
      expect(settingsRepo.settings.systemAvatarData, isNull);
    });

    test('null settings repo returns false even with a valid avatarUrl',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final client = _FakePKClient()
        ..system = const PKSystem(
          id: 'sys-1',
          name: 'Test',
          avatarUrl: 'https://example.com/whatever.png',
        );

      final service = _makeService(client: client, db: db, settingsRepo: null);

      final result = await service.importSystemAvatar();
      expect(result, isFalse);
    });

    test('not-connected (no token) throws StateError', () async {
      // Override the stub: wipe the token so _buildClient returns null.
      storageStub.teardown();
      storageStub.setup();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );

      final db = _makeDb();
      addTearDown(db.close);

      final settingsRepo = FakeSystemSettingsRepository();
      final client = _FakePKClient();
      final service = _makeService(
        client: client,
        db: db,
        settingsRepo: settingsRepo,
      );

      await expectLater(
        service.importSystemAvatar,
        throwsA(isA<StateError>()),
      );
    });
  });
}

