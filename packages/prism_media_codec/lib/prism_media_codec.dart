import 'dart:typed_data';

import 'generated/api.dart' as generated;
import 'generated/frb_generated.dart';

export 'generated/api.dart' show codecHealthCheck;
export 'generated/frb_generated.dart' show MediaCodecRustLib;

const _unavailableMessage =
    'Image processing is unavailable. Please restart Prism and try again.';

Object? _initializationFailure;

/// Initializes the codec and retains failures for user-facing errors.
Future<void> initializeMediaCodec() async {
  try {
    await MediaCodecRustLib.init();
    _initializationFailure = null;
  } catch (error) {
    _initializationFailure = error;
    rethrow;
  }
}

class MediaCodecUnavailableException implements Exception {
  const MediaCodecUnavailableException();

  @override
  String toString() => _unavailableMessage;
}

Future<(Uint8List, String)> encodeImage({
  required List<int> imageBytes,
  required int maxWidth,
  required int maxHeight,
  required int quality,
}) async {
  if (_initializationFailure != null) {
    throw const MediaCodecUnavailableException();
  }

  try {
    return await generated.encodeImage(
      imageBytes: imageBytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
  } on StateError catch (error) {
    if (error.toString().contains(
      'flutter_rust_bridge has not been initialized',
    )) {
      throw const MediaCodecUnavailableException();
    }
    rethrow;
  }
}
