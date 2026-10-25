import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

void main() {
  test('crop storage encoding preserves transparent and partial alpha', () {
    final source = _alphaImage();
    final output = encodeAvatarOutputForStorage(_png(source));
    _expectAlphaAndAppearance(output, source);
  });

  test('normalization preserves transparent and partial alpha', () {
    final source = _alphaImage();
    final output = AvatarNormalizer.normalize(_png(source))!;
    _expectAlphaAndAppearance(output, source);
    expect(output.length, lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes));
  });

  test('crop output retains alpha across repeated storage normalization', () {
    final source = _alphaImage();
    var output = encodeAvatarOutputForStorage(_png(source));
    for (var save = 0; save < 3; save++) {
      output = AvatarNormalizer.normalize(output)!;
      _expectAlphaAndAppearance(output, source);
    }
  });

  test('off-main and batch normalization retain alpha', () async {
    final source = _alphaImage();
    final input = _png(source);
    final output = await AvatarNormalizer.normalizeOffMainIsolate(input);
    _expectAlphaAndAppearance(output!, source);
    final batch = await AvatarNormalizer.normalizeBatch([input, null]);
    _expectAlphaAndAppearance(batch[0]!, source);
    expect(batch[1], isNull);
  });

  test('fully opaque RGBA input still uses efficient JPEG', () {
    final source = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(30, 70, 110, 255));
    final input = _png(source);
    for (final output in [
      encodeAvatarOutputForStorage(input),
      AvatarNormalizer.normalize(input)!,
    ]) {
      expect(img.decodeJpg(output), isNotNull);
      expect(output.length, lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes));
    }
  });

  test('noisy transparent crop output obeys dimension and byte limits', () {
    final source = img.Image(width: 640, height: 640, numChannels: 4);
    var seed = 7;
    int next() {
      seed ^= (seed << 13) & 0xffffffff;
      seed ^= seed >> 17;
      seed ^= (seed << 5) & 0xffffffff;
      return seed & 0xff;
    }

    for (final pixel in source) {
      pixel.setRgba(next(), next(), next(), 128);
    }
    final input = _png(source);
    expect(input.length, greaterThan(AvatarNormalizer.targetMaxBytes));
    for (final output in [
      encodeAvatarOutputForStorage(input),
      AvatarNormalizer.normalize(input)!,
    ]) {
      expect(output.length, lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes));
      final decoded = img.decodeImage(output)!;
      expect(decoded.width, lessThanOrEqualTo(AvatarNormalizer.maxDimension));
      expect(decoded.height, lessThanOrEqualTo(AvatarNormalizer.maxDimension));
      expect(decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a, 128);
    }
  });

  test('corrupt avatar input fails instead of producing opaque output', () {
    final corrupt = Uint8List.fromList([1, 2, 3, 4]);
    // image 4.8.0's PSD header probe throws RangeError for this short input,
    // before avatar normalization; preserve that existing rejection contract.
    expect(
      () => AvatarNormalizer.normalize(corrupt),
      throwsA(isA<RangeError>()),
    );
    expect(() => encodeAvatarOutputForStorage(corrupt), throwsStateError);
  });
}

img.Image _alphaImage() {
  final image = img.Image(width: 24, height: 24, numChannels: 4);
  for (final pixel in image) {
    pixel.setRgba(40, 100, 180, [0, 128, 255][pixel.x ~/ 8]);
  }
  return image;
}

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

void _expectAlphaAndAppearance(Uint8List bytes, img.Image source) {
  final saved = img.decodeImage(bytes);
  expect(saved, isNotNull);
  expect(saved!.width, source.width);
  expect(saved.height, source.height);
  for (final x in [4, 12, 20]) {
    final before = source.getPixel(x, 12);
    final after = saved.getPixel(x, 12);
    expect(after.a, before.a, reason: 'alpha at x=$x');
    // Compare saved appearance against the preview over light and dark surfaces.
    // Fully transparent RGB is immaterial; only composited values must match.
    for (final background in [0, 255]) {
      for (var channel = 0; channel < 3; channel++) {
        num composite(img.Pixel pixel) =>
            (pixel[channel] * pixel.a + background * (255 - pixel.a)) / 255;
        expect(composite(after), closeTo(composite(before), 1));
      }
    }
  }
}
