import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:prism_plurality/core/services/biometric_service.dart';

// ---------------------------------------------------------------------------
// Fake LocalAuthPlatform
// ---------------------------------------------------------------------------

/// Extends LocalAuthPlatform so that PlatformInterface.verifyToken passes.
class _FakeLocalAuthPlatform extends Fake
    implements LocalAuthPlatform, MockPlatformInterfaceMixin {
  bool deviceSupports = true;

  @override
  Future<bool> deviceSupportsBiometrics() async => deviceSupports;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => [];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => true;

  @override
  Future<bool> stopAuthentication() async => true;
}

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage stub via method channel
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};
  Map<String, String>? lastOptions;
  bool throwOnRead = false;
  int deleteCalls = 0;

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            final options = call.arguments['options'] as Map<Object?, Object?>?;
            if (options != null) {
              lastOptions = options.cast<String, String>();
            }

            switch (call.method) {
              case 'write':
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                _store[key] = value;
                return null;
              case 'read':
                if (throwOnRead) throw PlatformException(code: 'AuthError');
                final key = call.arguments['key'] as String;
                return _store[key];
              case 'delete':
                deleteCalls++;
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
    lastOptions = null;
    throwOnRead = false;
    deleteCalls = 0;
  }
}

class _NativeResetStub {
  _NativeResetStub({required this.onDeleteBiometricNamespace});

  final VoidCallback onDeleteBiometricNamespace;
  bool missing = false;
  int deleteBiometricNamespaceAttempts = 0;

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(BiometricService.androidNativeChannelName),
          (MethodCall call) async {
            if (call.method != BiometricService.androidDeleteNamespaceMethod) {
              throw MissingPluginException();
            }
            deleteBiometricNamespaceAttempts++;
            if (missing) throw MissingPluginException();
            onDeleteBiometricNamespace();
            return null;
          },
        );
  }

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(BiometricService.androidNativeChannelName),
          null,
        );
    missing = false;
    deleteBiometricNamespaceAttempts = 0;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocalAuthPlatform fakeAuth;
  final storageStub = _SecureStorageStub();
  final legacyDefaultBiometricStore = <String, String>{};
  late _NativeResetStub nativeResetStub;
  late BiometricService service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fakeAuth = _FakeLocalAuthPlatform();
    LocalAuthPlatform.instance = fakeAuth;
    storageStub.setup();
    nativeResetStub = _NativeResetStub(
      onDeleteBiometricNamespace: () {
        storageStub._store.remove('prism_sync.biometric_dek');
        legacyDefaultBiometricStore.remove('prism_sync.biometric_dek');
      },
    )..setup();
    service = BiometricService();
  });

  tearDown(() {
    nativeResetStub.teardown();
    storageStub.teardown();
    legacyDefaultBiometricStore.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  // ── isAvailable ───────────────────────────────────────────────────────────

  group('isAvailable', () {
    test('returns false when deviceSupportsBiometrics is false', () async {
      fakeAuth.deviceSupports = false;
      expect(await service.isAvailable(), isFalse);
    });

    test('returns true when deviceSupportsBiometrics is true', () async {
      fakeAuth.deviceSupports = true;
      expect(await service.isAvailable(), isTrue);
    });
  });

  // ── enroll ────────────────────────────────────────────────────────────────

  group('enroll', () {
    test('writes base64-encoded DEK bytes to storage', () async {
      final dek = Uint8List.fromList([1, 2, 3, 4, 5]);
      await service.enroll(dek);
      expect(storageStub._store['prism_sync.biometric_dek'], base64Encode(dek));
    });

    test('uses an isolated Android storage namespace', () async {
      await service.enroll(Uint8List.fromList([1, 2, 3]));

      expect(
        storageStub.lastOptions?['storageNamespace'],
        BiometricService.androidStorageNamespace,
      );
      expect(storageStub.lastOptions?['resetOnError'], 'true');
      expect(storageStub.lastOptions?['enforceBiometrics'], 'true');
      expect(storageStub.lastOptions?['migrateWithBackup'], 'false');
    });
  });

  // ── authenticate ──────────────────────────────────────────────────────────

  group('authenticate', () {
    test('returns DEK bytes when key is present', () async {
      final dek = Uint8List.fromList([10, 20, 30, 40]);
      storageStub._store['prism_sync.biometric_dek'] = base64Encode(dek);

      final result = await service.authenticate();
      expect(result, equals(dek));
    });

    test('returns null when not enrolled (key absent)', () async {
      final result = await service.authenticate();
      expect(result, isNull);
    });

    test('returns null on platform exception (biometric cancelled)', () async {
      storageStub._store['prism_sync.biometric_dek'] = base64Encode(
        Uint8List(4),
      );
      storageStub.throwOnRead = true;

      final result = await service.authenticate();
      expect(result, isNull);
    });
  });

  // ── clear ─────────────────────────────────────────────────────────────────

  group('clear', () {
    test('clears Android biometric namespace through native hook', () async {
      storageStub._store['prism_sync.biometric_dek'] = base64Encode(
        Uint8List.fromList([1, 2, 3]),
      );

      await service.clear();
      expect(nativeResetStub.deleteBiometricNamespaceAttempts, 1);
      expect(storageStub.deleteCalls, 0);
      expect(
        storageStub._store.containsKey('prism_sync.biometric_dek'),
        isFalse,
      );
    });

    test('clears legacy default-namespace biometric value natively', () async {
      legacyDefaultBiometricStore['prism_sync.biometric_dek'] = 'legacy';

      await service.clear();
      expect(nativeResetStub.deleteBiometricNamespaceAttempts, 1);
      expect(
        legacyDefaultBiometricStore.containsKey('prism_sync.biometric_dek'),
        isFalse,
      );
      expect(storageStub.deleteCalls, 0);
    });

    test(
      'falls back to storage delete when native hook is unavailable',
      () async {
        nativeResetStub.missing = true;
        storageStub._store['prism_sync.biometric_dek'] = base64Encode(
          Uint8List.fromList([1, 2, 3]),
        );

        await service.clear();
        expect(nativeResetStub.deleteBiometricNamespaceAttempts, 1);
        expect(storageStub.deleteCalls, 1);
        expect(
          storageStub._store.containsKey('prism_sync.biometric_dek'),
          isFalse,
        );
      },
    );

    test('uses storage delete off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      storageStub._store['prism_sync.biometric_dek'] = base64Encode(
        Uint8List.fromList([1, 2, 3]),
      );

      await service.clear();
      expect(nativeResetStub.deleteBiometricNamespaceAttempts, 0);
      expect(storageStub.deleteCalls, 1);
      expect(
        storageStub._store.containsKey('prism_sync.biometric_dek'),
        isFalse,
      );
    });
  });

  // ── isEnrolled ────────────────────────────────────────────────────────────

  group('isEnrolled', () {
    test('returns true when key is present', () async {
      storageStub._store['prism_sync.biometric_dek'] = base64Encode(
        Uint8List(32),
      );
      expect(await service.isEnrolled(), isTrue);
    });

    test('returns false when key is absent', () async {
      expect(await service.isEnrolled(), isFalse);
    });
  });
}
