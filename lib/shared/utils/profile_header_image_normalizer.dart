import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

abstract interface class ProfileHeaderWebpEncoder {
  /// [pngBytes] is the lossless intermediate built off the main isolate;
  /// [width]/[height] cap the native encode.
  Future<Uint8List> encode({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required int quality,
  });
}

class FlutterProfileHeaderWebpEncoder implements ProfileHeaderWebpEncoder {
  const FlutterProfileHeaderWebpEncoder();

  @override
  Future<Uint8List> encode({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required int quality,
  }) async {
    // Rust sends opaque images to JPEG but anything with real transparency to
    // lossless WebP, which ignores `quality` — those shrink only by dimension.
    final (bytes, _) = await media_codec.encodeImage(
      imageBytes: pngBytes,
      maxWidth: width,
      maxHeight: height,
      quality: quality,
    );
    return bytes;
  }
}

/// A prepared header ladder frame — dimensions plus its lossless PNG. Built by
/// [prepareProfileHeaderLadder], which production runs in a background isolate.
/// The FFI re-encode (not isolate-sendable) runs against [png] on the platform
/// thread.
@visibleForTesting
class PreparedProfileHeaderFrame {
  const PreparedProfileHeaderFrame({
    required this.width,
    required this.height,
    required this.png,
  });

  final int width;
  final int height;
  final Uint8List png;
}

/// Runs the pure-Dart header preparation (decode, 3:1 center-crop, downscale
/// ladder, PNG encoding) and returns its frames.
///
/// The production default is
/// [computeProfileHeaderPreparationOffMain], which runs the work in a
/// background isolate. Tests inject a synchronous recording function to observe
/// orchestration, or call [prepareProfileHeaderLadder] directly for pure
/// pixel/ladder assertions.
typedef ProfileHeaderPreparationRunner =
    Future<List<PreparedProfileHeaderFrame>> Function(Uint8List input);

/// Test-only start/resume barrier for the off-main preparation isolate.
///
/// Production never constructs this. A test allocates a [ReceivePort], passes
/// its [SendPort] here, and then:
///
/// 1. reads the worker's `Isolate.current.controlPort` and resume port from the
///    first event, proving a *distinct* isolate runs the preparation;
/// 2. observes a queued event on its own event loop while the worker is still
///    paused, proving the caller's isolate stays live;
/// 3. sends any message to the resume port to release the worker.
///
/// The barrier is port-driven, so the boundary proof never depends on a timer
/// race or wall-clock threshold.
@visibleForTesting
class ProfileHeaderPreparationProbe {
  const ProfileHeaderPreparationProbe({required this.eventPort});

  final SendPort eventPort;
}

/// Sendable task handed to the preparation isolate. Carries only the input
/// bytes and the optional test probe — never a live resource or a closure.
class _HeaderPreparationTask {
  const _HeaderPreparationTask({required this.input, this.probe});

  final Uint8List input;
  final ProfileHeaderPreparationProbe? probe;
}

/// The first event the worker sends: its own control port plus the port it
/// waits on before finishing. Named so the barrier test can destructure it.
@visibleForTesting
class ProfileHeaderPreparationStarted {
  const ProfileHeaderPreparationStarted({
    required this.workerControlPort,
    required this.resumePort,
  });

  final SendPort workerControlPort;
  final SendPort resumePort;
}

class ProfileHeaderImageNormalizer {
  ProfileHeaderImageNormalizer({
    ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
    ProfileHeaderPreparationRunner? prepareRunner,
  }) : _encoder = encoder,
       _prepareRunner = prepareRunner ?? computeProfileHeaderPreparationOffMain;

  static const maxWidth = 1800;
  static const maxHeight = 600;
  static const targetMaxBytes = 384 * 1024;
  static const hardMaxBytes = 512 * 1024;
  static const _webpQualities = <int>[85, 82, 78, 74, 68, 62, 56, 50];

  // Last-resort floor for the downscale fallback. Banners must fit
  // [hardMaxBytes] to clear the inline-sync size cliff (otherwise they render
  // as broken images on other devices), so we shrink until they do; this bounds
  // how small we'll go. Typical content fits far above 480-wide.
  static const _minFallbackWidth = 480;
  static const _downscaleFactor = 0.8;

  final ProfileHeaderWebpEncoder _encoder;
  final ProfileHeaderPreparationRunner _prepareRunner;

