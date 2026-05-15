import 'package:flutter/foundation.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

const int _maxDimension = 4096;
const int _quality = 92;

/// Re-encodes picker output through the platform's native image decoder
/// (CGImageSource on iOS) before it reaches Flutter's in-process decoder.
///
/// Why: `image_picker_ios` calls `UIImageJPEGRepresentation(image, 1.0)` on
/// the way out, which produces 30–50 MB JPEGs for modern iPhone originals
/// (24–48 MP, wide-gamut Display-P3). Those bytes can choke `Image.memory`
/// inside the cropper — the image stream listener never fires, the crop
/// screen renders blank, and the user sees "Could not process that image"
/// on Done.
///
/// Returns the original bytes unchanged on non-iOS platforms or when the
/// platform converter throws — the cropper still gets a chance to handle
/// them. Returns null only for empty input, which is a separate failure
/// mode (`UIImage initWithData:` returning nil → empty .jpg) that the
/// caller should surface as an error.
Future<Uint8List?> normalizePickedImageBytes(
  Uint8List sourceBytes, {
  TargetPlatform? platform,
}) async {
  if (sourceBytes.isEmpty) return null;
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (resolvedPlatform != TargetPlatform.iOS) return sourceBytes;
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
