// Property tests for the guarded DB-key writers (§11.6 acceptance criterion):
//
//   "No DB-key writer can write a value different from `verifiedStartupKey`
//    while repair pending."
//
// We generate large numbers of random 64-char lowercase hex inputs and feed
// each writer to verify the invariant holds. The codebase does not pull in
// `glados`/`fast_check` so we run loops with `Random.secure()` ourselves.
//
// All tests share the same `_SecureStorageStub` used in the existing
// encryption tests so the stubbed `flutter_secure_storage` platform channel
// behaviour matches what the rest of the suite already verifies.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';

// Number of random inputs per property. 100+ is the §11.6 floor; we run a
// bit more for the "always rejected" cases where each pass is cheap.
const int _kPropertyIterations = 200;

class _SecureStorageStub {
  final Map<String, String?> store = <String, String?>{};
  int writeCalls = 0;
  int deleteCalls = 0;

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        switch (call.method) {
          case 'write':
            writeCalls += 1;
            store[call.arguments['key'] as String] =
                call.arguments['value'] as String?;
            return null;
          case 'read':
            return store[call.arguments['key'] as String];
          case 'delete':
            deleteCalls += 1;
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
    writeCalls = 0;
    deleteCalls = 0;
  }
}

/// Generate a random 64-char lowercase hex string (32 bytes) using
/// [Random.secure].
String _randomHex(Random rng) {
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  late _SecureStorageStub storageStub;
  late Random rng;

  setUp(() {
    storageStub = _SecureStorageStub()..setup();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    rng = Random.secure();
  });

  tearDown(() => storageStub.teardown());

  // -------------------------------------------------------------------------
  // Property 1: divergent primary-slot writes during repair-pending are
  // ALWAYS rejected, regardless of the random input.
  // -------------------------------------------------------------------------

  group('property: divergent writes always blocked while repair pending', () {
    test(
      'writeDatabaseKeyHex refuses every divergent random hex',
      () async {
        final verified = '01' * 32; // pinned verified key
        await setKeychainRepairPending(true);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final candidate = _randomHex(rng);
          if (candidate == verified) continue; // skip the equality edge

          await expectLater(
            () => writeDatabaseKeyHex(
              candidate,
              verifiedStartupKey: verified,
            ),
            throwsStateError,
            reason: 'iteration $i with candidate=$candidate',
          );
        }

        // Invariant: NOTHING was written to the primary slot.
        expect(
          storageStub.store.containsKey(kDatabaseKeyStorageKey),
          isFalse,
          reason: 'guard must refuse every divergent write — storage stayed empty',
        );
        expect(storageStub.writeCalls, equals(0));
      },
    );

    test(
      'writeSyncDatabaseKeyHex refuses every divergent random hex',
      () async {
        final verified = '02' * 32;
        await setKeychainRepairPending(true);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final candidate = _randomHex(rng);
          if (candidate == verified) continue;

          await expectLater(
            () => writeSyncDatabaseKeyHex(
              candidate,
              verifiedStartupKey: verified,
            ),
            throwsStateError,
            reason: 'iteration $i with candidate=$candidate',
          );
        }

        expect(
          storageStub.store.containsKey(kSyncDatabaseKeyStorageKey),
          isFalse,
        );
        expect(storageStub.writeCalls, equals(0));
      },
    );

    test(
      'null verifiedStartupKey during repair-pending — every random hex refused',
      () async {
        await setKeychainRepairPending(true);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final candidate = _randomHex(rng);
          await expectLater(
            () => writeDatabaseKeyHex(candidate),
            throwsStateError,
            reason: 'no verifiedStartupKey → must always refuse — iter $i',
          );
          await expectLater(
            () => writeSyncDatabaseKeyHex(candidate),
            throwsStateError,
          );
        }

        expect(storageStub.writeCalls, equals(0));
        expect(
          storageStub.store.containsKey(kDatabaseKeyStorageKey),
          isFalse,
        );
        expect(
          storageStub.store.containsKey(kSyncDatabaseKeyStorageKey),
          isFalse,
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 2: matching-key writes (hex == verifiedStartupKey) ALWAYS succeed
  // during repair-pending. This is the self-heal contract.
  // -------------------------------------------------------------------------

  group('property: matching writes always allowed while repair pending', () {
    test(
      'writeDatabaseKeyHex accepts every input where hex == verifiedStartupKey',
      () async {
        await setKeychainRepairPending(true);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          final result = await writeDatabaseKeyHex(
            hex,
            verifiedStartupKey: hex,
          );
          expect(result.ok, isTrue, reason: 'iter $i, hex=$hex');
          expect(
            storageStub.store[kDatabaseKeyStorageKey],
            equals(hex),
            reason: 'iter $i should have written the matching key through',
          );
        }
      },
    );

    test(
      'writeSyncDatabaseKeyHex accepts every input where hex == verifiedStartupKey',
      () async {
        await setKeychainRepairPending(true);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          final result = await writeSyncDatabaseKeyHex(
            hex,
            verifiedStartupKey: hex,
          );
          expect(result.ok, isTrue);
          expect(storageStub.store[kSyncDatabaseKeyStorageKey], equals(hex));
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 3: staging writers are blocked ENTIRELY while repair pending,
  // regardless of the input value. (There is no "matching" path for staging
  // — we never trust the keystore enough to rotate during repair.)
  // -------------------------------------------------------------------------

  group('property: staging writes always blocked while repair pending', () {
    test(
      'writeStagingDatabaseKeyHex refuses every random hex',
      () async {
        await setKeychainRepairPending(true);
        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          await expectLater(
            () => writeStagingDatabaseKeyHex(hex),
            throwsStateError,
            reason: 'iter $i, hex=$hex',
          );
        }
        expect(
          storageStub.store
              .containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse,
        );
        expect(storageStub.writeCalls, equals(0));
      },
    );

    test(
      'writeStagingSyncDatabaseKeyHex refuses every random hex',
      () async {
        await setKeychainRepairPending(true);
        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          await expectLater(
            () => writeStagingSyncDatabaseKeyHex(hex),
            throwsStateError,
          );
        }
        expect(
          storageStub.store
              .containsKey('${kSyncDatabaseKeyStorageKey}_staging'),
          isFalse,
        );
        expect(storageStub.writeCalls, equals(0));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 4: when the flag is FALSE, every writer passes through any
  // valid input. (Sanity check that the guard isn't over-broad.)
  // -------------------------------------------------------------------------

  group('property: writes pass through when flag is false', () {
    test(
      'writeDatabaseKeyHex / writeSyncDatabaseKeyHex always succeed when flag is false',
      () async {
        // Flag is explicitly false (default state after setMockInitialValues({})).
        expect(await isKeychainRepairPending(), isFalse);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          final r1 = await writeDatabaseKeyHex(hex);
          expect(r1.ok, isTrue, reason: 'iter $i primary');
          expect(storageStub.store[kDatabaseKeyStorageKey], equals(hex));

          final r2 = await writeSyncDatabaseKeyHex(hex);
          expect(r2.ok, isTrue, reason: 'iter $i sync');
          expect(storageStub.store[kSyncDatabaseKeyStorageKey], equals(hex));
        }
      },
    );

    test(
      'writeStagingDatabaseKeyHex / writeStagingSyncDatabaseKeyHex always '
      'succeed when flag is false',
      () async {
        expect(await isKeychainRepairPending(), isFalse);

        for (var i = 0; i < _kPropertyIterations; i++) {
          final hex = _randomHex(rng);
          final r1 = await writeStagingDatabaseKeyHex(hex);
          expect(r1.ok, isTrue);
          expect(
            storageStub.store['${kDatabaseKeyStorageKey}_staging'],
            equals(hex),
          );

          final r2 = await writeStagingSyncDatabaseKeyHex(hex);
          expect(r2.ok, isTrue);
          expect(
            storageStub.store['${kSyncDatabaseKeyStorageKey}_staging'],
            equals(hex),
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 5: the storage value is NEVER mutated to a divergent input
  // across many sequential divergent-write attempts. Strengthens Property 1
  // by seeding the slot first and then running attempts.
  // -------------------------------------------------------------------------

  test('seeded slot is not mutated by any divergent write attempt', () async {
    final verified = '03' * 32;
    final seed = '04' * 32;
    storageStub.store[kDatabaseKeyStorageKey] = seed;
    storageStub.store[kSyncDatabaseKeyStorageKey] = seed;
    await setKeychainRepairPending(true);

    for (var i = 0; i < _kPropertyIterations; i++) {
      final candidate = _randomHex(rng);
      if (candidate == verified) continue;
      try {
        await writeDatabaseKeyHex(candidate, verifiedStartupKey: verified);
        fail('should have thrown for divergent primary write at iter $i');
      } on StateError {
        // expected
      }
      try {
        await writeSyncDatabaseKeyHex(
          candidate,
          verifiedStartupKey: verified,
        );
        fail('should have thrown for divergent sync write at iter $i');
      } on StateError {
        // expected
      }
    }

    // The seeded value must still be in the slot, unchanged.
    expect(storageStub.store[kDatabaseKeyStorageKey], equals(seed));
    expect(storageStub.store[kSyncDatabaseKeyStorageKey], equals(seed));
    expect(
      storageStub.writeCalls,
      equals(0),
      reason:
          'guards must short-circuit before any platform-channel write call',
    );
  });
}
