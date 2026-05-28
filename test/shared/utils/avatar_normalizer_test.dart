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

  // Regression: a small PNG/JPEG can declare 12000×12000 in its header, which
  // `img.decodeImage` would try to back with a ~576 MB RGBA buffer — instant
  // native OOM on Android. The header-only probe must reject this before
  // any pixel buffer is allocated.
  test('throws when source dimensions blow the pixel budget', () {
    const side = 8000;
    expect(side * side, greaterThan(AvatarNormalizer.maxSourcePixels));
    final huge = _jpegWithDeclaredDimensions(side, side);
    expect(
      () => AvatarNormalizer.normalize(huge),
      throwsA(isA<StateError>()),
    );
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
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds a real 2×2 JPEG, then patches its SOF0 marker to claim larger
/// dimensions. The JPEG decoder's header-only probe (`startDecode`) reads the
/// SOF0 fields directly, so the budget check fires before any pixel buffer
/// is allocated — exactly the path we want to exercise.
Uint8List _jpegWithDeclaredDimensions(int width, int height) {
  final source = img.Image(width: 2, height: 2);
  img.fill(source, color: img.ColorRgb8(1, 2, 3));
  final encoded = Uint8List.fromList(img.encodeJpg(source));
  for (var i = 0; i < encoded.length - 9; i++) {
    if (encoded[i] == 0xFF && encoded[i + 1] == 0xC0) {
      encoded[i + 5] = (height >> 8) & 0xFF;
      encoded[i + 6] = height & 0xFF;
      encoded[i + 7] = (width >> 8) & 0xFF;
      encoded[i + 8] = width & 0xFF;
      return encoded;
    }
  }
  throw StateError('no SOF0 marker found in encoded JPEG');
}
