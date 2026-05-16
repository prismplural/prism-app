import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const store = DeviceBoundRuntimeDekStore();
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  tearDown(() async {
    if (isDesktop) {
      await store.deleteWrappingKey();
    }
  });

  testWidgets(
    'desktop runtime DEK wrapper round-trips and rejects invalid context',
    (_) async {
      final dek = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      const aad = 'sync-id:test-sync\ndevice-id:test-device';

      final wrapped = await store.wrap(dek, aad: aad);
      final decoded = jsonDecode(wrapped) as Map<String, dynamic>;
      expect(
        wrapped,
        isNot(contains(base64Encode(dek))),
        reason: 'the wrapped blob must not contain the raw DEK bytes',
      );

      if (Platform.isMacOS) {
        expect(decoded['version'], 1);
        expect(decoded['platform'], 'macos_keychain_ecdh_p256_aes_gcm');
      } else if (Platform.isWindows) {
        expect(decoded['version'], 2);
        expect(decoded['platform'], 'windows');
        expect(decoded['protection'], 'dpapi_current_user');
      } else if (Platform.isLinux) {
        expect(decoded['version'], 1);
        expect(decoded['platform'], 'linux_secret_service_aes_gcm');
      }

      final restored = await store.unwrap(wrapped, aad: aad);
      expect(restored, orderedEquals(dek));

      await expectLater(
        store.unwrap(wrapped, aad: 'sync-id:test-sync\ndevice-id:other'),
        throwsA(anything),
      );

      if (!Platform.isWindows) {
        await store.deleteWrappingKey();
        await expectLater(store.unwrap(wrapped, aad: aad), throwsA(anything));
      }

      dek.fillRange(0, dek.length, 0);
      restored.fillRange(0, restored.length, 0);
    },
    skip: !isDesktop,
  );
}
