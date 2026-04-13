import 'dart:async';
import 'dart:io';

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

class VoicePlaybackNotifier extends Notifier<VoicePlaybackState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<dynamic>? _errorSub;

  /// The current temp plaintext audio file. Created by [getMediaFile] in
  /// [DownloadManager] and written to [getTemporaryDirectory]. Deleted
  /// explicitly when playback completes or the provider is disposed so that
  /// plaintext never persists beyond the active playback session.
  File? _tempFile;

  /// Sets [_tempFile] directly. Exposed for unit tests so the deletion
  /// lifecycle can be verified without a live audio player.
  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void setTempFileForTesting(File? file) => _tempFile = file;

  @override
  VoicePlaybackState build() {
    ref.onDispose(_disposePlayer);
    return const VoicePlaybackState();
  }

  Future<void> togglePlayPause(String mediaId, File audioFile) async {
    if (state.activeMediaId == mediaId && state.isPlaying) {
      // Pause current note.
      await _player?.pause();
      state = state.copyWith(isPlaying: false);
      return;
    }

    if (state.activeMediaId == mediaId && !state.isPlaying && state.error == null) {
      // Resume current note (no error — player is still set up).
      await _player?.play();
      state = state.copyWith(isPlaying: true);
      return;
    }

    // Load a different note, first play, or retry after error.
    _disposePlayer();

    // Track the new temp file — will be deleted on completion or dispose.
    _tempFile = audioFile;

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

      _errorSub = _player!.playbackEventStream.listen(
        null,
        onError: (Object e) {
          _disposePlayer();
          if (state.activeMediaId == mediaId) {
            state = state.copyWith(isPlaying: false, error: e.toString());
          }
        },
        cancelOnError: false,
      );

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
          // Playback finished — delete the temp plaintext file.
          _deleteTempFile();
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
    // Delete temp plaintext file when the player is disposed (stop, load new
    // track, or provider disposal). Errors are silenced — best-effort cleanup.
    _deleteTempFile();
  }

  /// Deletes [_tempFile] and clears the reference. Errors are silenced so that
  /// a missing file (e.g. already cleaned up by the OS) doesn't surface to the
  /// user. Called after playback completes and when the player is disposed.
  void _deleteTempFile() {
    final file = _tempFile;
    _tempFile = null;
    if (file == null) return;
    file.delete().onError((error, _) {
      // Best-effort: log in debug mode but don't surface to the user.
      debugPrint('[VoicePlayback] Could not delete temp file: ${file.path} ($error)');
      return file; // Return the file to satisfy the Future<File> type
    });
  }
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackNotifier, VoicePlaybackState>(
  VoicePlaybackNotifier.new,
);
