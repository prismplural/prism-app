import 'dart:isolate';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

typedef ImageEncoder =
    Future<(Uint8List, String)> Function({
      required List<int> imageBytes,
      required int maxWidth,
      required int maxHeight,
      required int quality,
    });

class CompressedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final String blurhash;
  final String mimeType;
  final Uint8List? thumbnailBytes;

  const CompressedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.blurhash,
    required this.mimeType,
    this.thumbnailBytes,
  });
}

class ImageCompressionService {
  ImageCompressionService({ImageEncoder? encodeImage})
    : _encodeImage = encodeImage ?? media_codec.encodeImage;

  static const _maxDimension = 2048;
  static const _quality = 85;
  static const _thumbnailMaxDimension = 300;
  static const _maxAnimatedBytes = 5 * 1024 * 1024; // 5 MB
  static const _gifTinyDelayThresholdCentiseconds = 1;
  static const _gifBrowserMinimumDelayCentiseconds = 10;

  final ImageEncoder _encodeImage;

  Future<CompressedImage> compressImage(Uint8List source) async {
    // Check for animated content — pass through without re-encoding to
    // preserve animation. Re-encoding would flatten to a single frame.
    final animInfo = _detectAnimation(source);
    if (animInfo != null) {
      return _handleAnimated(source, animInfo);
    }

    // Decode in Dart for dimension calculation and blurhash. The Rust side
    // will decode again for the actual resize + encode — the duplicate
    // decode is cheap compared to the encode step.
    final decoded = img.decodeImage(source);
    final (targetWidth, targetHeight) = decoded == null
        ? (_maxDimension, _maxDimension)
        : fitWithin(decoded.width, decoded.height, _maxDimension);

    // Encode via Rust FFI — auto-selects format:
    //   has alpha → lossless WebP (art/banners/dividers)
    //   no alpha  → JPEG at _quality (photos)
    final (compressed, mimeType) = await _encodeImage(
      imageBytes: source,
      maxWidth: targetWidth,
      maxHeight: targetHeight,
      quality: _quality,
    );

    final decodedForMetadata = decoded ?? img.decodeImage(compressed);
    if (decodedForMetadata == null) {
      throw ArgumentError('Unable to decode image');
    }

    final blurhash = await computeBlurhashFromImage(decodedForMetadata);

    return CompressedImage(
      bytes: compressed,
      width: decoded == null ? decodedForMetadata.width : targetWidth,
      height: decoded == null ? decodedForMetadata.height : targetHeight,
      blurhash: blurhash,
      mimeType: mimeType,
    );
  }

  /// Aspect-preserving target dimensions within [maxDimension]. Rejects
  /// non-positive sources (which would divide to NaN) and floors each axis at
  /// 1 (an extreme ratio can round the minor axis to 0).
  @visibleForTesting
  static (int, int) fitWithin(
    int sourceWidth,
    int sourceHeight,
    int maxDimension,
  ) {
    _ensureValidDimensions(sourceWidth, sourceHeight);

    final int targetWidth;
    final int targetHeight;
    if (sourceWidth > sourceHeight) {
      targetWidth = sourceWidth > maxDimension ? maxDimension : sourceWidth;
      targetHeight = (sourceHeight * targetWidth / sourceWidth).round();
    } else {
      targetHeight = sourceHeight > maxDimension ? maxDimension : sourceHeight;
      targetWidth = (sourceWidth * targetHeight / sourceHeight).round();
    }
    return (
      targetWidth < 1 ? 1 : targetWidth,
      targetHeight < 1 ? 1 : targetHeight,
    );
  }

