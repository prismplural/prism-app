import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/core/sharing/field_template_codec.dart'
    show kMaxTemplateCodeChars;
import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/shared/services/desktop_qr_decoder_stub.dart'
    if (dart.library.io) 'package:prism_plurality/shared/services/desktop_qr_decoder.dart'
    as desktop_qr;

const kTemplateImageExtensions = <String>['png', 'jpg', 'jpeg'];
const kMaxTemplateImageBytes = 16 * 1024 * 1024;

// Bounds RGBA allocation for compressed images with very large dimensions.
const kMaxTemplateImagePixels = 24 * 1000 * 1000;

typedef ImageFilePathQrDecoder = Future<String?> Function(String path);
typedef VisibleQrDecoder = Future<String?> Function(Uint8List bytes);

/// Reads a field-template code from PNG metadata or a visible QR code.
class TemplateImageCodeReader {
  TemplateImageCodeReader({
    TargetPlatform? platform,
    ImageFilePathQrDecoder? decodeFilePath,
    VisibleQrDecoder? decodeVisibleQr,
  }) : _platform = platform ?? defaultTargetPlatform,
       _decodeFilePath = decodeFilePath ?? _analyzeImageFile,
       _decodeVisibleQr = decodeVisibleQr ?? decodeTemplateVisibleQr;

  final TargetPlatform _platform;
  final ImageFilePathQrDecoder _decodeFilePath;
  final VisibleQrDecoder _decodeVisibleQr;

  Uint8List? _cachedInput;
  String? _cachedPath;
  String? _cachedCode;

  bool get _isMobile => switch (_platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  Future<String?> read(Uint8List bytes, {String? path}) async {
    if (bytes.isEmpty || bytes.length > kMaxTemplateImageBytes) return null;
    if (identical(_cachedInput, bytes) && _cachedPath == path) {
      return _cachedCode;
    }

    final code = await _resolve(bytes, path: path);
    _cachedInput = bytes;
    _cachedPath = path;
    _cachedCode = code;
    return code;
  }

  Future<String?> _resolve(Uint8List bytes, {String? path}) async {
    // Probe before metadata extraction because PNG metadata decoding can
    // otherwise allocate the full image before dimensions are validated.
    final header = _probeHeader(bytes);
    if (header == null) return null;

    final embedded = _embeddedCode(header);
    if (embedded != null) return embedded;

    if (_isMobile && path != null) {
      final fromPlatform = await _tryDecode(() => _decodeFilePath(path));
      if (fromPlatform != null) return fromPlatform;
    }

    return _tryDecode(() => _decodeVisibleQr(bytes));
  }

  static String? _embeddedCode(img.DecodeInfo info) {
    if (info is! img.PngInfo) return null;
    final code = info.textData[kTemplateTextKey];
    if (code == null || code.length > kMaxTemplateCodeChars) return null;
    return code;
  }

  static Future<String?> _tryDecode(Future<String?> Function() decode) async {
    try {
      return await decode();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _analyzeImageFile(String path) async {
    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      return capture?.barcodes.firstOrNull?.rawValue;
    } finally {
      await controller.dispose();
    }
  }
}

Future<String?> decodeTemplateVisibleQr(Uint8List bytes) {
  return compute(_decodeVisibleQrFromBytes, bytes);
}

@visibleForTesting
Future<String?> decodeTemplateVisibleQrOnCurrentIsolate(Uint8List bytes) {
  return _decodeVisibleQrFromBytes(bytes);
}

img.DecodeInfo? _probeHeader(Uint8List bytes) {
  try {
    final probe = img.findDecoderForData(bytes);
    if (probe == null) return null;
    final info = probe.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    if (info.width * info.height > kMaxTemplateImagePixels) return null;
    return info;
  } catch (_) {
    return null;
  }
}

Future<String?> _decodeVisibleQrFromBytes(Uint8List bytes) async {
  if (_probeHeader(bytes) == null) return null;

  final img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (image == null || image.width <= 0 || image.height <= 0) return null;
  if (image.width * image.height > kMaxTemplateImagePixels) return null;

  final Uint8List rgba;
  try {
    rgba = image.getBytes(order: img.ChannelOrder.rgba);
  } catch (_) {
    return null;
  }
  return desktop_qr.decodeDesktopQr(rgba, image.width, image.height);
}

final templateImageCodeReaderProvider = Provider<TemplateImageCodeReader>(
  (ref) => TemplateImageCodeReader(),
);
