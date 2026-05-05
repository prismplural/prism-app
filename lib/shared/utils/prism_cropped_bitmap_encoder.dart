import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> encodeCroppedBitmapPng(ui.Image image) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Unable to encode cropped image bitmap');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
