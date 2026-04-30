import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';

void _installSecureStorageStub() {
  final store = <String, String?>{};
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pkSyncDirectionNotifier.setDirection includes every member field',
    () async {
      _installSecureStorageStub();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = PluralKitSyncDao(db);

      final container = ProviderContainer(
        overrides: [pluralKitSyncDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      // Trigger build (which async-loads existing state), then wait for the
      // load to finish by hitting the DAO ourselves first. getSyncState
      // inserts the default row, so calling it up front dodges the race
      // between build's `_loadDirection` and our `setDirection` both trying
      // to insert the seed row concurrently.
      await dao.getSyncState();
      container.read(pkSyncDirectionProvider);

      await container
          .read(pkSyncDirectionProvider.notifier)
          .setDirection(PkSyncDirection.pushOnly);

      final row = await dao.getSyncState();
      final config = parseFieldSyncConfig(row.fieldSyncConfig);
      final global = config['__global__'];
      expect(
        global,
        isNotNull,
        reason: 'setDirection must persist a __global__ config entry',
      );

      // Every field — including displayName and birthday — must reflect the
      // user's chosen direction. Before the fix both silently fell back to
      // `bidirectional`.
      expect(global!.name, PkSyncDirection.pushOnly);
      expect(global.displayName, PkSyncDirection.pushOnly);
      expect(global.pronouns, PkSyncDirection.pushOnly);
      expect(global.description, PkSyncDirection.pushOnly);
      expect(global.color, PkSyncDirection.pushOnly);
      expect(global.birthday, PkSyncDirection.pushOnly);
      expect(global.proxyTags, PkSyncDirection.pushOnly);
    },
  );
}
