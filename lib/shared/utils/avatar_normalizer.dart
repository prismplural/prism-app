import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Normalizes avatar images for small on-device display and cheap sync.
class AvatarNormalizer {
  AvatarNormalizer._();

  static const maxDimension = 256;
  static const targetMaxBytes = 96 * 1024;
  static const _jpegQualities = <int>[82, 74, 66, 58, 50];

  static Uint8List? normalize(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return bytes;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unsupported avatar image format');
    }

    final resized = _resize(decoded);

    Uint8List? bestEffort;
    for (final quality in _jpegQualities) {
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      bestEffort = encoded;
      if (encoded.length <= targetMaxBytes) {
        return encoded;
      }
    }

    return bestEffort;
  }

  static img.Image _resize(img.Image source) {
    if (source.width <= maxDimension && source.height <= maxDimension) {
      return source;
    }

    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxDimension,
        interpolation: img.Interpolation.cubic,
      );
    }

    return img.copyResize(
      source,
      height: maxDimension,
      interpolation: img.Interpolation.cubic,
    );
  }
}
