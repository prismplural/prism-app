import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/fake_repositories.dart';

/// Minimal secure-storage mock reused for the adoption tests. Provides a
/// stored PK token so `adoptSystemProfile` can build a client when avatar
/// adoption is requested.
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

/// Fake PK client that records calls. Only supports `getSystem()` and
/// `dispose()` — the entry points `importSystemAvatar` uses. Other methods
/// throw if exercised, which helps surface incidental usage in tests.
class _FakeClient implements PluralKitClient {
  _FakeClient(this.system);
  final PKSystem system;
  int getSystemCalls = 0;

  @override
  Future<PKSystem> getSystem() async {
    getSystemCalls++;
    return system;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected PK client call: '
    '${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageStub = _SecureStorageStub();
  setUp(storageStub.setup);
  tearDown(storageStub.teardown);

  PluralKitSyncService makeService({
    required AppDatabase db,
    required FakeSystemSettingsRepository settings,
    required _FakeClient client,
  }) {
    return PluralKitSyncService(
      memberRepository: FakeMemberRepository(),
      frontingSessionRepository: FakeFrontingSessionRepository(),
      syncDao: db.pluralKitSyncDao,
      settingsRepository: settings,
      secureStorage: const FlutterSecureStorage(),
      tokenOverride: 'test-token',
      clientFactory: (_) => client,
    );
  }

  group('PluralKitSyncService.adoptSystemProfile', () {
    test('writes name/description/tag without invoking client', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = FakeSystemSettingsRepository();
      const pk = PKSystem(
        id: 'sysid',
        name: 'The Example System',
        description: 'we are many',
        tag: ' | examples',
        avatarUrl: 'https://example.invalid/avatar.png',
      );
      final client = _FakeClient(pk);
      final service = makeService(db: db, settings: settings, client: client);

      await service.adoptSystemProfile(
        pk: pk,
        accepted: {
          PkProfileField.name,
          PkProfileField.description,
          PkProfileField.tag,
        },
      );

      expect(settings.settings.systemName, 'The Example System');
      expect(settings.settings.systemDescription, 'we are many');
      expect(settings.settings.systemTag, ' | examples');
      expect(settings.settings.systemAvatarData, isNull);
      // Avatar wasn't selected → no PK client call needed.
      expect(client.getSystemCalls, 0);
    });

    test(
      'avatar selection invokes importSystemAvatar (calls client)',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final settings = FakeSystemSettingsRepository();
        const pk = PKSystem(
          id: 'sysid',
          name: 'Ignored',
          avatarUrl: 'https://example.invalid/avatar.png',
        );
        final client = _FakeClient(pk);
        final service = makeService(db: db, settings: settings, client: client);

        await service.adoptSystemProfile(
          pk: pk,
          accepted: {PkProfileField.avatar},
        );

        // importSystemAvatar() builds a client and calls getSystem() before
        // fetching the avatar URL. The URL here points to an invalid host, so
        // fetchAvatarBytes returns null and no avatar is persisted — but the
        // fact that the client was invoked confirms the avatar path was taken.
        expect(client.getSystemCalls, 1);
        // Name must NOT have been written (not in accepted set).
        expect(settings.settings.systemName, isNull);
        // Avatar URL was unreachable, so no blob was written. That's fine — we
        // only assert the avatar path was entered, not that the network call
        // succeeded.
        expect(settings.settings.systemAvatarData, isNull);
      },
    );

    test('skips null/empty PK fields even when accepted', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = FakeSystemSettingsRepository();
      // Pre-seed a tag to verify it isn't wiped by an empty PK tag.
      settings.settings = settings.settings.copyWith(systemTag: 'existing-tag');
      const pk = PKSystem(id: 'sysid', name: 'Only Name');
      final client = _FakeClient(pk);
      final service = makeService(db: db, settings: settings, client: client);

      await service.adoptSystemProfile(
        pk: pk,
        accepted: {
          PkProfileField.name,
          PkProfileField.description,
          PkProfileField.tag,
        },
      );

      expect(settings.settings.systemName, 'Only Name');
      expect(settings.settings.systemDescription, isNull);
      // tag left untouched because PK value was null.
      expect(settings.settings.systemTag, 'existing-tag');
    });
  });

  group('PluralKitSyncService adoptSystemProfile integration (Drift)', () {
    test('empty settings → tag row updated after adopt', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = FakeSystemSettingsRepository();
      const pk = PKSystem(id: 'sysid', tag: '| newtag');
      final client = _FakeClient(pk);
      final service = makeService(db: db, settings: settings, client: client);

      // Initially blank.
      expect(settings.settings.systemTag, isNull);

      await service.adoptSystemProfile(pk: pk, accepted: {PkProfileField.tag});

      expect(settings.settings.systemTag, '| newtag');
      // NOTE: pending_ops observation deferred — the fake repo used here
      // doesn't thread through the CRDT sync-record plumbing. The plan
      // explicitly allows skipping the ops check when the plumbing is heavy.
    });
  });
}
