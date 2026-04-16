import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_format.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_playback_backend.dart';

abstract interface class MobileVoicePlaybackTrack {}

abstract interface class MobileVoicePlaybackHandle {}

abstract interface class MobileVoicePlaybackSessionConfigurator {
  Future<void> configureForPlayback();
}

abstract interface class MobileVoicePlaybackPlayer {
  Future<void> ensureInitialized();
  Future<MobileVoicePlaybackTrack> loadTrack(
    Uint8List bytes, {
    required String trackId,
  });
  Duration getDuration(MobileVoicePlaybackTrack track);
  Stream<MobileVoicePlaybackHandle> completionStream(
    MobileVoicePlaybackTrack track,
  );
  MobileVoicePlaybackHandle play(
    MobileVoicePlaybackTrack track, {
    required double speed,
  });
  void setPaused(MobileVoicePlaybackHandle handle, bool paused);
  void setSpeed(MobileVoicePlaybackHandle handle, double speed);
  void seek(MobileVoicePlaybackHandle handle, Duration position);
  Duration getPosition(MobileVoicePlaybackHandle handle);
  bool isHandleValid(MobileVoicePlaybackHandle handle);
  Future<void> stop(MobileVoicePlaybackHandle handle);
  Future<void> disposeTrack(MobileVoicePlaybackTrack track);
  Future<void> disposePlayer();
}

class MobileVoicePlaybackBackend implements VoicePlaybackBackend {
  MobileVoicePlaybackBackend({
    MobileVoicePlaybackPlayer? player,
    MobileVoicePlaybackSessionConfigurator? sessionConfigurator,
    Duration positionPollInterval = const Duration(milliseconds: 200),
  }) : _player = player ?? SoLoudMobileVoicePlaybackPlayer(),
       _sessionConfigurator =
           sessionConfigurator ??
           AudioSessionMobileVoicePlaybackSessionConfigurator(),
       _positionPollInterval = positionPollInterval;

  final MobileVoicePlaybackPlayer _player;
  final MobileVoicePlaybackSessionConfigurator _sessionConfigurator;
  final Duration _positionPollInterval;

  @override
  final ValueNotifier<VoicePlaybackBackendState> state =
      ValueNotifier<VoicePlaybackBackendState>(
        const VoicePlaybackBackendState(),
      );

  MobileVoicePlaybackTrack? _track;
  MobileVoicePlaybackHandle? _handle;
  StreamSubscription<MobileVoicePlaybackHandle>? _completionSubscription;
  Timer? _positionTimer;
  bool _isDisposed = false;

  @override
  Future<void> load(VoicePlaybackSource source) async {
    _ensureNotDisposed();
    await _unloadCurrentTrack(preserveSpeed: true, disposePlayer: false);

    final bytes = source.bytes;
    if (!source.isMemoryBacked || bytes == null) {
      _setError(
        mediaId: source.mediaId,
        message: 'Voice playback requires in-memory Ogg Opus bytes.',
      );
      return;
    }

    if (!isValidatedOggOpus(bytes)) {
      final detected = detectVoiceFormat(
        bytes,
        fallbackMimeType: source.mimeType,
      );
      _setError(
        mediaId: source.mediaId,
        message:
            'Voice playback requires validated Ogg Opus bytes; got ${detected.containerLabel}.',
      );
      return;
    }

    state.value = state.value.copyWith(
      mediaId: source.mediaId,
      status: VoicePlaybackStatus.loading,
      position: Duration.zero,
      duration: Duration.zero,
      clearErrorMessage: true,
    );

    try {
      await _sessionConfigurator.configureForPlayback();
      await _player.ensureInitialized();
      final track = await _player.loadTrack(
        bytes,
        trackId: 'voice_${source.mediaId}',
      );
      _track = track;
      _completionSubscription = _player
          .completionStream(track)
          .listen(_handleCompletion);

      state.value = state.value.copyWith(
        mediaId: source.mediaId,
        status: VoicePlaybackStatus.ready,
        position: Duration.zero,
        duration: _player.getDuration(track),
        clearErrorMessage: true,
      );
    } catch (error) {
      await _disposeTrack();
      _setError(
        mediaId: source.mediaId,
        message: 'Voice playback failed: $error',
      );
    }
  }

  @override
  Future<void> play() async {
    _ensureNotDisposed();
    final track = _track;
    if (track == null) {
      return;
    }

    final existingHandle = _handle;
    if (existingHandle != null && _player.isHandleValid(existingHandle)) {
      _player.setPaused(existingHandle, false);
      _startPositionPolling();
      _updatePositionFromHandle(existingHandle);
      state.value = state.value.copyWith(
        status: VoicePlaybackStatus.playing,
        clearErrorMessage: true,
      );
      return;
    }

    final requestedPosition =
        state.value.status == VoicePlaybackStatus.completed
        ? Duration.zero
        : _clampPosition(state.value.position);

    try {
      final handle = _player.play(track, speed: state.value.speed);
      _handle = handle;
      if (requestedPosition > Duration.zero) {
        _player.seek(handle, requestedPosition);
      }
      _player.setSpeed(handle, state.value.speed);
      _startPositionPolling();
      state.value = state.value.copyWith(
        status: VoicePlaybackStatus.playing,
        position: requestedPosition,
        clearErrorMessage: true,
      );
    } catch (error) {
      _handle = null;
      _stopPositionPolling();
      _setError(
        mediaId: state.value.mediaId,
        message: 'Voice playback failed: $error',
      );
    }
  }

