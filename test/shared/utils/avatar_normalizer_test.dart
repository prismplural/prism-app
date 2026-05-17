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

  test('preserves picker-sized cropped JPEG avatars', () {
    final source = img.Image(
      width: AvatarNormalizer.maxDimension,
      height: AvatarNormalizer.maxDimension,
    );
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, (x * 7) % 255, (y * 5) % 255, (x + y) % 255);
      }
    }
    final croppedPickerOutput = Uint8List.fromList(
      img.encodeJpg(source, quality: 85),
    );
    expect(
      croppedPickerOutput.length,
      lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
      reason: 'precondition: picker output should fit the normalizer budget',
    );

    final normalized = AvatarNormalizer.normalize(croppedPickerOutput);

    expect(identical(normalized, croppedPickerOutput), isTrue);
    final decoded = img.decodeJpg(normalized!);
    expect(decoded, isNotNull);
    expect(decoded!.width, AvatarNormalizer.maxDimension);
    expect(decoded.height, AvatarNormalizer.maxDimension);
  });

  test('passes through null avatar data', () {
    expect(AvatarNormalizer.normalize(null), isNull);
  });

  // Regression: every member save (any field, not just avatar) used to re-run
  // normalize, decode the existing JPEG, and re-encode it. JPEG generation
  // loss accumulated until avatars visibly degraded — two users hit it.
  // The fast-path returns conformant input verbatim, so repeated saves are
  // byte-identical.
  test('is idempotent on conformant input across repeated normalize calls', () {
    final source = img.Image(width: 1200, height: 800);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, (x * 11) % 255, (y * 13) % 255, (x + y) % 255);
      }
    }
    final initial = AvatarNormalizer.normalize(
      Uint8List.fromList(img.encodePng(source)),
    );
    expect(initial, isNotNull);

    var current = initial;
    for (var i = 0; i < 5; i++) {
      final next = AvatarNormalizer.normalize(current);
      expect(
        next,
        isNotNull,
        reason: 'normalize returned null on iteration $i',
      );
      expect(
        identical(next, current) || _bytesEqual(next!, current!),
        isTrue,
        reason:
            'iteration $i changed bytes (len before=${current!.length} after=${next!.length})',
      );
      current = next;
    }
  });

  test('returns small in-budget JPEG verbatim (fast-path)', () {
    final small = img.Image(width: 200, height: 200);
    for (var y = 0; y < small.height; y++) {
      for (var x = 0; x < small.width; x++) {
        small.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
      }
    }
    final jpegBytes = Uint8List.fromList(img.encodeJpg(small, quality: 85));
    expect(
      jpegBytes.length,
      lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
      reason: 'precondition: input must fit byte budget',
    );

    final normalized = AvatarNormalizer.normalize(jpegBytes);
    expect(
      identical(normalized, jpegBytes),
      isTrue,
      reason: 'fast-path should return the input instance verbatim',
    );
  });

  // Regression: avatars set to an animated GIF used to display a single static
  // frame. `decodeImage` flattens to one frame and `encodeJpg` discards the
  // rest, so every member save destroyed the animation. With GIF passthrough,
  // the original bytes survive both upload and the per-write normalize pass.
  group('animated GIF passthrough', () {
    test('returns in-budget GIF verbatim', () {
      final source = img.Image(width: 64, height: 64);
      img.fill(source, color: img.ColorRgb8(100, 150, 200));
      final gifBytes = Uint8List.fromList(img.encodeGif(source));
      expect(_isGifBytes(gifBytes), isTrue, reason: 'precondition');
      expect(
        gifBytes.length,
        lessThanOrEqualTo(AvatarNormalizer.gifMaxBytes),
        reason: 'precondition',
      );

      final normalized = AvatarNormalizer.normalize(gifBytes);

      expect(identical(normalized, gifBytes), isTrue);
      expect(_isGifBytes(normalized!), isTrue);
    });

    test('GIF passthrough is idempotent across repeated saves', () {
      final source = img.Image(width: 64, height: 64);
      img.fill(source, color: img.ColorRgb8(10, 20, 30));
      final gifBytes = Uint8List.fromList(img.encodeGif(source));

      var current = AvatarNormalizer.normalize(gifBytes);
      for (var i = 0; i < 5; i++) {
        final next = AvatarNormalizer.normalize(current);
        expect(identical(next, current), isTrue, reason: 'iteration $i');
        current = next;
      }
    });

    test('isAnimatedGifInput returns true for GIF87a and GIF89a headers', () {
      expect(
        AvatarNormalizer.isAnimatedGifInput(
          Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0]),
        ),
        isTrue,
      );
      expect(
        AvatarNormalizer.isAnimatedGifInput(
          Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0, 0]),
        ),
        isTrue,
      );
    });

    test('isAnimatedGifInput returns false for JPEG/PNG/null/short inputs', () {
      expect(AvatarNormalizer.isAnimatedGifInput(null), isFalse);
      expect(
        AvatarNormalizer.isAnimatedGifInput(Uint8List.fromList([])),
        isFalse,
      );
      expect(
        AvatarNormalizer.isAnimatedGifInput(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        ),
        isFalse,
      );
      expect(
        AvatarNormalizer.isAnimatedGifInput(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        ),
        isFalse,
      );
    });

    test('oversized GIF falls back to JPEG single-frame path', () {
      // A 2MB+ image always exceeds the 1MB GIF cap. Encode as GIF; the
      // normalizer must still produce a usable output (loses animation but
      // keeps the user's image visible) rather than throwing.
      final source = img.Image(width: 2000, height: 2000);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, (x * 7) % 255, (y * 11) % 255, (x + y) % 255);
        }
      }
      final gifBytes = Uint8List.fromList(img.encodeGif(source));
      expect(
        gifBytes.length,
        greaterThan(AvatarNormalizer.gifMaxBytes),
        reason: 'precondition: oversized',
      );

      final normalized = AvatarNormalizer.normalize(gifBytes);

      expect(normalized, isNotNull);
      // Fell back to JPEG path — no longer GIF bytes.
      expect(_isGifBytes(normalized!), isFalse);
    });
  });
}

bool _isGifBytes(Uint8List bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
