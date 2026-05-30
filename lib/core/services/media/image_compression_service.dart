import 'dart:isolate';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart' as img;
import 'package:prism_sync/generated/api.dart' as ffi;

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
  static const _maxDimension = 2048;
  static const _quality = 85;
  static const _thumbnailMaxDimension = 300;
  static const _maxAnimatedBytes = 5 * 1024 * 1024; // 5 MB

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
    if (decoded == null) {
      throw ArgumentError('Unable to decode image');
    }

    final sourceWidth = decoded.width;
    final sourceHeight = decoded.height;

    int targetWidth;
    int targetHeight;
    if (sourceWidth > sourceHeight) {
      targetWidth = sourceWidth > _maxDimension ? _maxDimension : sourceWidth;
      targetHeight = (sourceHeight * targetWidth / sourceWidth).round();
    } else {
      targetHeight = sourceHeight > _maxDimension ? _maxDimension : sourceHeight;
      targetWidth = (sourceWidth * targetHeight / sourceHeight).round();
    }

    // Encode via Rust FFI — auto-selects format:
    //   has alpha → lossless WebP (art/banners/dividers)
    //   no alpha  → JPEG at _quality (photos)
    final (compressed, mimeType) = await ffi.encodeImage(
      imageBytes: source,
      maxWidth: targetWidth,
      maxHeight: targetHeight,
      quality: _quality,
    );

    final blurhash = await _computeBlurhashFromImage(decoded);

    return CompressedImage(
      bytes: compressed,
      width: targetWidth,
      height: targetHeight,
      blurhash: blurhash,
      mimeType: mimeType,
    );
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

    // Decode first frame for dimensions and blurhash.
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      throw ArgumentError('Unable to decode animated image');
    }

    final blurhash = await _computeBlurhashFromImage(decoded);

    return CompressedImage(
      bytes: source,
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

  Future<Uint8List> generateThumbnail(Uint8List source, {img.Image? decoded}) async {
    decoded ??= img.decodeImage(source);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image');
    }

    final sourceWidth = decoded.width;
    final sourceHeight = decoded.height;

    int targetWidth;
    int targetHeight;
    if (sourceWidth > sourceHeight) {
      targetWidth = sourceWidth > _thumbnailMaxDimension
          ? _thumbnailMaxDimension
          : sourceWidth;
      targetHeight = (sourceHeight * targetWidth / sourceWidth).round();
    } else {
      targetHeight = sourceHeight > _thumbnailMaxDimension
          ? _thumbnailMaxDimension
          : sourceHeight;
      targetWidth = (sourceWidth * targetHeight / sourceHeight).round();
    }

    final (bytes, _) = await ffi.encodeImage(
      imageBytes: source,
      maxWidth: targetWidth,
      maxHeight: targetHeight,
      quality: _quality,
    );
    return bytes;
  }

  static Future<String> _computeBlurhashFromImage(img.Image decoded) {
    // Resize to the tiny (width:32) blurhash input on the CALLING isolate so
    // we only ship a ~32px image across the isolate boundary, not the full
    // decoded bitmap (~16 MB for a 2048² source). The encode is unchanged —
    // BlurHash.encode still sees the same width:32 resize it did before.
    final small = img.copyResize(decoded, width: 32);
    return Isolate.run(() {
      return BlurHash.encode(
        small,
        numCompX: 4,
        numCompY: 3,
      ).hash;
    });
  }
}

class _AnimationInfo {
  final String mimeType;
  const _AnimationInfo({required this.mimeType});
}
