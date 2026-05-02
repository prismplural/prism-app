import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-owned clipboard reader used by UI surfaces that need richer clipboard
/// content than Flutter's text-only [Clipboard] helper exposes.
final appClipboardReaderProvider = Provider<AppClipboardReader>(
  (ref) => const MethodChannelAppClipboardReader(),
);

enum ClipboardPasteboard {
  /// The normal platform clipboard used by Cmd/Ctrl+V and paste menu actions.
  clipboard('clipboard'),

  /// The X11/GTK primary selection used by middle-click paste on Linux.
  /// Platforms without this pasteboard return null.
  primarySelection('primarySelection');

  const ClipboardPasteboard(this.platformValue);

  final String platformValue;
}

class ClipboardImageData {
  const ClipboardImageData({
    required this.bytes,
    this.mimeType,
    this.sourceUri,
    this.pasteboard = ClipboardPasteboard.clipboard,
  });

  final Uint8List bytes;
  final String? mimeType;
  final String? sourceUri;
  final ClipboardPasteboard pasteboard;
}

abstract interface class AppClipboardReader {
  Future<ClipboardImageData?> readImage({
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
  });

  Future<ClipboardImageData?> readImageUri(String uri);
}

class MethodChannelAppClipboardReader implements AppClipboardReader {
  const MethodChannelAppClipboardReader({
    MethodChannel channel = platformChannel,
  }) : _channel = channel;

  static const MethodChannel platformChannel = MethodChannel(
    'com.prism.prism_plurality/app_clipboard',
  );

  final MethodChannel _channel;

  @override
  Future<ClipboardImageData?> readImage({
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
  }) async {
    final payload = await _invoke('readImage', <String, Object?>{
      'pasteboard': pasteboard.platformValue,
    });
    return _decodeImagePayload(payload, pasteboard: pasteboard);
  }

  @override
  Future<ClipboardImageData?> readImageUri(String uri) async {
    if (uri.isEmpty) return null;
    final payload = await _invoke('readImageUri', <String, Object?>{
      'uri': uri,
    });
    return _decodeImagePayload(payload, sourceUri: uri);
  }

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  ClipboardImageData? _decodeImagePayload(
    Object? payload, {
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
    String? sourceUri,
  }) {
    final topLevelBytes = _bytesFromPayload(payload);
    if (topLevelBytes != null) {
      return _fromBytes(
        topLevelBytes,
        pasteboard: pasteboard,
        sourceUri: sourceUri,
      );
    }

    if (payload is Map) {
      final decoded = _bytesFromPayload(payload['bytes']);
      if (decoded == null) return null;
      final payloadSourceUri = payload['sourceUri'];
      final payloadMimeType = payload['mimeType'];
      return _fromBytes(
        decoded,
        pasteboard: pasteboard,
        sourceUri: payloadSourceUri is String ? payloadSourceUri : sourceUri,
        mimeType: payloadMimeType is String ? payloadMimeType : null,
      );
    }
    return null;
  }

  Uint8List? _bytesFromPayload(Object? payload) {
    if (payload is Uint8List) return payload;
    if (payload is ByteData) {
      return payload.buffer.asUint8List(
        payload.offsetInBytes,
        payload.lengthInBytes,
      );
    }
    if (payload is List<int>) return Uint8List.fromList(payload);
    return null;
  }

  ClipboardImageData? _fromBytes(
    Uint8List bytes, {
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
    String? sourceUri,
    String? mimeType,
  }) {
    if (bytes.isEmpty) return null;
    return ClipboardImageData(
      bytes: bytes,
      mimeType: mimeType,
      sourceUri: sourceUri,
      pasteboard: pasteboard,
    );
  }
}
