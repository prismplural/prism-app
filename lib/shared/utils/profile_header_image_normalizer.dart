import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:prism_sync/generated/api.dart' as ffi;

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
    final (bytes, _) = await ffi.encodeImage(
      imageBytes: pngBytes,
      maxWidth: width,
      maxHeight: height,
      quality: quality,
    );
    return bytes;
  }
}

/// A prepared header frame — dimensions plus its lossless PNG, built in a
/// background isolate. The FFI re-encode (not isolate-sendable) runs against
/// [png] on the platform thread.
class _PreparedHeaderFrame {
  const _PreparedHeaderFrame({
    required this.width,
    required this.height,
    required this.png,
  });

  final int width;
  final int height;
  final Uint8List png;
}

class ProfileHeaderImageNormalizer {
  ProfileHeaderImageNormalizer({
    ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
  }) : _encoder = encoder;

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

  /// Prep on the calling isolate, for contexts that can't spawn one — notably
  /// widget-test fake-async zones, where `compute` never completes. The re-emit
  /// migration uses [normalizeOffMainIsolate] instead.
  Future<Uint8List> normalize(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }
    return _encodeLadder(_prepareHeaderLadder(input));
  }

  /// Runs the pure-Dart prep in a background isolate, leaving only the FFI
  /// re-encode on the platform thread. Without this a banner GIF's
  /// frame-by-frame decode froze the UI thread (Android ANR) during the re-emit
  /// migration.
  Future<Uint8List> normalizeOffMainIsolate(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }
    return _encodeLadder(await compute(_prepareHeaderLadder, input));
  }

  /// Runs the FFI quality ladder per frame until one fits [hardMaxBytes].
  /// Best-effort, never throws on size (mirrors AvatarNormalizer): transparent
  /// banners hit lossless WebP, which ignores quality, so the ladder downscales
  /// instead; the smallest seen is the fallback.
  Future<Uint8List> _encodeLadder(List<_PreparedHeaderFrame> ladder) async {
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
  Future<Uint8List?> _encodeBestQuality(_PreparedHeaderFrame frame) async {
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

  /// Pure-Dart prep for [normalizeOffMainIsolate], run in a background isolate.
  /// Builds the downscale ladder, PNG-encoding each step once — PNG is
  /// quality-independent, so the FFI quality ladder reuses it.
  static List<_PreparedHeaderFrame> _prepareHeaderLadder(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw ArgumentError('Unable to decode profile header image');
    }

    var prepared = _resizeDown(centerCropToThreeToOne(decoded));
    final frames = <_PreparedHeaderFrame>[];
    while (true) {
      frames.add(
        _PreparedHeaderFrame(
          width: prepared.width,
          height: prepared.height,
          png: Uint8List.fromList(img.encodePng(prepared)),
        ),
      );

      final downscaled = _downscaleTowardFloor(prepared);
      if (downscaled == null) break;
      prepared = downscaled;
    }
    return frames;
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
    final nextHeight =
        (source.height * nextWidth / source.width).round().clamp(
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
      final cropWidth =
          (source.height * targetRatio).round().clamp(1, source.width);
      final x = ((source.width - cropWidth) / 2).round();
      return img.copyCrop(
        source,
        x: x,
        y: 0,
        width: cropWidth,
        height: source.height,
      );
    }

    final cropHeight =
        (source.width / targetRatio).round().clamp(1, source.height);
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

Future<Uint8List> normalizeProfileHeaderImage(
  Uint8List input, {
  ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
}) {
  return ProfileHeaderImageNormalizer(encoder: encoder).normalize(input);
}
