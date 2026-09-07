import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the production secure-storage path while replacing the platform keychain.
class _FakeKeychain {
  final Map<String, String> store = <String, String>{};
  PlatformException? throwOnRead;
  PlatformException? throwOnWrite;

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                if (throwOnWrite != null) throw throwOnWrite!;
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                if (value == null) {
                  store.remove(key);
                } else {
                  store[key] = value;
                }
                return null;
              case 'read':
                if (throwOnRead != null) throw throwOnRead!;
                return store[call.arguments['key'] as String];
              case 'readAll':
                return Map<String, String>.from(store);
              case 'delete':
                store.remove(call.arguments['key'] as String);
                return null;
              case 'deleteAll':
                store.clear();
                return null;
              case 'containsKey':
                return store.containsKey(call.arguments['key'] as String);
              default:
                return null;
            }
          },
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    store.clear();
  }
}

void main() {
  late PinLockService service;

  setUp(() {
    service = PinLockService();
  });

  // ── hashPin (SHA-256, legacy) ───────────────────────────────────────────

  group('hashPin', () {
    test('produces deterministic output for same inputs', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('1234', 'salt-abc');
      expect(hash1, equals(hash2));
    });

    test('produces different output for different PINs', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('5678', 'salt-abc');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces different output for different salts', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('1234', 'salt-xyz');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces a SHA-256 sized output (32 bytes)', () {
      final hash = service.hashPin('0000', 'any-salt');
      expect(hash.length, 32);
    });
  });

  // ── hashPinArgon2id ─────────────────────────────────────────────────────

  group('hashPinArgon2id', () {
    test('produces deterministic output for same inputs', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      expect(hash1, equals(hash2));
    });

    test('produces different output for different PINs', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('5678', 'salt-abc');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces different output for different salts', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('1234', 'salt-xyz');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces a 32-byte output', () {
      final hash = PinLockService.hashPinArgon2id('0000', 'any-salt');
      expect(hash.length, 32);
    });
  });

  group('hashPinArgon2idBytes', () {
    test('matches String API for UTF-8 encoded PIN bytes', () {
      const pin = '123456';
      const salt = 'salt-abc';
      final pinBytes = Uint8List.fromList(utf8.encode(pin));
      addTearDown(() => pinBytes.fillRange(0, pinBytes.length, 0));

      final stringHash = PinLockService.hashPinArgon2id(pin, salt);
      final bytesHash = PinLockService.hashPinArgon2idBytes(pinBytes, salt);

      expect(bytesHash, equals(stringHash));
    });

    test('does not mutate caller-owned PIN bytes', () {
      final pinBytes = Uint8List.fromList(utf8.encode('654321'));
      addTearDown(() => pinBytes.fillRange(0, pinBytes.length, 0));
      final original = List<int>.from(pinBytes);

      PinLockService.hashPinArgon2idBytes(pinBytes, 'salt-abc');

      expect(pinBytes, equals(original));
    });
  });

  // ── verifyPin ─────────────────────────────────────────────────────────────

  group('verifyPin', () {
    test('returns true for correct PIN', () {
      const pin = '9999';
      const salt = 'my-salt';
      final hash = service.hashPin(pin, salt);
      expect(service.verifyPin(pin, hash, salt), isTrue);
    });

    test('returns false for wrong PIN', () {
      const salt = 'my-salt';
      final hash = service.hashPin('1111', salt);
      expect(service.verifyPin('2222', hash, salt), isFalse);
    });

    test('rejects wrong hash (constant-time equals)', () {
      const pin = '1234';
      const salt = 'salt';
      final correctHash = service.hashPin(pin, salt);
      // Tamper with the hash
      final wrongHash = List<int>.from(correctHash);
      wrongHash[0] = (wrongHash[0] + 1) % 256;
      expect(service.verifyPin(pin, wrongHash, salt), isFalse);
    });

    test('rejects hash of different length', () {
      const pin = '1234';
      const salt = 'salt';
      // A hash that is too short
      expect(service.verifyPin(pin, [1, 2, 3], salt), isFalse);
    });
  });

  group('stored PIN contract (real secure storage path)', () {
    late _FakeKeychain keychain;
    late PinLockService realService;

    setUp(() {
      keychain = _FakeKeychain()..install();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      realService = PinLockService();
    });

    tearDown(() => keychain.uninstall());

    void seedLegacyPin({String pin = '1234', String salt = 'legacy-salt'}) {
      keychain.store['prism.pin_hash'] = base64Encode(
        realService.hashPin(pin, salt),
      );
      keychain.store['prism.pin_salt'] = salt;
    }

    test('missing PIN reports unset and rejects verification', () async {
      expect(await realService.isPinSet(), isFalse);
      expect(await realService.verifyStoredPin('1234'), isFalse);
    });

    test(
      'stores an Argon2id PIN and verifies only the matching value',
      () async {
        await realService.storePin('4567');

        expect(await realService.isPinSet(), isTrue);
        expect(keychain.store['prism.pin_hash_version'], '2');
        expect(keychain.store['prism.pin_hash'], isNotEmpty);
        expect(keychain.store['prism.pin_salt'], isNotEmpty);
        expect(await realService.verifyStoredPin('4567'), isTrue);
        expect(await realService.verifyStoredPin('0000'), isFalse);
      },
    );

    test('successful legacy verification migrates the stored slot', () async {
      seedLegacyPin();
      final legacyHash = keychain.store['prism.pin_hash'];

      expect(await realService.verifyStoredPin('1234'), isTrue);
      expect(keychain.store['prism.pin_hash_version'], '2');
      expect(keychain.store['prism.pin_hash'], isNot(legacyHash));
      expect(await realService.verifyStoredPin('1234'), isTrue);
    });

    test('wrong legacy PIN leaves the legacy slot untouched', () async {
      seedLegacyPin();
      final legacyHash = keychain.store['prism.pin_hash'];

      expect(await realService.verifyStoredPin('9999'), isFalse);
      expect(keychain.store['prism.pin_hash_version'], isNull);
      expect(keychain.store['prism.pin_hash'], legacyHash);
    });

    test('missing salt rejects a stored version-two hash', () async {
      keychain.store['prism.pin_hash'] = base64Encode(
        PinLockService.hashPinArgon2id('1234', 'missing-salt'),
      );
      keychain.store['prism.pin_hash_version'] = '2';

      expect(await realService.verifyStoredPin('1234'), isFalse);
    });

    test(
      'malformed stored hash preserves the production FormatException',
      () async {
        keychain.store['prism.pin_hash'] = 'not base64';
        keychain.store['prism.pin_salt'] = 'salt';
        keychain.store['prism.pin_hash_version'] = '2';

        expect(realService.verifyStoredPin('1234'), throwsFormatException);
      },
    );

    test(
      'transient secure-storage reads reject verification without leaking',
      () async {
        keychain.throwOnRead = PlatformException(
          code: 'temporarily_unavailable',
        );

        expect(await realService.verifyStoredPin('1234'), isFalse);
      },
    );

    test('failed storage writes leave no usable PIN slot', () async {
      keychain.throwOnWrite = PlatformException(
        code: 'temporarily_unavailable',
      );

      await realService.storePin('1234');

      expect(keychain.store, isEmpty);
      expect(await realService.isPinSet(), isFalse);
    });

    test(
      'failed legacy migration keeps a verified legacy slot for retry',
      () async {
        seedLegacyPin();
        final legacyHash = keychain.store['prism.pin_hash'];
        keychain.throwOnWrite = PlatformException(
          code: 'temporarily_unavailable',
        );

        expect(await realService.verifyStoredPin('1234'), isTrue);
        expect(keychain.store['prism.pin_hash'], legacyHash);
        expect(keychain.store['prism.pin_hash_version'], isNull);
      },
    );

    test('clearPin removes the real stored PIN slot', () async {
      await realService.storePin('1234');
      await realService.clearPin();

      expect(await realService.isPinSet(), isFalse);
      expect(keychain.store, isEmpty);
    });
  });

  // ── enforceLegacyPinMigrationPolicy (real secure storage via channel) ──────
  group('enforceLegacyPinMigrationPolicy', () {
    late _FakeKeychain keychain;
    late PinLockService realService;

    setUp(() {
      keychain = _FakeKeychain()..install();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      realService = PinLockService();
    });

    tearDown(() => keychain.uninstall());

    void seedLegacyPin() {
      // Legacy v1 slot: SHA-256 hash + salt, NO version key (== version 1).
      final hash = realService.hashPin('1234', 'salt0123456789ab');
      keychain.store['prism.pin_hash'] = base64Encode(Uint8List.fromList(hash));
      keychain.store['prism.pin_salt'] = 'salt0123456789ab';
    }

    test('no-op when no PIN is set', () async {
      final invalidated = await realService.enforceLegacyPinMigrationPolicy();
      expect(invalidated, isFalse);
      expect(
        keychain.store.containsKey('prism.pin_legacy_boot_count'),
        isFalse,
      );
    });

    test('no-op for an Argon2id (version 2) slot', () async {
      final hash = PinLockService.hashPinArgon2id('1234', 'salt0123456789ab');
      keychain.store['prism.pin_hash'] = base64Encode(Uint8List.fromList(hash));
      keychain.store['prism.pin_salt'] = 'salt0123456789ab';
      keychain.store['prism.pin_hash_version'] = '2';

      final invalidated = await realService.enforceLegacyPinMigrationPolicy();
      expect(invalidated, isFalse);
      // The Argon2id slot is untouched.
      expect(keychain.store.containsKey('prism.pin_hash'), isTrue);
      expect(
        keychain.store.containsKey('prism.pin_legacy_boot_count'),
        isFalse,
      );
    });

    test('increments the boot counter while a legacy slot lingers', () async {
      seedLegacyPin();

      final invalidated = await realService.enforceLegacyPinMigrationPolicy();
      expect(invalidated, isFalse);
      expect(keychain.store['prism.pin_legacy_boot_count'], '1');
      // Legacy slot still present (not yet over the threshold).
      expect(keychain.store.containsKey('prism.pin_hash'), isTrue);
    });

    test('force-invalidates the legacy slot after the boot threshold', () async {
      seedLegacyPin();

      var invalidated = false;
      // The guard fires on the boot where the counter reaches the threshold.
      for (var i = 0; i < 10; i++) {
        invalidated = await realService.enforceLegacyPinMigrationPolicy();
      }

      expect(invalidated, isTrue);
      // Legacy hash/salt/version cleared → user re-enrolls a fresh Argon2id PIN.
      expect(keychain.store.containsKey('prism.pin_hash'), isFalse);
      expect(keychain.store.containsKey('prism.pin_salt'), isFalse);
      expect(keychain.store.containsKey('prism.pin_hash_version'), isFalse);
      // Counter is cleared after invalidation.
      expect(
        keychain.store.containsKey('prism.pin_legacy_boot_count'),
        isFalse,
      );
      // And there is no PIN set anymore.
      expect(await realService.isPinSet(), isFalse);
    });

    test('a successful unlock-migration short-circuits the policy', () async {
      seedLegacyPin();

      // One boot — counter goes to 1.
      await realService.enforceLegacyPinMigrationPolicy();
      expect(keychain.store['prism.pin_legacy_boot_count'], '1');

      // User unlocks: legacy verify migrates to Argon2id and clears the counter.
      expect(await realService.verifyStoredPin('1234'), isTrue);
      expect(keychain.store['prism.pin_hash_version'], '2');
      expect(
        keychain.store.containsKey('prism.pin_legacy_boot_count'),
        isFalse,
      );

      // Subsequent policy runs are no-ops (now version 2).
      final invalidated = await realService.enforceLegacyPinMigrationPolicy();
      expect(invalidated, isFalse);
      expect(keychain.store.containsKey('prism.pin_hash'), isTrue);
    });
  });
}
