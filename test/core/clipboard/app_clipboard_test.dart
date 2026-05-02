import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('readImage decodes bytes from native clipboard channel', () async {
    const channel = MethodChannel('test.prism/app_clipboard/read_image');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return Uint8List.fromList(const [1, 2, 3]);
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const reader = MethodChannelAppClipboardReader(channel: channel);
    final image = await reader.readImage(
      pasteboard: ClipboardPasteboard.primarySelection,
    );

    expect(image?.bytes, orderedEquals(const [1, 2, 3]));
    expect(image?.pasteboard, ClipboardPasteboard.primarySelection);
    expect(calls.single.method, 'readImage');
    expect((calls.single.arguments as Map)['pasteboard'], 'primarySelection');
  });

  test('readImageUri decodes structured native image payloads', () async {
    const channel = MethodChannel('test.prism/app_clipboard/read_uri');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'bytes': Uint8List.fromList(const [4, 5, 6]),
            'mimeType': 'image/png',
            'sourceUri': 'content://prism.test/image.png',
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const reader = MethodChannelAppClipboardReader(channel: channel);
    final image = await reader.readImageUri('content://prism.test/image.png');

    expect(image?.bytes, orderedEquals(const [4, 5, 6]));
    expect(image?.mimeType, 'image/png');
    expect(image?.sourceUri, 'content://prism.test/image.png');
  });

  test(
    'decodes ByteData views without leaking surrounding buffer bytes',
    () async {
      final buffer = Uint8List.fromList(const [0, 1, 2, 3, 4, 5]).buffer;
      final channel = _PayloadMethodChannel(ByteData.view(buffer, 2, 3));

      final reader = MethodChannelAppClipboardReader(channel: channel);
      final image = await reader.readImage();

      expect(image?.bytes, orderedEquals(const [2, 3, 4]));
    },
  );

  test('returns null for platform errors', () async {
    const channel = MethodChannel('test.prism/app_clipboard/platform_error');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'clipboard_unavailable');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const reader = MethodChannelAppClipboardReader(channel: channel);
    expect(await reader.readImage(), isNull);
  });

  test('returns null for empty bytes and malformed maps', () async {
    const channel = MethodChannel('test.prism/app_clipboard/malformed');
    final responses = <Object?>[
      Uint8List(0),
      <String, Object?>{'bytes': 'not bytes'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return responses.removeAt(0);
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const reader = MethodChannelAppClipboardReader(channel: channel);
    expect(await reader.readImage(), isNull);
    expect(await reader.readImage(), isNull);
  });

  test('returns null for missing native clipboard implementation', () async {
    const channel = MethodChannel('test.prism/app_clipboard/missing');
    const reader = MethodChannelAppClipboardReader(channel: channel);

    expect(await reader.readImage(), isNull);
  });
}

class _PayloadMethodChannel extends MethodChannel {
  const _PayloadMethodChannel(this.payload) : super('test.prism/payload');

  final Object? payload;

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    return payload as T?;
  }
}
