import 'dart:isolate';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

class CompressedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final String blurhash;
  final Uint8List? thumbnailBytes;

  const CompressedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.blurhash,
    this.thumbnailBytes,
  });
}

class ImageCompressionService {
  static const _maxDimension = 2048;
  static const _quality = 78;
  static const _thumbnailMaxDimension = 300;
  static const _thumbnailQuality = 65;

  Future<CompressedImage> compressImage(Uint8List source) async {
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

    final compressed = await FlutterImageCompress.compressWithList(
      source,
      minWidth: targetWidth,
      minHeight: targetHeight,
      quality: _quality,
      format: CompressFormat.webp,
    );

    final compressedDecoded = img.decodeImage(compressed);
    final finalWidth = compressedDecoded?.width ?? targetWidth;
    final finalHeight = compressedDecoded?.height ?? targetHeight;

    final blurhash = await _computeBlurhash(source);

    return CompressedImage(
      bytes: compressed,
      width: finalWidth,
      height: finalHeight,
      blurhash: blurhash,
    );
  }

  Future<Uint8List> generateThumbnail(Uint8List source) async {
    final decoded = img.decodeImage(source);
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

    return FlutterImageCompress.compressWithList(
      source,
      minWidth: targetWidth,
      minHeight: targetHeight,
      quality: _thumbnailQuality,
      format: CompressFormat.webp,
    );
  }

  static Future<String> _computeBlurhash(Uint8List imageBytes) {
    return Isolate.run(() {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        throw ArgumentError('Unable to decode image for blurhash');
      }

      final small = img.copyResize(decoded, width: 32);

      return BlurHash.encode(
        small,
        numCompX: 4,
        numCompY: 3,
      ).hash;
    });
  }
}
