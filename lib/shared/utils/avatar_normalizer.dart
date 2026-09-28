import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
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
    if (_isConforming(bytes)) return bytes;
    return _reencode(bytes);
  }

  /// Header-only probe so we can reject oversized images before
  /// img.decodeImage allocates the RGBA buffer, then the idempotent
  /// fast-path: a JPEG already within both the dimension and byte budget is
  /// returned verbatim, skipping the multi-hundred-millisecond decode (and
  /// JPEG-on-JPEG generation loss) on every member write.
  static bool _isConforming(Uint8List bytes) {
    // The probe instance can't be reused for the real decode — PngDecoder
    // accumulates IDAT offsets across startDecode calls, doubling the zlib
    // working set the second time through. img.decodeImage builds a fresh
    // decoder.
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
    return _isJpeg(bytes) &&
        bytes.length <= targetMaxBytes &&
        info.width <= maxDimension &&
        info.height <= maxDimension;
  }

  static Uint8List? _reencode(Uint8List bytes) {
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

  /// Off-main-isolate single normalize — identical result to [normalize]. Use
  /// from any path that can `await` so the UI thread never stalls on a
  /// pure-Dart image decode. The header probe walks the whole file for PNG,
  /// GIF and large JPEG, so only an in-budget JPEG is probed inline; a
  /// conforming one then skips the isolate spawn.
  static Future<Uint8List?> normalizeOffMainIsolate(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return bytes;
    if (_isJpeg(bytes) && bytes.length <= targetMaxBytes) {
      if (_isConforming(bytes)) return bytes;
      return compute(_reencode, bytes);
    }
    return compute(normalize, bytes);
  }

  /// Off-main-isolate batch normalize — one background isolate for the whole
  /// list, for loops over many members (Simply Plural import, oversized-inline
  /// re-emit) where inline decode ANR'd. Output order matches input, null maps
  /// to null, and an undecodable member throws — same contract as [normalize].
  static Future<List<Uint8List?>> normalizeBatch(List<Uint8List?> images) {
    if (images.isEmpty) return Future<List<Uint8List?>>.value(const []);
    return compute(_normalizeBatch, images);
  }

  static List<Uint8List?> _normalizeBatch(List<Uint8List?> images) =>
      [for (final bytes in images) normalize(bytes)];

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
