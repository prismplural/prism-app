import 'dart:typed_data';

enum VoiceContainer { ogg, caf, unknown }

enum VoiceCodec { opus, unknown }

enum VoicePlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
}

class VoiceFormatDescriptor {
  const VoiceFormatDescriptor({
    required this.container,
    required this.codec,
    required this.mimeType,
  });

  final VoiceContainer container;
  final VoiceCodec codec;
  final String mimeType;

  bool get isOggOpus =>
      container == VoiceContainer.ogg && codec == VoiceCodec.opus;
  bool get isCafOpus =>
      container == VoiceContainer.caf && codec == VoiceCodec.opus;
  bool get needsRemuxBeforeUpload => isCafOpus;
  bool get canUseBufferStream => isOggOpus;

  String get containerLabel {
    return switch ((container, codec)) {
      (VoiceContainer.ogg, VoiceCodec.opus) => 'Ogg Opus',
      (VoiceContainer.ogg, _) => 'Ogg',
      (VoiceContainer.caf, VoiceCodec.opus) => 'CAF Opus',
      (VoiceContainer.caf, _) => 'CAF',
      (VoiceContainer.unknown, VoiceCodec.opus) => 'Opus (unknown container)',
      _ => 'Unknown',
    };
  }
}

class VoiceCaptureArtifact {
  const VoiceCaptureArtifact({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
    required this.waveformB64,
    this.debugBackend,
  });

  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  final String waveformB64;
  final String? debugBackend;
}

class VoicePlaybackSource {
  VoicePlaybackSource.bytes({
    required this.bytes,
    required this.mimeType,
    required this.mediaId,
  }) : filePath = null;

  const VoicePlaybackSource.file({
    required this.filePath,
    required this.mimeType,
    required this.mediaId,
  }) : bytes = null;

  final Uint8List? bytes;
  final String? filePath;
  final String mimeType;
  final String mediaId;

  bool get isMemoryBacked => bytes != null;
}

class VoiceRecorderCapabilities {
  const VoiceRecorderCapabilities({
    required this.isSupported,
    required this.needsCafToOggRemux,
    required this.outputFileExtension,
    required this.sourceContainerLabel,
    required this.normalizedContainerLabel,
    required this.summary,
    this.unsupportedReason,
  });

  const VoiceRecorderCapabilities.unsupported({
    required this.unsupportedReason,
    required this.summary,
  }) : isSupported = false,
       needsCafToOggRemux = false,
       outputFileExtension = 'opus',
       sourceContainerLabel = 'Unavailable',
       normalizedContainerLabel = 'Unavailable';

  final bool isSupported;
  final bool needsCafToOggRemux;
  final String outputFileExtension;
  final String sourceContainerLabel;
  final String normalizedContainerLabel;
  final String summary;
  final String? unsupportedReason;
}
