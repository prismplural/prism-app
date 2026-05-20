import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/prism_secure_store.dart';

class _FakeSecureStorageChannel {
  final values = <String, String>{};
  PlatformException? throwOnRead;
  PlatformException? throwOnWrite;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            switch (call.method) {
              case 'read':
                if (throwOnRead != null) throw throwOnRead!;
                return values[call.arguments['key'] as String];
              case 'write':
                if (throwOnWrite != null) throw throwOnWrite!;
                values[call.arguments['key'] as String] =
                    call.arguments['value'] as String;
                return null;
              case 'delete':
                values.remove(call.arguments['key'] as String);
                return null;
              case 'deleteAll':
                values.clear();
                return null;
              case 'readAll':
                return Map<String, String>.from(values);
              case 'containsKey':
                return values.containsKey(call.arguments['key'] as String);
            }
            return null;
          },
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorageChannel channel;
  late PrismSecureStore store;

  setUp(() {
    channel = _FakeSecureStorageChannel()..install();
    store = PrismSecureStore(const FlutterSecureStorage());
  });

  tearDown(() {
    channel.uninstall();
  });

  test('get returns decoded bytes for a valid value', () async {
    channel.values['sync_key'] = base64Encode(<int>[1, 2, 3]);

    expect(await store.get('sync_key'), orderedEquals(<int>[1, 2, 3]));
  });

  test('get returns null instead of leaking PlatformException', () async {
    channel.throwOnRead = PlatformException(
      code: 'Exception encountered',
      message: 'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
      details: 'javax.crypto.AEADBadTagException',
    );

    expect(await store.get('sync_key'), isNull);
  });

  test('get returns null for malformed base64', () async {
    channel.values['sync_key'] = 'not base64';

    expect(await store.get('sync_key'), isNull);
  });

  test(
    'set throws classified StateError instead of PlatformException',
    () async {
      channel.throwOnWrite = PlatformException(
        code: 'Exception encountered',
        message: 'java.security.InvalidKeyException: Failed to unwrap key',
        details: 'java.security.InvalidKeyException',
      );

      await expectLater(
        store.set('sync_key', Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    },
  );
}
