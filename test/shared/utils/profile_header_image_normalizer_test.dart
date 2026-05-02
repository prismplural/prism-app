import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

void main() {
  group('ProfileHeaderImageNormalizer', () {
    test('center-crops tall input to 3:1 before encoding', () async {
      final source = img.Image(width: 300, height: 300);
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      img.fillRect(
        source,
        x1: 0,
        y1: 100,
        x2: 299,
        y2: 199,
        color: img.ColorRgb8(0, 255, 0),
      );
      img.fillRect(
        source,
        x1: 0,
        y1: 200,
        x2: 299,
        y2: 299,
        color: img.ColorRgb8(0, 0, 255),
      );

      final encoder = _FakeWebpEncoder.fixed(100);
      await normalizeProfileHeaderImage(
        Uint8List.fromList(img.encodePng(source)),
        encoder: encoder,
      );

      final encodedImage = encoder.images.single;
      expect(encodedImage.width, 300);
      expect(encodedImage.height, 100);
      expect(encodedImage.getPixel(0, 0).g, 255);
    });

    test('resizes down only to max 1800x600', () async {
      final source = img.Image(width: 3600, height: 1200);
      img.fill(source, color: img.ColorRgb8(12, 34, 56));

      final encoder = _FakeWebpEncoder.fixed(100);
      await normalizeProfileHeaderImage(
        Uint8List.fromList(img.encodePng(source)),
        encoder: encoder,
      );

      final encodedImage = encoder.images.single;
      expect(encodedImage.width, ProfileHeaderImageNormalizer.maxWidth);
      expect(encodedImage.height, ProfileHeaderImageNormalizer.maxHeight);
    });

    test('does not upscale small input', () async {
      final source = img.Image(width: 900, height: 300);
      img.fill(source, color: img.ColorRgb8(12, 34, 56));

      final encoder = _FakeWebpEncoder.fixed(100);
      await normalizeProfileHeaderImage(
        Uint8List.fromList(img.encodePng(source)),
        encoder: encoder,
      );

      final encodedImage = encoder.images.single;
      expect(encodedImage.width, 900);
      expect(encodedImage.height, 300);
    });

    test('uses quality ladder until target byte budget is met', () async {
      final source = img.Image(width: 900, height: 300);
      img.fill(source, color: img.ColorRgb8(12, 34, 56));

      final encoder = _FakeWebpEncoder.byQuality({
        85: ProfileHeaderImageNormalizer.targetMaxBytes + 10,
        82: ProfileHeaderImageNormalizer.targetMaxBytes + 9,
        78: ProfileHeaderImageNormalizer.targetMaxBytes + 8,
        74: ProfileHeaderImageNormalizer.targetMaxBytes,
      });

      final normalized = await normalizeProfileHeaderImage(
        Uint8List.fromList(img.encodePng(source)),
        encoder: encoder,
      );

      expect(encoder.qualities, [85, 82, 78, 74]);
      expect(normalized.length, ProfileHeaderImageNormalizer.targetMaxBytes);
    });

    test(
      'returns best effort under hard max when target cannot be met',
      () async {
        final source = img.Image(width: 900, height: 300);
        img.fill(source, color: img.ColorRgb8(12, 34, 56));

        final encoder = _FakeWebpEncoder.fixed(
          ProfileHeaderImageNormalizer.targetMaxBytes + 1,
        );

        final normalized = await normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
          encoder: encoder,
        );

        expect(
          normalized.length,
          ProfileHeaderImageNormalizer.targetMaxBytes + 1,
        );
        expect(
          normalized.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );
      },
    );

    test('throws when hard max cannot be met', () async {
      final source = img.Image(width: 900, height: 300);
      img.fill(source, color: img.ColorRgb8(12, 34, 56));

      final encoder = _FakeWebpEncoder.fixed(
        ProfileHeaderImageNormalizer.hardMaxBytes + 1,
      );

      await expectLater(
        normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
          encoder: encoder,
        ),
        throwsStateError,
      );
    });

    test('rejects empty and undecodable input', () async {
      final encoder = _FakeWebpEncoder.fixed(100);

      await expectLater(
        normalizeProfileHeaderImage(Uint8List(0), encoder: encoder),
        throwsArgumentError,
      );
      await expectLater(
        normalizeProfileHeaderImage(
          Uint8List.fromList(utf8.encode('not an image')),
          encoder: encoder,
        ),
        throwsArgumentError,
      );
    });
  });
}

class _FakeWebpEncoder implements ProfileHeaderWebpEncoder {
  _FakeWebpEncoder.fixed(this.length) : lengthsByQuality = null;

  _FakeWebpEncoder.byQuality(this.lengthsByQuality) : length = null;

  final Map<int, int>? lengthsByQuality;
  final int? length;
  final qualities = <int>[];
  final images = <img.Image>[];

  @override
  Future<Uint8List> encode(img.Image image, {required int quality}) async {
    qualities.add(quality);
    images.add(img.Image.from(image));

    final outputLength = lengthsByQuality?[quality] ?? length ?? 1;
    return Uint8List(outputLength);
  }
}
