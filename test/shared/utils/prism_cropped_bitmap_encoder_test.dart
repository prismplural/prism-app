import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/shared/utils/prism_cropped_bitmap_encoder.dart';

void main() {
  test('encodes a cropped bitmap into decodable PNG bytes', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..color = const ui.Color(0xFF3A7BD5);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 24, 16), paint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(24, 16);

    final bytes = await encodeCroppedBitmapPng(image);
    final decoded = img.decodePng(bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, 24);
    expect(decoded.height, 16);
  });
}
