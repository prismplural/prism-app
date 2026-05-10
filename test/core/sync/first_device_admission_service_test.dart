import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/first_device_admission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.prism.prism_plurality/first_device_admission',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FirstDeviceAdmissionService.collectPlatformProof', () {
    test('returns platform proof when native attestation succeeds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'collectFirstDeviceAdmissionProof');
            return <String, Object?>{
              'kind': 'apple_app_attest',
              'key_id': 'test-key',
              'attestation_object': 'test-attestation',
            };
          });

      final proof = await FirstDeviceAdmissionService().collectPlatformProof(
        syncId: 'sync-id',
        deviceId: 'device-id',
        nonce: 'nonce',
        registrationKeyBundleHash: '00' * 32,
      );

      expect(proof, {
        'kind': 'apple_app_attest',
        'key_id': 'test-key',
        'attestation_object': 'test-attestation',
      });
    });

    test('falls back to PoW when native attestation fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'collectFirstDeviceAdmissionProof');
            throw PlatformException(
              code: 'permanent_failure',
              message:
                  'App Attest attestation failed verification: '
                  'com.apple.devicecheck.error error 2',
            );
          });

      final proof = await FirstDeviceAdmissionService().collectPlatformProof(
        syncId: 'sync-id',
        deviceId: 'device-id',
        nonce: 'nonce',
        registrationKeyBundleHash: '00' * 32,
      );

      expect(proof, isNull);
    });
  });
}
