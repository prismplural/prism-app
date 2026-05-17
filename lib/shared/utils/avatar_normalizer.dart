import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Normalizes avatar images for small on-device display and cheap sync.
class AvatarNormalizer {
  AvatarNormalizer._();

  // Profile avatars render as large as 96 logical pixels in member headers.
  // On 3x/4x mobile screens, a 256px source has to upscale there. Match the
  // cropper output so newly cropped avatars stay crisp while still enforcing a
  // byte budget for sync.
  static const maxDimension = 512;
  static const targetMaxBytes = 256 * 1024;
  // Sized to stay within a single sync batch (~950KB target).
  static const gifMaxBytes = 1024 * 1024;
  static const _jpegQualities = <int>[85, 82, 78, 74, 68, 62, 56, 50];

  static Uint8List? normalize(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return bytes;

    // Oversized GIFs fall through to the JPEG path — animation lost but
    // the image still appears.
    if (_isGif(bytes) && bytes.length <= gifMaxBytes) {
      return bytes;
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unsupported avatar image format');
    }

    // Idempotent fast-path: if the input is already a JPEG within both the
    // dimension and byte budget, return it verbatim. The repository calls
    // normalize on every member write, including writes that don't touch the
    // avatar field — without this, JPEG-on-JPEG re-encoding accumulates
    // generation loss until the avatar visibly degrades.
    if (_isJpeg(bytes) &&
        bytes.length <= targetMaxBytes &&
        decoded.width <= maxDimension &&
        decoded.height <= maxDimension) {
      return bytes;
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

  static bool _isJpeg(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  static bool isAnimatedGifInput(Uint8List? bytes) {
    if (bytes == null) return false;
    return _isGif(bytes);
  }

  static bool _isGif(Uint8List bytes) {
    // GIF87a or GIF89a header.
    return bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
  }

  static img.Image _resize(img.Image source) {
    if (source.width <= maxDimension && source.height <= maxDimension) {
      return source;
    }

    // Average, not cubic — cubic aliases on a 3-4× downscale and JPEG locks
    // it in as visible blocking.
    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxDimension,
        interpolation: img.Interpolation.average,
      );
    }

    return img.copyResize(
      source,
      height: maxDimension,
      interpolation: img.Interpolation.average,
    );
  }
}
