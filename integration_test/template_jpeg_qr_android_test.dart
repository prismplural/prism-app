import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/shared/services/template_image_code_reader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android native analyzer reads a custom-field template QR from JPEG',
    (tester) async {
      const code = 'PF1:android-jpeg-qr-harness';
      final jpeg = _jpegQr(code);
      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, 'template-qr.jpg'));
      await file.writeAsBytes(jpeg, flush: true);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      var fallbackCalls = 0;
      final reader = TemplateImageCodeReader(
        platform: TargetPlatform.android,
        decodeVisibleQr: (_) async {
          fallbackCalls++;
          return null;
        },
      );

      final recovered = await reader.read(jpeg, path: file.path);

      expect(recovered, code);
      expect(
        fallbackCalls,
        0,
        reason:
            'The Android MobileScanner analyzer should decode the JPEG; '
            'the pure-Dart fallback must not be needed in this harness.',
      );

      // ignore: avoid_print
      print(
        '[template-jpeg-qr-android] PASS: recovered ${code.length}-character '
        'template payload from ${jpeg.length}-byte JPEG via MobileScanner',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Uint8List _jpegQr(String data, {int scale = 10, int quietZone = 4}) {
  final qr = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final side = (qr.moduleCount + quietZone * 2) * scale;
  final image = img.Image(width: side, height: side, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  for (var row = 0; row < qr.moduleCount; row++) {
    for (var column = 0; column < qr.moduleCount; column++) {
      if (!qr.isDark(row, column)) continue;
      img.fillRect(
        image,
        x1: (column + quietZone) * scale,
        y1: (row + quietZone) * scale,
        x2: (column + quietZone + 1) * scale - 1,
        y2: (row + quietZone + 1) * scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
