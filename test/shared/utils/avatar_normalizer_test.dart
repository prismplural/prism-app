import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

import '../../helpers/main_isolate_responsiveness.dart';

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

  // Regression: decoding avatars inline on the main isolate (in the Simply
  // Plural import batch and the oversized-inline re-emit migration) froze the
  // UI thread long enough to ANR — animated GIFs, walked frame-by-frame in
  // pure Dart, were the worst case. normalizeBatch runs the same routine in a
  // background isolate. This asserts the offloaded path is order-preserving
  // and byte-identical to per-item normalize, including a real animated GIF.
  test('normalizeBatch matches per-item normalize across formats', () async {
    final bigPng = Uint8List.fromList(img.encodePng(_gradient(1200, 800)));
    final conformingJpeg = Uint8List.fromList(
      img.encodeJpg(_gradient(200, 200), quality: 85),
    );
    final animatedGif = _animatedGif();

    final inputs = <Uint8List?>[bigPng, conformingJpeg, animatedGif, null];
    final batch = await AvatarNormalizer.normalizeBatch(inputs);

    expect(batch, hasLength(inputs.length));
    for (var i = 0; i < inputs.length; i++) {
      final inline = AvatarNormalizer.normalize(inputs[i]);
      if (inline == null) {
        expect(batch[i], isNull, reason: 'index $i should be null');
      } else {
        expect(
          _bytesEqual(batch[i]!, inline),
          isTrue,
          reason: 'offloaded result differs from inline normalize at index $i',
        );
      }
    }

    // The animated GIF (index 2) re-encodes to a budget-fitting JPEG.
    expect(batch[2], isNotNull);
    expect(batch[2]!.length, lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes));
    expect(img.decodeJpg(batch[2]!), isNotNull);
    // Conforming JPEG (index 1) returns verbatim through the batch path.
    expect(_bytesEqual(batch[1]!, conformingJpeg), isTrue);
  });

  test('normalizeBatch returns empty for an empty list', () async {
    expect(await AvatarNormalizer.normalizeBatch(const []), isEmpty);
  });

  test(
    'normalizeOffMainIsolate matches normalize and keeps the fast path',
    () async {
      final bigPng = Uint8List.fromList(img.encodePng(_gradient(1200, 800)));
      final conformingJpeg = Uint8List.fromList(
        img.encodeJpg(_gradient(200, 200), quality: 85),
      );

      final offloaded = await AvatarNormalizer.normalizeOffMainIsolate(bigPng);
      expect(
        _bytesEqual(offloaded!, AvatarNormalizer.normalize(bigPng)!),
        isTrue,
      );

      final verbatim = await AvatarNormalizer.normalizeOffMainIsolate(
        conformingJpeg,
      );
      expect(
        identical(verbatim, conformingJpeg),
        isTrue,
        reason: 'conforming avatars return verbatim without an isolate hop',
      );
    },
  );

  test(
    'normalizeOffMainIsolate re-encodes an over-budget JPEG like normalize',
    () async {
      final noisy = _noise(900, 900);
      final bigJpeg = Uint8List.fromList(img.encodeJpg(noisy, quality: 95));
      expect(
        bigJpeg.length,
        greaterThan(AvatarNormalizer.targetMaxBytes),
        reason: 'precondition: input must skip the inline probe',
      );

      final offloaded = await AvatarNormalizer.normalizeOffMainIsolate(bigJpeg);
      expect(identical(offloaded, bigJpeg), isFalse);
      expect(
        _bytesEqual(offloaded!, AvatarNormalizer.normalize(bigJpeg)!),
        isTrue,
      );
    },
  );

  group('normalizeOffMainIsolate main-isolate responsiveness', () {
    Future<void> expectOffMain(Uint8List source) async {
      Uint8List? offloaded;
      Uint8List? expected;
      await expectStaysResponsive(
        offMain: () async {
          offloaded = await AvatarNormalizer.normalizeOffMainIsolate(source);
        },
        inline: () => expected = AvatarNormalizer.normalize(source),
      );

      expect(_bytesEqual(offloaded!, expected!), isTrue);
    }

    test('an over-budget image re-encodes off the main isolate', () async {
      final source = Uint8List.fromList(
        img.encodeJpg(_noise(2400, 2400), quality: 90),
      );
      expect(
        source.length,
        greaterThan(AvatarNormalizer.targetMaxBytes),
        reason: 'precondition: input must skip the inline probe',
      );
      await expectOffMain(source);
    });

    test(
      'an in-budget oversized JPEG re-encodes off the main isolate',
      () async {
        // Subsampled chroma packs more pixels into the byte budget, so the
        // re-encode dwarfs the whole-file header probe this branch runs inline.
        final source = Uint8List.fromList(
          img.encodeJpg(
            _ramp(3600, 3600),
            quality: 40,
            chroma: img.JpegChroma.yuv420,
          ),
        );
        expect(
          source.length,
          lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
          reason: 'precondition: input must take the inline probe',
        );
        await expectOffMain(source);
      },
    );
  });

  test('normalizeOffMainIsolate reports bad input as a failed future', () {
    final huge = _jpegWithDeclaredDimensions(8000, 8000);
    expect(
      AvatarNormalizer.normalizeOffMainIsolate(huge),
      throwsA(isA<StateError>()),
    );
  });
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

/// Deterministic noise, which JPEG can't compress under the byte budget.
img.Image _noise(int width, int height) {
  final image = img.Image(width: width, height: height);
  var seed = 7;
  int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, next() & 0xFF, next() & 0xFF, next() & 0xFF);
    }
  }
  return image;
}

/// A smooth ramp, which JPEG fits in the byte budget far past the dimension
/// cap.
img.Image _ramp(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, 128);
    }
  }
  return image;
}

/// A real two-frame animated GIF — the format that walked frame-by-frame on
/// the main isolate and tipped the import into an ANR.
Uint8List _animatedGif() {
  final frame0 = _gradient(48, 48);
  final frame1 = img.Image(width: 48, height: 48);
  img.fill(frame1, color: img.ColorRgb8(10, 10, 200));
  frame0.addFrame(frame1);
  return Uint8List.fromList(img.encodeGif(frame0));
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