  /// Prep on the calling isolate, for contexts that can't spawn one — notably
  /// widget-test fake-async zones, where `compute` never completes.
  ///
  /// Production must not call this: it decodes, crops, downscales, and
  /// PNG-encodes a banner on the UI isolate, which ANR'd Android during
  /// profile-header picks and PluralKit banner pulls. Production call sites use
  /// [normalizeProfileHeaderImageOffMain] (pickers and banner caching) or
  /// [normalizeOffMainIsolate] (the oversized-inline re-emit migration).
  Future<Uint8List> normalize(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }
    return _encodeLadder(prepareProfileHeaderLadder(input));
  }

  /// Runs the pure-Dart prep in a background isolate, leaving only the FFI
  /// re-encode on the platform thread. Without this a banner GIF's
  /// frame-by-frame decode froze the UI thread (Android ANR) during the re-emit
  /// migration and PluralKit banner pulls.
  Future<Uint8List> normalizeOffMainIsolate(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }
    return _encodeLadder(await _prepareRunner(input));
  }

  /// Runs the FFI quality ladder per frame until one fits [hardMaxBytes].
  /// Best-effort, never throws on size (mirrors AvatarNormalizer): transparent
  /// banners hit lossless WebP, which ignores quality, so the ladder downscales
  /// instead; the smallest seen is the fallback.
  Future<Uint8List> _encodeLadder(
    List<PreparedProfileHeaderFrame> ladder,
  ) async {
    Uint8List? smallest;
    for (final frame in ladder) {
      final encoded = await _encodeBestQuality(frame);
      if (encoded != null) {
        if (smallest == null || encoded.length < smallest.length) {
          smallest = encoded;
        }
        if (encoded.length <= hardMaxBytes) {
          return encoded;
        }
      }
    }

    if (smallest == null) {
      throw StateError('Profile header WebP encoder returned no bytes');
    }
    // Floor reached and still over budget: return the smallest rather than fail.
    return smallest;
  }

  /// Runs the quality ladder once over a prepared [frame], returning the
  /// smallest encoding and stopping early once one is within [targetMaxBytes].
  /// Null only if nothing encoded.
  Future<Uint8List?> _encodeBestQuality(
    PreparedProfileHeaderFrame frame,
  ) async {
    Uint8List? smallest;
    for (final quality in _webpQualities) {
      final encoded = await _encoder.encode(
        pngBytes: frame.png,
        width: frame.width,
        height: frame.height,
        quality: quality,
      );
      if (encoded.isEmpty) continue;
      if (smallest == null || encoded.length < smallest.length) {
        smallest = encoded;
      }
      if (encoded.length <= targetMaxBytes) {
        return encoded;
      }
    }
    return smallest;
  }

  /// Shrinks [source] one step toward [_minFallbackWidth], preserving its
  /// (≈3:1) aspect ratio. Null once already at or below the floor.
  static img.Image? _downscaleTowardFloor(img.Image source) {
    if (source.width <= _minFallbackWidth) return null;

    // Upper bound forces progress (≥1px narrower); lower bound holds the floor.
    final nextWidth = (source.width * _downscaleFactor).round().clamp(
      _minFallbackWidth,
      source.width - 1,
    );
    final nextHeight = (source.height * nextWidth / source.width).round().clamp(
      1,
      source.height,
    );

    // Average, not cubic — cubic aliases on downscale and WebP locks it in.
    return img.copyResize(
      source,
      width: nextWidth,
      height: nextHeight,
      interpolation: img.Interpolation.average,
    );
  }

  /// Center-crop to a 3:1 aspect ratio. Rejects non-positive dimensions, which
  /// would make `width / height` non-finite and feed NaN into the crop math.
  @visibleForTesting
  static img.Image centerCropToThreeToOne(img.Image source) {
    if (source.width <= 0 || source.height <= 0) {
      throw ArgumentError(
        'Profile header image has invalid dimensions '
        '(${source.width}x${source.height})',
      );
    }
    final currentRatio = source.width / source.height;
    const targetRatio = 3.0;

    if ((currentRatio - targetRatio).abs() < 0.0001) {
      return source;
    }

    if (currentRatio > targetRatio) {
      // Floor at 1: an extreme ratio can round the crop axis to 0.
      final cropWidth = (source.height * targetRatio).round().clamp(
        1,
        source.width,
      );
      final x = ((source.width - cropWidth) / 2).round();
      return img.copyCrop(
        source,
        x: x,
        y: 0,
        width: cropWidth,
        height: source.height,
      );
    }

    final cropHeight = (source.width / targetRatio).round().clamp(
      1,
      source.height,
    );
    final y = ((source.height - cropHeight) / 2).round();
    return img.copyCrop(
      source,
      x: 0,
      y: y,
      width: source.width,
      height: cropHeight,
    );
  }

  static img.Image _resizeDown(img.Image source) {
    if (source.width <= maxWidth && source.height <= maxHeight) {
      return source;
    }

    // Average, not cubic — cubic aliases on downscale and WebP locks it in.
    return img.copyResize(
      source,
      width: maxWidth,
      height: maxHeight,
      interpolation: img.Interpolation.average,
    );
  }
}

