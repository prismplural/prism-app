import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/chat/services/voice/mobile_voice_playback_backend.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_playback_backend.dart';

final voicePlaybackBackendProvider = Provider<VoicePlaybackBackend>((ref) {
  final backend = MobileVoicePlaybackBackend();
  ref.onDispose(() {
    unawaited(backend.dispose());
  });
  return backend;
});

class VoicePlaybackState {
  const VoicePlaybackState({
    this.activeMediaId,
    this.status = VoicePlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.error,
  });

  final String? activeMediaId;
  final VoicePlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? error;

  bool get isPlaying => status == VoicePlaybackStatus.playing;
  bool get isLoading => status == VoicePlaybackStatus.loading;

  VoicePlaybackState copyWith({
    String? activeMediaId,
    bool clearActiveMediaId = false,
    VoicePlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? speed,
    String? error,
    bool clearError = false,
  }) {
    return VoicePlaybackState(
      activeMediaId: clearActiveMediaId
          ? null
          : (activeMediaId ?? this.activeMediaId),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class VoicePlaybackNotifier extends Notifier<VoicePlaybackState> {
  VoicePlaybackBackend? _backend;
  VoidCallback? _backendListener;

  @override
  VoicePlaybackState build() {
    final backend = ref.watch(voicePlaybackBackendProvider);
    if (!identical(_backend, backend)) {
      final previousBackend = _backend;
      final previousListener = _backendListener;
      if (previousBackend != null && previousListener != null) {
        previousBackend.state.removeListener(previousListener);
      }

      _backend = backend;
      _backendListener = () {
        state = _mapBackendState(backend.state.value);
      };
      backend.state.addListener(_backendListener!);
    }

    ref.onDispose(_cleanup);
    return _mapBackendState(backend.state.value);
  }

  void _cleanup() {
    final backend = _backend;
    final listener = _backendListener;
    if (backend != null && listener != null) {
      backend.state.removeListener(listener);
    }
    _backend = null;
    _backendListener = null;
  }

  Future<void> togglePlayPause(VoicePlaybackSource source) async {
    final backend = _backend;
    if (backend == null) {
      return;
    }

    final isSameMedia = state.activeMediaId == source.mediaId;

    try {
      if (isSameMedia && state.status == VoicePlaybackStatus.playing) {
        await backend.pause();
        return;
      }

      final canResumeWithoutReload =
          isSameMedia &&
          state.status != VoicePlaybackStatus.idle &&
          state.status != VoicePlaybackStatus.error;
      if (canResumeWithoutReload) {
        await backend.play();
        return;
      }

      await backend.load(source);
      final backendState = backend.state.value;
      if (backendState.mediaId == source.mediaId &&
          backendState.status != VoicePlaybackStatus.error) {
        await backend.play();
      }
    } catch (error, stackTrace) {
      debugPrint('[VoicePlayback] togglePlayPause failed: $error\n$stackTrace');
      state = state.copyWith(
        activeMediaId: source.mediaId,
        status: VoicePlaybackStatus.error,
        position: Duration.zero,
        duration: Duration.zero,
        error: 'Voice playback failed: $error',
      );
    }
  }

  Future<void> seek(Duration position) async {
    final backend = _backend;
    if (backend == null) {
      return;
    }

    try {
      await backend.seek(position);
    } catch (error, stackTrace) {
      debugPrint('[VoicePlayback] seek failed: $error\n$stackTrace');
    }
  }

  Future<void> cycleSpeed() async {
    final backend = _backend;
    if (backend == null) {
      return;
    }

    try {
      await backend.cycleSpeed();
    } catch (error, stackTrace) {
      debugPrint('[VoicePlayback] cycleSpeed failed: $error\n$stackTrace');
    }
  }

  Future<void> stop() async {
    final backend = _backend;
    if (backend == null) {
      state = const VoicePlaybackState();
      return;
    }

    try {
      await backend.stop();
    } catch (error, stackTrace) {
      debugPrint('[VoicePlayback] stop failed: $error\n$stackTrace');
    }
  }

  VoicePlaybackState _mapBackendState(VoicePlaybackBackendState backendState) {
    return VoicePlaybackState(
      activeMediaId: backendState.mediaId,
      status: backendState.status,
      position: backendState.position,
      duration: backendState.duration,
      speed: backendState.speed,
      error: backendState.errorMessage,
    );
  }
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackNotifier, VoicePlaybackState>(
      VoicePlaybackNotifier.new,
    );