  @override
  Future<void> pause() async {
    _ensureNotDisposed();
    final handle = _handle;
    if (handle == null || !_player.isHandleValid(handle)) {
      return;
    }

    _player.setPaused(handle, true);
    _stopPositionPolling();
    _updatePositionFromHandle(handle);
    state.value = state.value.copyWith(
      status: VoicePlaybackStatus.paused,
      clearErrorMessage: true,
    );
  }

  @override
  Future<void> stop() async {
    _ensureNotDisposed();
    _stopPositionPolling();

    final handle = _handle;
    _handle = null;
    if (handle != null && _player.isHandleValid(handle)) {
      await _player.stop(handle);
    }

    if (_track == null) {
      state.value = VoicePlaybackBackendState(speed: state.value.speed);
      return;
    }

    state.value = state.value.copyWith(
      status: VoicePlaybackStatus.ready,
      position: Duration.zero,
      clearErrorMessage: true,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _ensureNotDisposed();
    if (_track == null) {
      return;
    }

    final clampedPosition = _clampPosition(position);
    final handle = _handle;

    if (handle != null && _player.isHandleValid(handle)) {
      _player.seek(handle, clampedPosition);
      _updatePositionFromHandle(handle);
      return;
    }

    state.value = state.value.copyWith(position: clampedPosition);
  }

  @override
  Future<double> cycleSpeed() async {
    _ensureNotDisposed();
    final newSpeed = nextVoicePlaybackSpeed(state.value.speed);
    final handle = _handle;
    if (handle != null && _player.isHandleValid(handle)) {
      _player.setSpeed(handle, newSpeed);
    }
    state.value = state.value.copyWith(speed: newSpeed);
    return newSpeed;
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _unloadCurrentTrack(preserveSpeed: true, disposePlayer: true);
    state.dispose();
  }

  Future<void> _unloadCurrentTrack({
    required bool preserveSpeed,
    required bool disposePlayer,
  }) async {
    _stopPositionPolling();
    await _completionSubscription?.cancel();
    _completionSubscription = null;

    final handle = _handle;
    _handle = null;
    if (handle != null && _player.isHandleValid(handle)) {
      await _player.stop(handle);
    }

    await _disposeTrack();

    if (disposePlayer) {
      await _player.disposePlayer();
    }

    if (!_isDisposed) {
      state.value = VoicePlaybackBackendState(
        speed: preserveSpeed ? state.value.speed : 1.0,
      );
    }
  }

  Future<void> _disposeTrack() async {
    final track = _track;
    _track = null;
    if (track != null) {
      await _player.disposeTrack(track);
    }
  }

  void _handleCompletion(MobileVoicePlaybackHandle completedHandle) {
    if (_handle != completedHandle) {
      return;
    }

    _stopPositionPolling();
    _handle = null;
    state.value = state.value.copyWith(
      status: VoicePlaybackStatus.completed,
      position: state.value.duration,
      clearErrorMessage: true,
    );
  }

  void _startPositionPolling() {
    _stopPositionPolling();
    if (_positionPollInterval <= Duration.zero) {
      return;
    }

    _positionTimer = Timer.periodic(_positionPollInterval, (_) {
      final handle = _handle;
      if (handle == null || !_player.isHandleValid(handle)) {
        return;
      }
      _updatePositionFromHandle(handle);
    });
  }

  void _stopPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _updatePositionFromHandle(MobileVoicePlaybackHandle handle) {
    final position = _clampPosition(_player.getPosition(handle));
    state.value = state.value.copyWith(position: position);
  }

  Duration _clampPosition(Duration position) {
    if (position.isNegative) {
      return Duration.zero;
    }
    final duration = state.value.duration;
    if (duration == Duration.zero || position <= duration) {
      return position;
    }
    return duration;
  }

  void _setError({required String? mediaId, required String message}) {
    state.value = state.value.copyWith(
      mediaId: mediaId,
      status: VoicePlaybackStatus.error,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: message,
    );
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Voice playback backend has been disposed.');
    }
  }
}

class AudioSessionMobileVoicePlaybackSessionConfigurator
    implements MobileVoicePlaybackSessionConfigurator {
  @override
  Future<void> configureForPlayback() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: true,
      ),
    );
  }
}

class SoLoudMobileVoicePlaybackPlayer implements MobileVoicePlaybackPlayer {
  SoLoudMobileVoicePlaybackPlayer({SoLoud? soLoud})
    : _soLoud = soLoud ?? SoLoud.instance;

  final SoLoud _soLoud;
  bool _ownsPlayer = false;

