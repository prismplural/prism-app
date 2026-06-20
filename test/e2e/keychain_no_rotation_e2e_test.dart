// Fix B regression (end-to-end, real Rust FFI): `cacheRuntimeKeys` must NOT
// rotate the app database to the engine's local-storage key. The app DB keeps
// its own stable device-local key; binding it to the LSK (= HKDF(DEK,
// DeviceSecret), where DeviceSecret churns on revoke/re-pair) is what orphaned
// intact DBs on the next cold boot.
//
// This drives a real compiled engine so `local_storage_key` returns a genuine
// value that DIFFERS from the device-local app-DB key. Pre-fix, cacheRuntimeKeys
// read the device-local key from the slot, saw it differ from the LSK, and
// rotated prism.db TO the LSK — overwriting the primary slot. Post-fix it must
// leave the slot untouched.
//
// Build prereq: (cd ../prism-sync && cargo build --release -p prism_sync_ffi &&
// cargo build --release -p prism-sync-relay --example test_relay)

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final store = <String, String?>{};

  setUp(() {
    store.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map?;
          switch (call.method) {
            case 'write':
              store[args!['key'] as String] = args['value'] as String?;
              return null;
            case 'read':
              return store[args!['key'] as String];
            case 'delete':
              store.remove(args!['key'] as String);
              return null;
            case 'containsKey':
              return store.containsKey(args!['key']);
            case 'readAll':
              return <String, String>{
                for (final e in store.entries)
                  if (e.value != null) e.key: e.value!,
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'cacheRuntimeKeys does not rotate the app DB key to the engine '
    'local-storage key',
    skip: e2eSkip(),
    () async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
      final relay = await spawnRelay();
      // db is unused by the post-fix cacheRuntimeKeys; an in-memory executor is
      // enough to catch a reintroduced rotation (which would PRAGMA-rekey it and
      // write the primary slot).
      final db = AppDatabase(NativeDatabase.memory());
      E2EDevice? device;
      try {
        device = await createDevice(relay);

        // A device-local app-DB key that is NOT derived from the sync group.
        const deviceLocalKey = '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a'
            '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a';
        store[kDatabaseKeyStorageKey] = deviceLocalKey;

        // Precondition: the real engine LSK differs from the device-local key,
        // so the pre-fix code WOULD have rotated (and clobbered the slot).
        final lsk = Uint8List.fromList(
          await ffi.localStorageKey(handle: device.handle),
        );
        final lskHex = lsk
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(
          lskHex,
          isNot(deviceLocalKey),
          reason: 'precondition: engine LSK must differ from the app-DB key',
        );

        await cacheRuntimeKeys(device.handle, db);

        // Fix B: the primary app-DB slot is untouched — no rotation to the LSK.
        expect(
          store[kDatabaseKeyStorageKey],
          deviceLocalKey,
          reason: 'cacheRuntimeKeys must not rotate prism.db to the LSK',
        );
        // And no staging slot was written (rotation writes staging first).
        expect(
          store.containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse,
          reason: 'no rotation means no staging-slot write',
        );
      } finally {
        await db.close();
        device?.dispose();
        relay.stop();
        RustLib.dispose();
      }
    },
  );
}
