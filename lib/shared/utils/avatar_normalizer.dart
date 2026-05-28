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
  static const _jpegQualities = <int>[85, 82, 78, 74, 68, 62, 56, 50];

  // Cap source pixel count before `img.decodeImage` allocates the full RGBA
  // buffer. A 5 MB PNG can declare 12000×12000 — decoding would allocate
  // ~576 MB and native-OOM the Android process. 24 MP keeps headroom for
  // 48 MP phone-camera selfies while bounding the worst case at ~96 MB.
  static const maxSourcePixels = 24 * 1000 * 1000;

  static Uint8List? normalize(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return bytes;

    // Header-only probe so we can reject oversized images before
    // img.decodeImage allocates the RGBA buffer. The probe instance can't
    // be reused for the real decode — PngDecoder accumulates IDAT offsets
    // across startDecode calls, doubling the zlib working set the second
    // time through. img.decodeImage builds a fresh decoder.
    final probe = img.findDecoderForData(bytes);
    if (probe == null) {
      throw StateError('Unsupported avatar image format');
    }
    final info = probe.startDecode(bytes);
    if (info == null) {
      throw StateError('Unsupported avatar image format');
    }
    if (info.width <= 0 || info.height <= 0) {
      throw StateError('Unsupported avatar image format');
    }
    if (info.width * info.height > maxSourcePixels) {
      throw StateError(
        'Avatar source image is too large to decode safely '
        '(${info.width}x${info.height})',
      );
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
