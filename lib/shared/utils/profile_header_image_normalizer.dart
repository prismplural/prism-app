import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

abstract interface class ProfileHeaderWebpEncoder {
  Future<Uint8List> encode(img.Image image, {required int quality});
}

class FlutterProfileHeaderWebpEncoder implements ProfileHeaderWebpEncoder {
  const FlutterProfileHeaderWebpEncoder();

  @override
  Future<Uint8List> encode(img.Image image, {required int quality}) {
    return FlutterImageCompress.compressWithList(
      Uint8List.fromList(img.encodePng(image)),
      minWidth: image.width,
      minHeight: image.height,
      quality: quality,
      format: CompressFormat.webp,
    );
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

    final prepared = _resizeDown(_centerCropToThreeToOne(decoded));

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

  static img.Image _centerCropToThreeToOne(img.Image source) {
    final currentRatio = source.width / source.height;
    const targetRatio = 3.0;

    if ((currentRatio - targetRatio).abs() < 0.0001) {
      return source;
    }

    if (currentRatio > targetRatio) {
      final cropWidth = (source.height * targetRatio).round();
      final x = ((source.width - cropWidth) / 2).round();
      return img.copyCrop(
        source,
        x: x,
        y: 0,
        width: cropWidth,
        height: source.height,
      );
    }

    final cropHeight = (source.width / targetRatio).round();
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

    return img.copyResize(
      source,
      width: maxWidth,
      height: maxHeight,
      interpolation: img.Interpolation.cubic,
    );
  }
}

Future<Uint8List> normalizeProfileHeaderImage(
  Uint8List input, {
  ProfileHeaderWebpEncoder encoder = const FlutterProfileHeaderWebpEncoder(),
}) {
  return ProfileHeaderImageNormalizer(encoder: encoder).normalize(input);
}
