import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

import '../../helpers/media_codec_test_support.dart';

/// Synchronous, recording stand-in for the off-main preparation runner. Lets
/// orchestration tests assert *that* the normalizer delegates preparation and
/// what it does with the resulting ladder, without isolate scheduling.
class _RecordingPreparationRunner {
  _RecordingPreparationRunner();

  final inputs = <Uint8List>[];

  Future<List<PreparedProfileHeaderFrame>> call(Uint8List input) async {
    inputs.add(input);
    return prepareProfileHeaderLadder(input);
  }

  /// Fixed-ladder runner for tests that need a specific frame set.
  static ProfileHeaderPreparationRunner fixed(
    List<PreparedProfileHeaderFrame> frames,
  ) {
    var calls = 0;
    return (input) async {
      calls += 1;
      expect(
        calls,
        1,
        reason: 'preparation runner must be called exactly once',
      );
      return frames;
    };
  }
}

/// Marker the boundary test queues on the caller's own event loop to prove it
/// stays live while the preparation isolate is paused. `const` so the identical
/// instance survives the round trip through the receive port.
const _profileHeaderCallerSentinel = <Object?>[];

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

    test('inline and off-main preparation produce identical ladders', () async {
      final banner = _animatedGifBanner();

      final inlineEncoder = _PngPassthroughEncoder();
      final offMainEncoder = _PngPassthroughEncoder();

      final inline = await ProfileHeaderImageNormalizer(
        encoder: inlineEncoder,
      ).normalize(banner);
      final offMain = await ProfileHeaderImageNormalizer(
        encoder: offMainEncoder,
      ).normalizeOffMainIsolate(banner);

      expect(offMain, inline);
      expect(offMainEncoder.images, hasLength(inlineEncoder.images.length));
      for (var i = 0; i < inlineEncoder.images.length; i++) {
        final a = inlineEncoder.images[i];
        final b = offMainEncoder.images[i];
        expect((b.width, b.height), (a.width, a.height));
      }
    });

    test(
      'off-main normalization delegates preparation to the injected runner',
      () async {
        final source = img.Image(width: 900, height: 300);
        img.fill(source, color: img.ColorRgb8(20, 30, 40));
        final input = Uint8List.fromList(img.encodePng(source));

        final runner = _RecordingPreparationRunner();
        final encoder = _FakeWebpEncoder.fixed(100);

        final normalized = await ProfileHeaderImageNormalizer(
          encoder: encoder,
          prepareRunner: runner.call,
        ).normalizeOffMainIsolate(input);

        // The runner received the raw input exactly once and produced the
        // ladder the encode phase then walked.
        expect(runner.inputs, [input]);
        expect(normalized, hasLength(100));
        expect(encoder.images.single.width, 900);
      },
    );

    test(
      'rejects empty input before invoking the preparation runner',
      () async {
        var runnerCalls = 0;

        await expectLater(
          ProfileHeaderImageNormalizer(
            prepareRunner: (input) async {
              runnerCalls += 1;
              return const [];
            },
          ).normalizeOffMainIsolate(Uint8List(0)),
          throwsArgumentError,
        );

        expect(runnerCalls, 0);
      },
    );

    test(
      'surfaces a preparation failure without touching the encoder',
      () async {
        final encoder = _FakeWebpEncoder.fixed(100);

        await expectLater(
          ProfileHeaderImageNormalizer(
            encoder: encoder,
            prepareRunner: (_) async => throw ArgumentError('bad image'),
          ).normalizeOffMainIsolate(Uint8List.fromList([1, 2, 3])),
          throwsArgumentError,
        );

        expect(encoder.qualities, isEmpty);
      },
    );

    test('preserves the empty-ladder StateError contract', () async {
      await expectLater(
        ProfileHeaderImageNormalizer(
          prepareRunner: _RecordingPreparationRunner.fixed(const []),
        ).normalizeOffMainIsolate(Uint8List.fromList([1, 2, 3])),
        throwsStateError,
      );
    });

    test('rejects undecodable input in the pure preparation callback', () {
      expect(
        () => prepareProfileHeaderLadder(
          Uint8List.fromList(utf8.encode('not an image')),
        ),
        throwsArgumentError,
      );
    });

    test('builds the full downscale ladder for an oversized banner', () {
      final source = img.Image(width: 3600, height: 1200);
      img.fill(source, color: img.ColorRgb8(12, 34, 56));

      final ladder = prepareProfileHeaderLadder(
        Uint8List.fromList(img.encodePng(source)),
      );

      expect(ladder, isNotEmpty);
      expect(
        (ladder.first.width, ladder.first.height),
        (
          ProfileHeaderImageNormalizer.maxWidth,
          ProfileHeaderImageNormalizer.maxHeight,
        ),
      );
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i].width, lessThan(ladder[i - 1].width));
      }
      expect(
        ladder.last.width,
        greaterThanOrEqualTo(480),
        reason: 'ladder must stop at the fallback floor',
      );
      for (final frame in ladder) {
        expect(frame.png, isNotEmpty);
      }
    });

    // The production wrapper's isolate boundary, proven with a port-driven
    // start/resume barrier rather than a timer race: the worker reports its own
    // isolate identity, then pauses while the caller's event loop keeps
    // running; only an explicit resume releases it.
    test(
      'runs preparation in a distinct isolate while the caller stays live',
      () async {
        final source = img.Image(width: 900, height: 300);
        img.fill(source, color: img.ColorRgb8(20, 30, 40));
        final input = Uint8List.fromList(img.encodePng(source));

        final events = ReceivePort();
        final eventsDone = Completer<void>();
        final observed = <Object?>[];
        var boundaryVerified = false;

        events.listen((message) {
          observed.add(message);
          if (message is ProfileHeaderPreparationStarted) {
            final started = message;

            // Distinct isolate: a worker's control port never equals the
            // caller's, so the preparation did not run on this isolate.
            expect(
              started.workerControlPort,
              isNot(equals(Isolate.current.controlPort)),
            );

            // The caller's event loop is live while the worker is paused: this
            // queued microtask runs before the worker can be resumed.
            scheduleMicrotask(
              () => events.sendPort.send(_profileHeaderCallerSentinel),
            );
          } else if (identical(message, _profileHeaderCallerSentinel)) {
            expect(observed.first, isA<ProfileHeaderPreparationStarted>());
            expect(
              observed.indexOf(_profileHeaderCallerSentinel),
              greaterThan(0),
              reason: 'the resume sentinel must follow the worker start event',
            );
            // The worker is still suspended here — release it now.
            boundaryVerified = true;
            (observed.first! as ProfileHeaderPreparationStarted).resumePort
                .send('resume');
          } else if (message is bool) {
            expect(message, isTrue, reason: 'preparation must have completed');
            if (!eventsDone.isCompleted) eventsDone.complete();
          }
        });

        final frames = await computeProfileHeaderPreparationOffMain(
          input,
          probe: ProfileHeaderPreparationProbe(eventPort: events.sendPort),
        );

        await eventsDone.future;
        events.close();

        expect(boundaryVerified, isTrue);
        expect(frames, isNotEmpty);
        expect((frames.first.width, frames.first.height), (900, 300));
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
