import 'package:flutter/foundation.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_format.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

typedef VoiceLabCapability = VoiceRecorderCapabilities;

enum VoiceLabPlaybackMode { loadMem, bufferStream }

VoiceLabCapability buildVoiceLabCapability({
  required bool isWeb,
  required TargetPlatform platform,
  required bool opusRecordingSupported,
}) {
  if (isWeb) {
    return const VoiceLabCapability.unsupported(
      unsupportedReason: 'Web is out of scope for this debug spike.',
      summary: 'This spike targets native mobile and desktop builds only.',
    );
  }

  if (!opusRecordingSupported) {
    return const VoiceLabCapability.unsupported(
      unsupportedReason:
          'The current recorder backend does not advertise Opus output here.',
      summary:
          'This debug lab only runs on platforms where the recorder reports Opus support at runtime.',
    );
  }

  switch (platform) {
    case TargetPlatform.iOS:
      return const VoiceLabCapability(
        isSupported: true,
        needsCafToOggRemux: true,
        outputFileExtension: 'caf',
        sourceContainerLabel: 'CAF Opus',
        normalizedContainerLabel: 'Ogg Opus',
        summary:
            'Record native Opus in CAF, remux to Ogg Opus, then play from memory.',
      );
    case TargetPlatform.android:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return const VoiceLabCapability(
        isSupported: true,
        needsCafToOggRemux: false,
        outputFileExtension: 'opus',
        sourceContainerLabel: 'Ogg Opus',
        normalizedContainerLabel: 'Ogg Opus',
        summary:
            'Record Opus directly, then play the resulting Ogg bytes from memory.',
      );
    case TargetPlatform.macOS:
      return const VoiceLabCapability.unsupported(
        unsupportedReason:
            'macOS is excluded from this spike because the current recorder docs still do not give us a clean Opus path to trust.',
        summary:
            'Desktop production work can still use a Rust capture pipeline later without changing the app-facing contract.',
      );
    case TargetPlatform.fuchsia:
      return const VoiceLabCapability.unsupported(
        unsupportedReason: 'Fuchsia is not part of Prism’s target matrix.',
        summary: 'No debug spike support planned here.',
      );
  }
}

String detectVoiceLabContainer(Uint8List bytes) {
  return detectVoiceContainerLabel(bytes);
}

VoiceLabPlaybackMode chooseVoiceLabPlaybackMode(Uint8List bytes) {
  return detectVoiceFormat(bytes).canUseBufferStream
      ? VoiceLabPlaybackMode.bufferStream
      : VoiceLabPlaybackMode.loadMem;
}

String describeVoiceLabPlaybackMode(VoiceLabPlaybackMode mode) {
  return switch (mode) {
    VoiceLabPlaybackMode.loadMem => 'SoLoud.loadMem()',
    VoiceLabPlaybackMode.bufferStream => 'SoLoud.setBufferStream(auto)',
  };
}

String formatVoiceLabBytes(int byteCount) {
  if (byteCount < 1024) {
    return '$byteCount B';
  }
  if (byteCount < 1024 * 1024) {
    return '${(byteCount / 1024).toStringAsFixed(1)} KB';
  }
  return '${(byteCount / (1024 * 1024)).toStringAsFixed(2)} MB';
}
