import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

import '../../helpers/media_codec_test_support.dart';

void main() {
  final mediaCodecFfiLibPath = resolveMediaCodecFfiLibPath();

  setUpAll(() async {
    if (mediaCodecFfiLibPath == null) return;
    await media_codec.MediaCodecRustLib.init(
      externalLibrary: ExternalLibrary.open(mediaCodecFfiLibPath),
    );
  });

  tearDownAll(() {
    if (mediaCodecFfiLibPath != null) {
      media_codec.MediaCodecRustLib.dispose();
    }
  });

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

    test('returns best effort without throwing when even the floor exceeds '
        'the hard cap', () async {
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

      expect(normalized.length, ProfileHeaderImageNormalizer.hardMaxBytes + 1);
      // It exhausted the downscale ladder before giving up.
      expect(
        encoder.images.last.width,
        lessThan(ProfileHeaderImageNormalizer.maxWidth),
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

    test(
      'normalizes transparent headers through the real media codec',
      skip: missingMediaCodecFfiLibReason(
        mediaCodecFfiLibPath,
        'profile header integration test',
      ),
      () async {
        final source = img.Image(width: 600, height: 600, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));
        img.fillRect(
          source,
          x1: 300,
          y1: 200,
          x2: 599,
          y2: 399,
          color: img.ColorRgba8(20, 80, 140, 255),
        );

        final normalized = await normalizeProfileHeaderImage(
          Uint8List.fromList(img.encodePng(source)),
        );

        expect(_isWebp(normalized), isTrue);
        final decoded = img.decodeImage(normalized);
        expect(decoded, isNotNull);
        expect((decoded!.width, decoded.height), (600, 200));
        expect(decoded.hasAlpha, isTrue);
        expect(
          normalized.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );
      },
    );

    // Regression: a banner GIF used to be decoded frame-by-frame on the main
    // isolate during the re-emit migration, freezing the UI thread (ANR).
    // normalizeOffMainIsolate moves that decode into a background isolate. The
    // passthrough fake stands in for the native encoder (which flattens the
    // animation), so this only checks the off-isolate prep cropped to 3:1.
    test(
      're-encodes an animated GIF banner through the off-isolate path',
      () async {
        final encoder = _PngPassthroughEncoder();

        final normalized = await ProfileHeaderImageNormalizer(
          encoder: encoder,
        ).normalizeOffMainIsolate(_animatedGifBanner());

        // One ladder frame was enough — the budget was met at the base resolution
        // without walking the downscale ladder.
        expect(encoder.images, hasLength(1));
        final prepared = encoder.images.single;
        expect(prepared.width, 900);
        expect(prepared.height, 300); // center-cropped 900x900 → 3:1

        // The passthrough output decodes back to the prepared 3:1 banner, within
        // the inline-sync hard cap.
        final decoded = img.decodeImage(normalized);
        expect(decoded, isNotNull);
        expect(decoded!.width, 900);
        expect(decoded.height, 300);
        expect(
          normalized.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );
      },
    );
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

  /// Frames the normalizer fed in, decoded back from their PNG so tests inspect
  /// dimensions and pixels just as they did before the off-isolate split.
  final images = <img.Image>[];

  @override
  Future<Uint8List> encode({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required int quality,
  }) async {
    qualities.add(quality);
    images.add(img.decodeImage(pngBytes)!);

    final bytesPerPixel = this.bytesPerPixel;
    final outputLength = bytesPerPixel != null
        ? (width * height * bytesPerPixel).round()
        : lengthsByQuality?[quality] ?? length ?? 1;
    return Uint8List(outputLength);
  }
}

/// Returns the prepared PNG verbatim, so a test can decode the normalizer's
/// output back into a real image. Records each frame it was handed.
class _PngPassthroughEncoder implements ProfileHeaderWebpEncoder {
  final images = <img.Image>[];

  @override
  Future<Uint8List> encode({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required int quality,
  }) async {
    images.add(img.decodeImage(pngBytes)!);
    return pngBytes;
  }
}

img.Image _gradient(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 255, (y * 5) % 255, (x + y) % 255);
    }
  }
  return image;
}

/// A real two-frame animated GIF banner — the format that walked frame-by-frame
/// on the main isolate and tipped the re-emit migration into an ANR. 900x900 so
/// the off-isolate prep also exercises the center-crop to 3:1.
Uint8List _animatedGifBanner() {
  final frame0 = _gradient(900, 900);
  final frame1 = img.Image(width: 900, height: 900);
  img.fill(frame1, color: img.ColorRgb8(10, 10, 200));
  frame0.addFrame(frame1);
  return Uint8List.fromList(img.encodeGif(frame0));
}

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
