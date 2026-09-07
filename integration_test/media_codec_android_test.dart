import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

import 'package:prism_plurality/app.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'app boot initializes the codec and encodes a JPEG photo',
    (tester) async {
      app.main();

      Object? lastCodecError;
      String? codecHealth;
      for (var attempt = 0; attempt < 240; attempt++) {
        await tester.pump(const Duration(milliseconds: 250));
        try {
          codecHealth = await media_codec.codecHealthCheck();
          break;
        } catch (error) {
          lastCodecError = error;
        }
      }

      expect(
        codecHealth,
        'prism_media_codec_ffi',
        reason: 'The app did not initialize its media codec: $lastCodecError',
      );

      for (var attempt = 0; attempt < 240; attempt++) {
        if (find.byType(PrismApp).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(PrismApp), findsOneWidget);

      final source = _photoFixture();
      final sourceBytes = Uint8List.fromList(
        img.encodeJpg(source, quality: 95),
      );
      final stopwatch = Stopwatch()..start();
      final compressed = await ImageCompressionService().compressImage(
        sourceBytes,
      );
      stopwatch.stop();

      final decoded = img.decodeJpg(compressed.bytes);
      expect(compressed.mimeType, 'image/jpeg');
      expect((compressed.width, compressed.height), (2048, 1365));
      expect(decoded, isNotNull);
      expect((decoded!.width, decoded.height), (2048, 1365));
      expect(compressed.blurhash, isNotEmpty);
      expect(compressed.bytes, isNot(equals(sourceBytes)));

      // ignore: avoid_print
      print(
        '[media-codec-android] encoded ${source.width}x${source.height} JPEG '
        '(${sourceBytes.length} bytes) to ${decoded.width}x${decoded.height} '
        'JPEG (${compressed.bytes.length} bytes) in '
        '${stopwatch.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

img.Image _photoFixture() {
  const width = 2400;
  const height = 1600;
  final photo = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final horizon = y < height ~/ 2;
      final red = horizon ? 55 + (x * 110 ~/ width) : 35 + (y * 95 ~/ height);
      final green = horizon
          ? 110 + (y * 120 ~/ height)
          : 80 + (x * 95 ~/ width);
      final blue = horizon ? 190 + (x * 45 ~/ width) : 45 + ((x + y) % 70);
      photo.setPixelRgb(x, y, red, green, blue);
    }
  }

  return photo;
}
