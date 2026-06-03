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
    // Profile headers are always opaque (no alpha) so this produces JPEG,
    // which is fine — the caller iterates quality levels to hit size targets.
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

  final ProfileHeaderWebpEncoder _encoder;

  Future<Uint8List> normalize(Uint8List input) async {
    if (input.isEmpty) {
      throw ArgumentError('Profile header image input is empty');
    }

    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw ArgumentError('Unable to decode profile header image');
    }

    final prepared = _resizeDown(centerCropToThreeToOne(decoded));

    Uint8List? smallest;
    for (final quality in _webpQualities) {
      final encoded = await _encoder.encode(prepared, quality: quality);
      if (encoded.isEmpty) continue;
      if (smallest == null || encoded.length < smallest.length) {
        smallest = encoded;
      }
      if (encoded.length <= targetMaxBytes) {
        return encoded;
      }
    }

    if (smallest == null) {
      throw StateError('Profile header WebP encoder returned no bytes');
    }
    if (smallest.length > hardMaxBytes) {
      throw StateError('Normalized profile header exceeds hard byte limit');
    }

    return smallest;
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
