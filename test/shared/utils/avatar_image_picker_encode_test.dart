import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';

void main() {
  test('encodes cropped avatar bytes into decodable square jpeg output', () {
    final source = img.Image(width: 900, height: 600);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    img.fillRect(
      source,
      x1: 200,
      y1: 100,
      x2: 699,
      y2: 499,
      color: img.ColorRgb8(220, 180, 40),
    );

    final encoded = encodeAvatarOutputForStorage(
      Uint8List.fromList(img.encodePng(source)),
    );
    final decoded = img.decodeJpg(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
  });

  test('throws when avatar output bytes are not decodable', () {
    expect(
      () => encodeAvatarOutputForStorage(
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsStateError,
    );
  });
}