  static void _ensureValidDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image has invalid dimensions (${width}x$height)');
    }
  }

  /// Pass animated images through without re-encoding. Computes blurhash
  /// from the first frame for the placeholder.
  Future<CompressedImage> _handleAnimated(
    Uint8List source,
    _AnimationInfo info,
  ) async {
    if (source.length > _maxAnimatedBytes) {
      throw ArgumentError(
        'Animated image is too large '
        '(${(source.length / (1024 * 1024)).toStringAsFixed(1)} MB, '
        'max ${_maxAnimatedBytes ~/ (1024 * 1024)} MB)',
      );
    }

    final bytes = info.mimeType == 'image/gif'
        ? _normalizeTinyGifFrameDelays(source)
        : source;

    // Decode first frame for dimensions and blurhash.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode animated image');
    }
    _ensureValidDimensions(decoded.width, decoded.height);

    final blurhash = await computeBlurhashFromImage(decoded);

    return CompressedImage(
      bytes: bytes,
      width: decoded.width,
      height: decoded.height,
      blurhash: blurhash,
      mimeType: info.mimeType,
    );
  }

  /// Detect animated GIF or animated WebP. Returns null for static images.
  static _AnimationInfo? _detectAnimation(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // GIF: "GIF87a" / "GIF89a".
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return _isAnimatedGif(bytes)
          ? const _AnimationInfo(mimeType: 'image/gif')
          : null;
    }

    // WebP: "RIFF"…"WEBP". Animation is signalled by the 'A' flag in the
    // VP8X extended-format chunk, not by scanning for the literal bytes
    // "ANIM" (which can appear in pixel data of a static image).
    if (bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // A simple (lossy/lossless) WebP has no VP8X chunk and cannot animate.
      // Extended format: chunk FourCC "VP8X" at offset 12, flags byte at 20.
      if (bytes.length >= 21 &&
          bytes[12] == 0x56 && // V
          bytes[13] == 0x50 && // P
          bytes[14] == 0x38 && // 8
          bytes[15] == 0x58 && // X
          (bytes[20] & 0x02) != 0) {
        return const _AnimationInfo(mimeType: 'image/webp');
      }
    }

    return null;
  }

  /// Walk the GIF block structure and return true only if it contains more
  /// than one image descriptor (i.e. is actually animated). Counting raw
  /// `0x2C` bytes is wrong — that value occurs freely inside color tables and
  /// LZW-compressed pixel data, so static GIFs were being misclassified as
  /// animated and passed through un-recompressed.
  static bool _isAnimatedGif(Uint8List b) {
    // Header (6) + Logical Screen Descriptor (7) = 13 bytes minimum.
    if (b.length < 13) return false;

    var pos = 6;
    final packed = b[pos + 4];
    final hasGct = (packed & 0x80) != 0;
    final gctSize = hasGct ? 3 * (1 << ((packed & 0x07) + 1)) : 0;
    pos += 7 + gctSize;

    var frames = 0;
    while (pos < b.length) {
      final block = b[pos];
      if (block == 0x3B) break; // trailer
      if (block == 0x2C) {
        // Image Descriptor: separator + 9 bytes (last is packed flags).
        frames++;
        if (frames > 1) return true;
        if (pos + 10 > b.length) break;
        final imgPacked = b[pos + 9];
        final hasLct = (imgPacked & 0x80) != 0;
        final lctSize = hasLct ? 3 * (1 << ((imgPacked & 0x07) + 1)) : 0;
        pos += 10 + lctSize;
        if (pos >= b.length) break;
        pos += 1; // LZW minimum code size
        pos = _skipGifSubBlocks(b, pos);
      } else if (block == 0x21) {
        // Extension: introducer + label, then sub-blocks.
        pos += 2;
        pos = _skipGifSubBlocks(b, pos);
      } else {
        break; // malformed / unknown — treat as static
      }
    }
    return false;
  }

  /// Firefox and other browsers clamp zero/10ms GIF frame delays up to 100ms.
  /// Flutter does not, so preserving literal 0cs/1cs delays can turn otherwise
  /// normal-looking browser GIFs into rapid flashing in Prism.
  static Uint8List _normalizeTinyGifFrameDelays(Uint8List source) {
    // Header (6) + Logical Screen Descriptor (7) = 13 bytes minimum.
    if (source.length < 13) return source;

    var pos = 6;
    final packed = source[pos + 4];
    final hasGct = (packed & 0x80) != 0;
    final gctSize = hasGct ? 3 * (1 << ((packed & 0x07) + 1)) : 0;
    pos += 7 + gctSize;

    Uint8List? normalized;
    while (pos < source.length) {
      final block = source[pos];
      if (block == 0x3B) break; // trailer
      if (block == 0x2C) {
        if (pos + 10 > source.length) break;
        final imgPacked = source[pos + 9];
        final hasLct = (imgPacked & 0x80) != 0;
        final lctSize = hasLct ? 3 * (1 << ((imgPacked & 0x07) + 1)) : 0;
        pos += 10 + lctSize;
        if (pos >= source.length) break;
        pos += 1; // LZW minimum code size
        pos = _skipGifSubBlocks(source, pos);
      } else if (block == 0x21) {
        if (pos + 2 > source.length) break;
        final label = source[pos + 1];
        if (label == 0xF9 && pos + 6 <= source.length && source[pos + 2] == 4) {
          final delayOffset = pos + 4;
          final delay = source[delayOffset] | (source[delayOffset + 1] << 8);
          if (delay <= _gifTinyDelayThresholdCentiseconds) {
            normalized ??= Uint8List.fromList(source);
            normalized[delayOffset] =
                _gifBrowserMinimumDelayCentiseconds & 0xFF;
            normalized[delayOffset + 1] =
                _gifBrowserMinimumDelayCentiseconds >> 8;
          }
        }
        pos += 2;
        pos = _skipGifSubBlocks(source, pos);
      } else {
        break; // malformed / unknown — leave bytes as-is
      }
    }
    return normalized ?? source;
  }

  /// Skip a run of GIF sub-blocks (each: 1 length byte + that many bytes),
  /// terminated by a zero-length block. Returns the position after the
  /// terminator.
  static int _skipGifSubBlocks(Uint8List b, int pos) {
    while (pos < b.length) {
      final size = b[pos];
      pos += 1;
      if (size == 0) break;
      pos += size;
    }
    return pos;
  }

  Future<Uint8List> generateThumbnail(
    Uint8List source, {
    img.Image? decoded,
  }) async {
    decoded ??= img.decodeImage(source);
    if (decoded == null) {
      final (bytes, _) = await _encodeImage(
        imageBytes: source,
        maxWidth: _thumbnailMaxDimension,
        maxHeight: _thumbnailMaxDimension,
        quality: _quality,
      );
      return bytes;
    }

    final (targetWidth, targetHeight) = fitWithin(
      decoded.width,
      decoded.height,
      _thumbnailMaxDimension,
    );

    final (bytes, _) = await _encodeImage(
      imageBytes: source,
      maxWidth: targetWidth,
      maxHeight: targetHeight,
      quality: _quality,
    );
    return bytes;
  }

  @visibleForTesting
  static Future<String> computeBlurhashFromImage(img.Image decoded) {
    // Resize on the CALLING isolate so we ship a ~32px image across the
    // isolate boundary, not the full bitmap. fitWithin (not a bare
    // copyResize(width: 32)) keeps both axes bounded and ≥1 — a fixed width
    // derives round(32*h/w), which is 0 for very wide images and millions of
    // rows for very tall ones.
    final (blurWidth, blurHeight) = fitWithin(
      decoded.width,
      decoded.height,
      32,
    );
    final small = img.copyResize(decoded, width: blurWidth, height: blurHeight);
    return Isolate.run(() {
      return BlurHash.encode(small, numCompX: 4, numCompY: 3).hash;
    });
  }
}

class _AnimationInfo {
  final String mimeType;
  const _AnimationInfo({required this.mimeType});
}
