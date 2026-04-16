// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class VoicePlaybackState {
  const VoicePlaybackState({
    this.activeMediaId,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.error,
  });

  final String? activeMediaId;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;

  /// Non-null when the most recent play attempt failed for [activeMediaId].
  final String? error;

  VoicePlaybackState copyWith({
    String? activeMediaId,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
    String? error,
  }) {
    return VoicePlaybackState(
      activeMediaId: activeMediaId ?? this.activeMediaId,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      error: error ?? this.error,
    );
  }
}

@visibleForTesting
String normalizeVoiceContentType(String mimeType) {
  switch (mimeType.trim().toLowerCase()) {
    case '':
    case 'audio/ogg':
    case 'audio/aac':
    case 'audio/m4a':
    case 'audio/x-m4a':
    case 'audio/mp4':
      return 'audio/mp4';
    default:
      return mimeType;
  }
}

@visibleForTesting
class VoicePlaybackSource extends StreamAudioSource {
  VoicePlaybackSource({required this.audioBytes, required this.contentType});

  final Uint8List audioBytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = (start ?? 0).clamp(0, audioBytes.length);
    final safeEnd = (end ?? audioBytes.length).clamp(
      safeStart,
      audioBytes.length,
    );
    final chunk = Uint8List.sublistView(audioBytes, safeStart, safeEnd);

    return StreamAudioResponse(
      sourceLength: audioBytes.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      stream: Stream.value(chunk),
      contentType: contentType,
    );
  }
}

class VoicePlaybackNotifier extends Notifier<VoicePlaybackState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerException>? _errorSub;

  @override
  VoicePlaybackState build() {
    ref.onDispose(_disposePlayer);
    return const VoicePlaybackState();
  }

  Future<void> togglePlayPause(
    String mediaId,
    Uint8List audioBytes, {
    required String mimeType,
  }) async {
    if (state.activeMediaId == mediaId && state.isPlaying) {
      // Pause current note.
      await _player?.pause();
      state = state.copyWith(isPlaying: false);
      return;
    }

    if (state.activeMediaId == mediaId &&
        !state.isPlaying &&
        state.error == null) {
      // Resume current note (no error — player is still set up).
      await _player?.play();
      state = state.copyWith(isPlaying: true);
      return;
    }

    // Load a different note, first play, or retry after error.
    _disposePlayer();

    // Clear error and mark loading state before the async work.
    state = VoicePlaybackState(
      activeMediaId: mediaId,
      isPlaying: true,
      position: Duration.zero,
      duration: Duration.zero,
      speed: state.speed,
    );

    try {
      _player = AudioPlayer();

      _errorSub = _player!.errorStream.listen((e) {
        _disposePlayer();
        if (state.activeMediaId == mediaId) {
          state = state.copyWith(isPlaying: false, error: e.toString());
        }
      });

      await _player!.setAudioSource(
        VoicePlaybackSource(
          audioBytes: audioBytes,
          contentType: normalizeVoiceContentType(mimeType),
        ),
      );
      await _player!.setSpeed(state.speed);

      _positionSub = _player!.positionStream.listen((pos) {
        state = state.copyWith(position: pos);
      });

      _stateSub = _player!.playerStateStream.listen((ps) {
        if (ps.processingState == ProcessingState.completed) {
          _player?.seek(Duration.zero);
          _player?.pause();
          state = state.copyWith(isPlaying: false, position: Duration.zero);
        } else {
          state = state.copyWith(isPlaying: ps.playing);
        }
      });

      _durationSub = _player!.durationStream.listen((dur) {
        if (dur != null) {
          state = state.copyWith(duration: dur);
        }
      });

      await _player!.play();
    } catch (e) {
      _disposePlayer();
      state = state.copyWith(isPlaying: false, error: e.toString());
    }
  }

  void seek(Duration position) {
    _player?.seek(position);
  }

  void cycleSpeed() {
    final double newSpeed;
    if (state.speed == 1.0) {
      newSpeed = 1.5;
    } else if (state.speed == 1.5) {
      newSpeed = 2.0;
    } else {
      newSpeed = 1.0;
    }
    _player?.setSpeed(newSpeed);
    state = state.copyWith(speed: newSpeed);
  }

  void stop() {
    _player?.stop();
    _disposePlayer();
    state = const VoicePlaybackState();
  }

  void _disposePlayer() {
    _positionSub?.cancel();
    _positionSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _durationSub?.cancel();
    _durationSub = null;
    _errorSub?.cancel();
    _errorSub = null;
    _player?.dispose();
    _player = null;
  }
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackNotifier, VoicePlaybackState>(
      VoicePlaybackNotifier.new,
    );