/// Pure-Dart prep: decode, 3:1 center-crop, resize into the 1800x600 box, then
/// build the downscale ladder — PNG-encoding each step once. PNG is
/// quality-independent, so the FFI quality ladder reuses one PNG per frame.
///
/// Synchronous and cheap to call directly from tests; production reaches it
/// through [computeProfileHeaderPreparationOffMain].
@visibleForTesting
List<PreparedProfileHeaderFrame> prepareProfileHeaderLadder(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw ArgumentError('Unable to decode profile header image');
  }

  var prepared = ProfileHeaderImageNormalizer._resizeDown(
    ProfileHeaderImageNormalizer.centerCropToThreeToOne(decoded),
  );
  final frames = <PreparedProfileHeaderFrame>[];
  while (true) {
    frames.add(
      PreparedProfileHeaderFrame(
        width: prepared.width,
        height: prepared.height,
        png: Uint8List.fromList(img.encodePng(prepared)),
      ),
    );

    final downscaled = ProfileHeaderImageNormalizer._downscaleTowardFloor(
      prepared,
    );
    if (downscaled == null) break;
    prepared = downscaled;
  }
  return frames;
}

/// Production preparation runner: runs [prepareProfileHeaderLadder] in a
/// background isolate via [compute].
///
/// [probe] is a test-only start/resume barrier; production always leaves it
/// null, and the isolate boundary proof lives in the normalizer tests.
@visibleForTesting
Future<List<PreparedProfileHeaderFrame>> computeProfileHeaderPreparationOffMain(
  Uint8List input, {
  ProfileHeaderPreparationProbe? probe,
}) {
  return compute(
    (task) => _prepareHeaderLadderOffMain(task.input, probe: task.probe),
    _HeaderPreparationTask(input: input, probe: probe),
  );
}

/// Body of the preparation isolate. Never touches platform channels or FFI —
/// the native WebP encoder stays on the caller's isolate.
Future<List<PreparedProfileHeaderFrame>> _prepareHeaderLadderOffMain(
  Uint8List input, {
  ProfileHeaderPreparationProbe? probe,
}) async {
  if (probe == null) {
    return prepareProfileHeaderLadder(input);
  }

  final barrier = _HeaderPreparationBarrier(probe);
  barrier.started();
  var prepared = false;
  try {
    final frames = prepareProfileHeaderLadder(input);
    prepared = true;
    return frames;
  } finally {
    // Test-only: report whether preparation completed and pause until the test
    // resumes this isolate, so the boundary proof is port-driven.
    await barrier.finished(prepared: prepared);
  }
}

/// Worker side of [ProfileHeaderPreparationProbe].
class _HeaderPreparationBarrier {
  _HeaderPreparationBarrier(this._probe) : _responses = ReceivePort();

  final ProfileHeaderPreparationProbe _probe;
  final ReceivePort _responses;

  void started() {
    _probe.eventPort.send(
      ProfileHeaderPreparationStarted(
        workerControlPort: Isolate.current.controlPort,
        resumePort: _responses.sendPort,
      ),
    );
  }

  Future<void> finished({required bool prepared}) async {
    _probe.eventPort.send(prepared);
    await _responses.first;
    _responses.close();
  }
}

/// Production entrypoint for a single profile-header/banner normalization.
///
/// Decodes, crops, downscales, and PNG-encodes the banner ladder in a
/// background isolate and only invokes the native WebP encoder on the calling
/// isolate. Use this from every production path that can `await` — picker
/// output and PluralKit banner caching both do.
Future<Uint8List> normalizeProfileHeaderImageOffMain(
  Uint8List input, {
  ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
}) {
  return ProfileHeaderImageNormalizer(
    encoder: encoder,
  ).normalizeOffMainIsolate(input);
}

/// Prepares a profile header on the *calling* isolate.
///
/// Kept for fake-async widget tests and tightly controlled internal tests,
/// where `compute` never completes. Production call sites must use
/// [normalizeProfileHeaderImageOffMain] instead: this path runs the banner
/// decode/crop/downscale/PNG work on the UI isolate and previously produced
/// Android ANRs on profile-header picks and PluralKit banner pulls.
Future<Uint8List> normalizeProfileHeaderImage(
  Uint8List input, {
  ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
}) {
  return ProfileHeaderImageNormalizer(encoder: encoder).normalize(input);
}
