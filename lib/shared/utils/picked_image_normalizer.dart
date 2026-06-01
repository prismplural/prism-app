import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:platform_image_converter/platform_image_converter.dart';

const int _maxDimension = 4096;
const int _quality = 92;

/// Re-encodes picker output into bytes the cropper can decode reliably.
///
/// iOS uses ImageIO for large/wide-gamut picker output. Windows/Linux use the
/// Dart decoder to canonicalize PNGs before they reach Flutter's image codec.
Future<Uint8List?> normalizePickedImageBytes(
  Uint8List sourceBytes, {
  TargetPlatform? platform,
}) async {
  if (sourceBytes.isEmpty) return null;
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (_usesNativeConverter(resolvedPlatform)) {
    try {
      return await ImageConverter.convert(
        inputData: sourceBytes,
        format: OutputFormat.jpeg,
        quality: _quality,
        resizeMode: const FitResizeMode(
          width: _maxDimension,
          height: _maxDimension,
        ),
      );
    } catch (_) {
      return sourceBytes;
    }
  }
  if (_usesDartConverter(resolvedPlatform)) {
    return compute(_normalizePickedImageBytesWithDart, sourceBytes);
  }
  return sourceBytes;
}

bool _usesNativeConverter(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

bool _usesDartConverter(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.linux || TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => false,
  };
}

Uint8List? _normalizePickedImageBytesWithDart(Uint8List sourceBytes) {
  try {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    final firstFrame = decoded
        .getFrame(0)
        .convert(format: img.Format.uint8, numChannels: 4);
    final prepared = _resizeForCropper(firstFrame);
    return Uint8List.fromList(img.encodePng(prepared));
  } catch (_) {
    return null;
  }
}

img.Image _resizeForCropper(img.Image source) {
  if (source.width <= _maxDimension && source.height <= _maxDimension) {
    return source;
  }
  if (source.width >= source.height) {
    return img.copyResize(
      source,
      width: _maxDimension,
      interpolation: img.Interpolation.average,
    );
  }
  return img.copyResize(
    source,
    height: _maxDimension,
    interpolation: img.Interpolation.average,
  );
}
