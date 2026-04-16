import 'dart:typed_data';

import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

const _oggMimeType = 'audio/ogg';
const _cafMimeType = 'audio/x-caf';
const _unknownMimeType = 'application/octet-stream';

VoiceFormatDescriptor detectVoiceFormat(
  Uint8List bytes, {
  String? fallbackMimeType,
}) {
  final safeFallbackMimeType = _normalizeMimeType(fallbackMimeType);

  if (_hasPrefix(bytes, 'OggS')) {
    if (_containsAscii(bytes, 'OpusHead')) {
      return const VoiceFormatDescriptor(
        container: VoiceContainer.ogg,
        codec: VoiceCodec.opus,
        mimeType: _oggMimeType,
      );
    }

    return VoiceFormatDescriptor(
      container: VoiceContainer.ogg,
      codec: VoiceCodec.unknown,
      mimeType: safeFallbackMimeType ?? _unknownMimeType,
    );
  }

  if (_hasPrefix(bytes, 'caff')) {
    return VoiceFormatDescriptor(
      container: VoiceContainer.caf,
      codec: _containsAscii(bytes, 'OpusHead')
          ? VoiceCodec.opus
          : VoiceCodec.unknown,
      mimeType: _cafMimeType,
    );
  }

  if (_containsAscii(bytes, 'OpusHead')) {
    return VoiceFormatDescriptor(
      container: VoiceContainer.unknown,
      codec: VoiceCodec.opus,
      mimeType: safeFallbackMimeType ?? _unknownMimeType,
    );
  }

  return VoiceFormatDescriptor(
    container: VoiceContainer.unknown,
    codec: VoiceCodec.unknown,
    mimeType: safeFallbackMimeType ?? _unknownMimeType,
  );
}

String detectVoiceContainerLabel(Uint8List bytes) {
  return detectVoiceFormat(bytes).containerLabel;
}

String resolveVoiceMimeType(Uint8List bytes, {String? fallbackMimeType}) {
  return detectVoiceFormat(bytes, fallbackMimeType: fallbackMimeType).mimeType;
}

bool isValidatedOggOpus(Uint8List bytes) {
  return detectVoiceFormat(bytes).isOggOpus;
}

String? _normalizeMimeType(String? mimeType) {
  final normalized = mimeType?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

bool _hasPrefix(Uint8List bytes, String prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }

  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix.codeUnitAt(i)) {
      return false;
    }
  }

  return true;
}

bool _containsAscii(Uint8List bytes, String needle) {
  if (needle.isEmpty || bytes.length < needle.length) {
    return false;
  }

  for (var start = 0; start <= bytes.length - needle.length; start++) {
    var matches = true;
    for (var i = 0; i < needle.length; i++) {
      if (bytes[start + i] != needle.codeUnitAt(i)) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }

  return false;
}
