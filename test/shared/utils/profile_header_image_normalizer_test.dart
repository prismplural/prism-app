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

    test(
      'downscales lossless output past the byte cap instead of throwing',
      () async {
        // A detailed transparent banner routes to lossless WebP in production,
        // which ignores quality — so the quality ladder can't shrink it. This
        // fake reproduces that: size depends only on pixel count. At 1800x600 it
        // exceeds hardMaxBytes (this used to throw StateError); the normalizer
        // must downscale until it fits.
        final source = img.Image(width: 1800, height: 600, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(10, 20, 30, 255));
        img.fillRect(
          source,
          x1: 0,
          y1: 0,
          x2: 899,
          y2: 599,
          color: img.ColorRgba8(0, 0, 0, 0), // genuine transparency
        );

        final encoder = _FakeWebpEncoder.proportional(1.5);

        final normalized = await normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
          encoder: encoder,
        );

        // Lands under the hard byte cap without throwing...
        expect(
          normalized.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );
        // ...because the fallback downscaled below the 1800x600 max.
        final encodedImage = encoder.images.last;
        expect(
          encodedImage.width,
          lessThan(ProfileHeaderImageNormalizer.maxWidth),
        );
        expect(
          encodedImage.height,
          lessThan(ProfileHeaderImageNormalizer.maxHeight),
        );
      },
    );

    test(
      'keeps shrinking below a 900px banner so output still fits the cap',
      () async {
        // Dense alpha art whose lossless size is high enough that even a
        // 900-wide 3:1 banner blows the 512 KB cap. The fallback must keep
        // shrinking rather than store an oversized, unsyncable blob — otherwise
        // the banner shows as a broken image on other devices.
        final source = img.Image(width: 1800, height: 600, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(10, 20, 30, 200));

        final encoder = _FakeWebpEncoder.proportional(2.2);

        final normalized = await normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
          encoder: encoder,
        );

        // 900x300 at 2.2 B/px would be ~594 KB — over the cap — so it must have
        // shrunk past 900 to land in budget.
        expect(
          normalized.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );
        expect(encoder.images.last.width, lessThan(900));
      },
    );

    test(
      'returns best effort without throwing when even the floor exceeds '
      'the hard cap',
      () async {
        final source = img.Image(width: 1800, height: 600);
        img.fill(source, color: img.ColorRgb8(12, 34, 56));

        // Degenerate encoder: ignores both quality and dimensions, so no amount
        // of downscaling helps. The normalizer must still return best effort
        // rather than failing the upload (matching AvatarNormalizer's contract).
        final encoder = _FakeWebpEncoder.fixed(
          ProfileHeaderImageNormalizer.hardMaxBytes + 1,
        );

        final normalized = await normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
          encoder: encoder,
        );

        expect(
          normalized.length,
          ProfileHeaderImageNormalizer.hardMaxBytes + 1,
        );
        // It exhausted the downscale ladder before giving up.
        expect(
          encoder.images.last.width,
          lessThan(ProfileHeaderImageNormalizer.maxWidth),
        );
      },
    );

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

  group('ProfileHeaderImageNormalizer.centerCropToThreeToOne', () {
    test('rejects a zero-height image instead of dividing by zero', () {
      // A 0-height decode made `width / height` non-finite, feeding NaN into
      // the crop math.
      expect(
        () => ProfileHeaderImageNormalizer.centerCropToThreeToOne(
          img.Image(width: 600, height: 0),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('invalid dimensions'),
          ),
        ),
      );
    });

    test('rejects a 0x0 image', () {
      expect(
        () => ProfileHeaderImageNormalizer.centerCropToThreeToOne(
          img.Image(width: 0, height: 0),
        ),
        throwsArgumentError,
      );
    });

    test('passes an image already at 3:1 through unchanged', () {
      final cropped = ProfileHeaderImageNormalizer.centerCropToThreeToOne(
        img.Image(width: 300, height: 100),
      );
      expect(cropped.width, 300);
      expect(cropped.height, 100);
    });

    test('floors crop height at 1 for a 1px-wide tall image', () {
      // width=1 made cropHeight=(1/3).round()=0 — an empty crop rectangle.
      final cropped = ProfileHeaderImageNormalizer.centerCropToThreeToOne(
        img.Image(width: 1, height: 9000),
      );
      expect(cropped.width, 1);
      expect(cropped.height, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeWebpEncoder implements ProfileHeaderWebpEncoder {
  _FakeWebpEncoder.fixed(this.length)
    : lengthsByQuality = null,
      bytesPerPixel = null;

  _FakeWebpEncoder.byQuality(this.lengthsByQuality)
    : length = null,
      bytesPerPixel = null;

  /// Mimics real lossless WebP: output size is driven purely by pixel count and
  /// is unaffected by `quality`. Only downscaling can shrink it.
  _FakeWebpEncoder.proportional(this.bytesPerPixel)
    : length = null,
      lengthsByQuality = null;

  final Map<int, int>? lengthsByQuality;
  final int? length;
  final double? bytesPerPixel;
  final qualities = <int>[];
  final images = <img.Image>[];

  @override
  Future<Uint8List> encode(img.Image image, {required int quality}) async {
    qualities.add(quality);
    images.add(img.Image.from(image));

    final bytesPerPixel = this.bytesPerPixel;
    final outputLength = bytesPerPixel != null
        ? (image.width * image.height * bytesPerPixel).round()
        : lengthsByQuality?[quality] ?? length ?? 1;
    return Uint8List(outputLength);
  }
}
