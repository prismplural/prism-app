import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

void main() {
  test('normalizes large images down to the avatar target size', () {
    final source = img.Image(width: 1200, height: 800);
    img.fill(source, color: img.ColorRgb8(12, 34, 56));
    final encoded = Uint8List.fromList(img.encodePng(source));

    final normalized = AvatarNormalizer.normalize(encoded);

    expect(normalized, isNotNull);

    final decoded = img.decodeJpg(normalized!);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(AvatarNormalizer.maxDimension));
    expect(decoded.height, lessThanOrEqualTo(AvatarNormalizer.maxDimension));
  });

  test('keeps normalized avatars under the target byte budget', () {
    final source = img.Image(width: 1024, height: 1024);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, (x * 17) % 255, (y * 29) % 255, (x + y) % 255);
      }
    }

    final encoded = Uint8List.fromList(img.encodePng(source));
    final normalized = AvatarNormalizer.normalize(encoded);

    expect(normalized, isNotNull);
    expect(
      normalized!.length,
      lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
    );
  });

  test('passes through null avatar data', () {
    expect(AvatarNormalizer.normalize(null), isNull);
  });
}
