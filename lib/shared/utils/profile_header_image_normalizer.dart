import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:prism_sync/generated/api.dart' as ffi;

abstract interface class ProfileHeaderWebpEncoder {
  Future<Uint8List> encode(img.Image image, {required int quality});
}

class FlutterProfileHeaderWebpEncoder implements ProfileHeaderWebpEncoder {
  const FlutterProfileHeaderWebpEncoder();

  @override
  Future<Uint8List> encode(img.Image image, {required int quality}) async {
    // Encode to PNG first (lossless intermediate), then let Rust re-encode.
    // Rust sends opaque images to JPEG but any image with real transparency to
    // lossless WebP, which ignores `quality` — so those can only be shrunk by
    // reducing dimensions, not quality.
    final (bytes, _) = await ffi.encodeImage(
      imageBytes: Uint8List.fromList(img.encodePng(image)),
      maxWidth: image.width,
      maxHeight: image.height,
      quality: quality,
    );
    return bytes;
  }
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

  Future<Uint8List> normalize(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }

    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw ArgumentError('Unable to decode profile header image');
    }

    // Best-effort, never throwing on size — mirrors AvatarNormalizer.normalize.
    // Quality can't shrink the lossless WebP that transparent banners encode
    // to, so when the ladder overshoots [hardMaxBytes] we downscale and retry
    // until it fits or we reach the floor.
    var prepared = _resizeDown(centerCropToThreeToOne(decoded));

    Uint8List? smallest;
    while (true) {
      final encoded = await _encodeBestQuality(prepared);
      if (encoded != null) {
        if (smallest == null || encoded.length < smallest.length) {
          smallest = encoded;
        }
        if (encoded.length <= hardMaxBytes) {
          return encoded;
        }
      }

      final downscaled = _downscaleTowardFloor(prepared);
      if (downscaled == null) break;
      prepared = downscaled;
    }

    if (smallest == null) {
      throw StateError('Profile header WebP encoder returned no bytes');
    }
    // Floor reached and still over budget: return the smallest rather than fail.
    return smallest;
  }

  /// Runs the quality ladder once, returning the smallest encoding and stopping
  /// early once one is within [targetMaxBytes]. Null only if nothing encoded.
  Future<Uint8List?> _encodeBestQuality(img.Image image) async {
    Uint8List? smallest;
    for (final quality in _webpQualities) {
      final encoded = await _encoder.encode(image, quality: quality);
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
