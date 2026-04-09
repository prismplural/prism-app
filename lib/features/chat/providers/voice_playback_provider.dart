import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class VoicePlaybackState {
  const VoicePlaybackState({
    this.activeMediaId,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
  });

  final String? activeMediaId;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;

  VoicePlaybackState copyWith({
    String? activeMediaId,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
  }) {
    return VoicePlaybackState(
      activeMediaId: activeMediaId ?? this.activeMediaId,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
    );
  }
}

class VoicePlaybackNotifier extends Notifier<VoicePlaybackState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  VoicePlaybackState build() => const VoicePlaybackState();

  Future<void> togglePlayPause(String mediaId, File audioFile) async {
    if (state.activeMediaId == mediaId && state.isPlaying) {
      // Pause current note.
      await _player?.pause();
      state = state.copyWith(isPlaying: false);
      return;
    }

    if (state.activeMediaId == mediaId && !state.isPlaying) {
      // Resume current note.
      await _player?.play();
      state = state.copyWith(isPlaying: true);
      return;
    }

    // Load a different note (or first play).
    _disposePlayer();

    _player = AudioPlayer();
    await _player!.setAudioSource(AudioSource.file(audioFile.path));
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

    state = state.copyWith(
      activeMediaId: mediaId,
      isPlaying: true,
      position: Duration.zero,
      duration: Duration.zero,
    );

    await _player!.play();
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
    _player?.dispose();
    _player = null;
  }
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackNotifier, VoicePlaybackState>(
  VoicePlaybackNotifier.new,
);
