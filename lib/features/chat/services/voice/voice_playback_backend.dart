import 'package:flutter/foundation.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

class VoicePlaybackBackendState {
  const VoicePlaybackBackendState({
    this.mediaId,
    this.status = VoicePlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.errorMessage,
  });

  final String? mediaId;
  final VoicePlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? errorMessage;

  VoicePlaybackBackendState copyWith({
    String? mediaId,
    bool clearMediaId = false,
    VoicePlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? speed,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return VoicePlaybackBackendState(
      mediaId: clearMediaId ? null : (mediaId ?? this.mediaId),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

abstract interface class VoicePlaybackBackend {
  ValueListenable<VoicePlaybackBackendState> get state;

  Future<void> load(VoicePlaybackSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<double> cycleSpeed();
  Future<void> dispose();
}

double nextVoicePlaybackSpeed(double currentSpeed) {
  return switch (currentSpeed) {
    1.0 => 1.5,
    1.5 => 2.0,
    _ => 1.0,
  };
}
