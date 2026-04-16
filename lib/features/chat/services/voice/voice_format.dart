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
      codec: _detectCafCodec(bytes),
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

/// Detects whether a CAF file contains Opus audio by checking the
/// `mFormatID` field in the Audio Description (`desc`) chunk.
///
/// CAF layout: 8-byte file header, then chunks (12-byte chunk header each).
/// The `desc` chunk's `mFormatID` sits at offset 8 (mSampleRate) into the
/// chunk data — absolute byte 28 when `desc` is the first chunk (typical).
/// Falls back to scanning the first 64 bytes for the `opus` FourCC.
VoiceCodec _detectCafCodec(Uint8List bytes) {
  // Fast path: desc chunk at expected position, mFormatID at byte 28.
  if (bytes.length >= 32 && _hasAsciiAt(bytes, 28, 'opus')) {
    return VoiceCodec.opus;
  }

  // Fallback: scan first 64 bytes for the `opus` FourCC in case the
  // desc chunk isn't at the standard offset.
  final scanLimit = bytes.length < 64 ? bytes.length : 64;
  for (var i = 8; i <= scanLimit - 4; i++) {
    if (_hasAsciiAt(bytes, i, 'opus')) {
      return VoiceCodec.opus;
    }
  }

  return VoiceCodec.unknown;
}

bool _hasAsciiAt(Uint8List bytes, int offset, String ascii) {
  if (offset + ascii.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[offset + i] != ascii.codeUnitAt(i)) {
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