  @override
  Stream<MobileVoicePlaybackHandle> completionStream(
    MobileVoicePlaybackTrack track,
  ) {
    final soLoudTrack = track as _SoLoudMobileVoicePlaybackTrack;
    return soLoudTrack.source.soundEvents
        .where((event) => event.event == SoundEventType.handleIsNoMoreValid)
        .map((event) => _SoLoudMobileVoicePlaybackHandle(event.handle));
  }

  @override
  Future<void> disposePlayer() async {
    if (_ownsPlayer && _soLoud.isInitialized) {
      _soLoud.deinit();
      _ownsPlayer = false;
    }
  }

  @override
  Future<void> disposeTrack(MobileVoicePlaybackTrack track) async {
    _pendingHandle = null;
    final soLoudTrack = track as _SoLoudMobileVoicePlaybackTrack;
    if (_soLoud.isInitialized) {
      await _soLoud.disposeSource(soLoudTrack.source);
    }
  }

  @override
  Future<void> ensureInitialized() async {
    if (_soLoud.isInitialized) {
      return;
    }
    await _soLoud.init();
    _ownsPlayer = true;
  }

  @override
  Duration getDuration(MobileVoicePlaybackTrack track) {
    final soLoudTrack = track as _SoLoudMobileVoicePlaybackTrack;
    return _soLoud.getLength(soLoudTrack.source);
  }

  @override
  Duration getPosition(MobileVoicePlaybackHandle handle) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    return _soLoud.getPosition(soLoudHandle.handle);
  }

  @override
  bool isHandleValid(MobileVoicePlaybackHandle handle) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    return _soLoud.getIsValidVoiceHandle(soLoudHandle.handle);
  }

  @override
  Future<MobileVoicePlaybackTrack> loadTrack(
    Uint8List bytes, {
    required String trackId,
  }) async {
    // Use setBufferStream instead of loadMem because loadMem fails on iOS
    // with the patched flutter_soloud build. The buffer stream approach
    // starts playback paused, feeds all bytes, then marks the stream as
    // ended — producing a seekable, duration-aware source identical to
    // loadMem but using a code path that works on both platforms.
    final source = _soLoud.setBufferStream(
      format: BufferType.auto,
      bufferingTimeNeeds: 0.05,
      maxBufferSizeDuration: const Duration(seconds: 660),
    );
    final handle = _soLoud.play(source, paused: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _soLoud.addAudioDataStream(source, bytes);
    _soLoud.setDataIsEnded(source);
    // Stash the pre-created handle so play() can unpause it.
    _pendingHandle = _SoLoudMobileVoicePlaybackHandle(handle);
    return _SoLoudMobileVoicePlaybackTrack(source);
  }

  /// Handle created during [loadTrack] that is paused and waiting for
  /// [play] to unpause it.
  _SoLoudMobileVoicePlaybackHandle? _pendingHandle;

  @override
  MobileVoicePlaybackHandle play(
    MobileVoicePlaybackTrack track, {
    required double speed,
  }) {
    final pending = _pendingHandle;
    _pendingHandle = null;
    if (pending != null) {
      _soLoud.setRelativePlaySpeed(pending.handle, speed);
      _soLoud.setPause(pending.handle, false);
      return pending;
    }
    // Fallback for replay after completion — start fresh.
    final soLoudTrack = track as _SoLoudMobileVoicePlaybackTrack;
    final handle = _soLoud.play(soLoudTrack.source);
    _soLoud.setRelativePlaySpeed(handle, speed);
    return _SoLoudMobileVoicePlaybackHandle(handle);
  }

  @override
  void seek(MobileVoicePlaybackHandle handle, Duration position) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    _soLoud.seek(soLoudHandle.handle, position);
  }

  @override
  void setPaused(MobileVoicePlaybackHandle handle, bool paused) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    _soLoud.setPause(soLoudHandle.handle, paused);
  }

  @override
  void setSpeed(MobileVoicePlaybackHandle handle, double speed) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    _soLoud.setRelativePlaySpeed(soLoudHandle.handle, speed);
  }

  @override
  Future<void> stop(MobileVoicePlaybackHandle handle) {
    final soLoudHandle = handle as _SoLoudMobileVoicePlaybackHandle;
    return _soLoud.stop(soLoudHandle.handle);
  }
}

final class _SoLoudMobileVoicePlaybackTrack
    implements MobileVoicePlaybackTrack {
  const _SoLoudMobileVoicePlaybackTrack(this.source);

  final AudioSource source;

  @override
  bool operator ==(Object other) {
    return other is _SoLoudMobileVoicePlaybackTrack &&
        other.source.soundHash == source.soundHash;
  }

  @override
  int get hashCode => source.soundHash.hashCode;
}

final class _SoLoudMobileVoicePlaybackHandle
    implements MobileVoicePlaybackHandle {
  const _SoLoudMobileVoicePlaybackHandle(this.handle);

  final SoundHandle handle;

  @override
  bool operator ==(Object other) {
    return other is _SoLoudMobileVoicePlaybackHandle &&
        other.handle.id == handle.id;
  }

  @override
  int get hashCode => handle.id.hashCode;
}
