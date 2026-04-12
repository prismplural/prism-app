import 'dart:convert';
import 'dart:typed_data';

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
  }) async =>
      true;

  @override
  Future<bool> stopAuthentication() async => true;
}

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage stub via method channel
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};
  bool throwOnRead = false;

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
            if (throwOnRead) throw PlatformException(code: 'AuthError');
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
    throwOnRead = false;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocalAuthPlatform fakeAuth;
  final storageStub = _SecureStorageStub();
  late BiometricService service;

  setUp(() {
    fakeAuth = _FakeLocalAuthPlatform();
    LocalAuthPlatform.instance = fakeAuth;
    storageStub.setup();
    service = BiometricService();
  });

  tearDown(storageStub.teardown);

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
      expect(
        storageStub._store['prism_sync.biometric_dek'],
        base64Encode(dek),
      );
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
      storageStub._store['prism_sync.biometric_dek'] =
          base64Encode(Uint8List(4));
      storageStub.throwOnRead = true;

      final result = await service.authenticate();
      expect(result, isNull);
    });
  });

  // ── clear ─────────────────────────────────────────────────────────────────

  group('clear', () {
    test('removes the biometric key from storage', () async {
      storageStub._store['prism_sync.biometric_dek'] =
          base64Encode(Uint8List.fromList([1, 2, 3]));

      await service.clear();
      expect(
        storageStub._store.containsKey('prism_sync.biometric_dek'),
        isFalse,
      );
    });
  });

  // ── isEnrolled ────────────────────────────────────────────────────────────

  group('isEnrolled', () {
    test('returns true when key is present', () async {
      storageStub._store['prism_sync.biometric_dek'] =
          base64Encode(Uint8List(32));
      expect(await service.isEnrolled(), isTrue);
    });

    test('returns false when key is absent', () async {
      expect(await service.isEnrolled(), isFalse);
    });
  });
}
