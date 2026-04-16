import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/services/voice/mobile_voice_playback_backend.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

void main() {
  group('MobileVoicePlaybackBackend', () {
    test('loads validated ogg bytes and reports playing state', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-1',
        ),
      );
      await backend.play();

      expect(backend.state.value.status, VoicePlaybackStatus.playing);
      expect(backend.state.value.duration, player.duration);
      expect(player.loadedBytes, isNotNull);
    });

    test('invalid bytes fail safely', () async {
      final backend = MobileVoicePlaybackBackend(
        player: FakeMobileVoicePlaybackPlayer(),
      );

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          mimeType: 'audio/aac',
          mediaId: 'broken',
        ),
      );

      expect(backend.state.value.status, VoicePlaybackStatus.error);
      expect(backend.state.value.errorMessage, isNotNull);
    });

    test('stop, seek, and speed transitions stay consistent', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-2',
        ),
      );

      await backend.seek(const Duration(seconds: 2));
      final newSpeed = await backend.cycleSpeed();
      await backend.play();
      await backend.pause();
      await backend.stop();

      expect(newSpeed, 1.5);
      expect(backend.state.value.status, VoicePlaybackStatus.ready);
      expect(backend.state.value.position, Duration.zero);
      expect(backend.state.value.speed, 1.5);
      expect(player.lastSeek, const Duration(seconds: 2));
      expect(player.lastSpeed, 1.5);
      expect(player.stopCallCount, 1);
    });

    test('dispose cleans up active playback resources', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-3',
        ),
      );
      await backend.play();
      await backend.dispose();

      expect(player.disposeTrackCallCount, 1);
      expect(player.disposePlayerCallCount, 1);
    });

    test('non-memory-backed source fails with error', () async {
      final backend = MobileVoicePlaybackBackend(
        player: FakeMobileVoicePlaybackPlayer(),
      );

      await backend.load(
        const VoicePlaybackSource.file(
          filePath: '/tmp/voice.ogg',
          mimeType: 'audio/ogg',
          mediaId: 'file-1',
        ),
      );

      expect(backend.state.value.status, VoicePlaybackStatus.error);
      expect(
        backend.state.value.errorMessage,
        contains('in-memory'),
      );
    });

    test('resume via setPaused on existing valid handle', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-resume',
        ),
      );

      await backend.play();
      await backend.pause();
      await backend.play();

      // One pause (setPaused true) + one resume (setPaused false)
      expect(player.setPausedCount, 2);
      expect(player.lastPausedValue, false);
      // Only one handle was created (id=1), no second play() call
      expect(player.nextHandleId, 2);
    });

    test('natural completion transitions to completed state', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-complete',
        ),
      );

      await backend.play();
      final handle = player.lastCreatedHandle!;
      player.emitCompletion(handle);

      // Allow the stream event to propagate
      await Future<void>.delayed(Duration.zero);

      expect(backend.state.value.status, VoicePlaybackStatus.completed);
      expect(backend.state.value.position, backend.state.value.duration);
    });

    test('seek with negative position clamps to zero', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-seek-neg',
        ),
      );

      await backend.seek(const Duration(milliseconds: -500));

      expect(backend.state.value.position, Duration.zero);
    });

    test('play after completion resets to beginning', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-replay',
        ),
      );

      await backend.play();
      final handle = player.lastCreatedHandle!;
      player.emitCompletion(handle);
      await Future<void>.delayed(Duration.zero);

      expect(backend.state.value.status, VoicePlaybackStatus.completed);

      await backend.play();

      expect(backend.state.value.status, VoicePlaybackStatus.playing);
      expect(backend.state.value.position, Duration.zero);
    });

    test('load new source disposes previous track', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'source-a',
        ),
      );

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'source-b',
        ),
      );

      expect(player.disposeTrackCallCount, 1);
    });

    test('cycleSpeed cycles through 1.0 → 1.5 → 2.0 → 1.0', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-speed',
        ),
      );

      final speeds = <double>[
        await backend.cycleSpeed(),
        await backend.cycleSpeed(),
        await backend.cycleSpeed(),
      ];

      expect(speeds, [1.5, 2.0, 1.0]);
    });

    test('play failure transitions to error state', () async {
      final player = FakeMobileVoicePlaybackPlayer();
      final backend = MobileVoicePlaybackBackend(player: player);

      await backend.load(
        VoicePlaybackSource.bytes(
          bytes: _validOggOpusBytes(),
          mimeType: 'audio/ogg',
          mediaId: 'voice-fail',
        ),
      );

      player.playError = Exception('audio device unavailable');
      await backend.play();

      expect(backend.state.value.status, VoicePlaybackStatus.error);
      expect(
        backend.state.value.errorMessage,
        contains('audio device unavailable'),
      );
    });
  });
}

Uint8List _validOggOpusBytes() {
  return Uint8List.fromList([
    ...'OggS'.codeUnits,
    ...List<int>.filled(24, 0),
    ...'OpusHead'.codeUnits,
    ...List<int>.filled(32, 1),
  ]);
}

final class FakeMobileVoicePlaybackPlayer implements MobileVoicePlaybackPlayer {
  final StreamController<MobileVoicePlaybackHandle> _completionController =
      StreamController<MobileVoicePlaybackHandle>.broadcast();

  final FakeMobileVoicePlaybackTrack _track =
      const FakeMobileVoicePlaybackTrack('track-1');

  Uint8List? loadedBytes;
  Duration duration = const Duration(seconds: 4);
  Duration position = Duration.zero;
  Duration? lastSeek;
  double? lastSpeed;
  int stopCallCount = 0;
  int disposeTrackCallCount = 0;
  int disposePlayerCallCount = 0;
  int setPausedCount = 0;
  bool? lastPausedValue;
  Object? playError;
  int _nextHandleId = 1;
  FakeMobileVoicePlaybackHandle? lastCreatedHandle;
  final Set<FakeMobileVoicePlaybackHandle> _validHandles =
      <FakeMobileVoicePlaybackHandle>{};

  int get nextHandleId => _nextHandleId;

  void emitCompletion(MobileVoicePlaybackHandle handle) {
    _completionController.add(handle);
  }

  @override
  Future<void> disposePlayer() async {
    disposePlayerCallCount += 1;
    await _completionController.close();
  }

  @override
  Stream<MobileVoicePlaybackHandle> completionStream(
    MobileVoicePlaybackTrack track,
  ) {
    return _completionController.stream;
  }

  @override
  Future<void> disposeTrack(MobileVoicePlaybackTrack track) async {
    disposeTrackCallCount += 1;
    _validHandles.clear();
  }

  @override
  Future<void> ensureInitialized() async {}

  @override
  Duration getDuration(MobileVoicePlaybackTrack track) => duration;

  @override
  Duration getPosition(MobileVoicePlaybackHandle handle) => position;

  @override
  bool isHandleValid(MobileVoicePlaybackHandle handle) {
    return _validHandles.contains(handle);
  }

  @override
  Future<MobileVoicePlaybackTrack> loadTrack(
    Uint8List bytes, {
    required String trackId,
  }) async {
    loadedBytes = bytes;
    return _track;
  }

  @override
  MobileVoicePlaybackHandle play(
    MobileVoicePlaybackTrack track, {
    required double speed,
  }) {
    final error = playError;
    if (error != null) {
      throw error;
    }
    lastSpeed = speed;
    final handle = FakeMobileVoicePlaybackHandle(_nextHandleId++);
    lastCreatedHandle = handle;
    _validHandles.add(handle);
    return handle;
  }

  @override
  void seek(MobileVoicePlaybackHandle handle, Duration position) {
    this.position = position;
    lastSeek = position;
  }

  @override
  void setPaused(MobileVoicePlaybackHandle handle, bool paused) {
    setPausedCount += 1;
    lastPausedValue = paused;
  }

  @override
  void setSpeed(MobileVoicePlaybackHandle handle, double speed) {
    lastSpeed = speed;
  }

  @override
  Future<void> stop(MobileVoicePlaybackHandle handle) async {
    stopCallCount += 1;
    _validHandles.remove(handle);
    await _completionController.addStream(Stream.value(handle));
  }
}

final class FakeMobileVoicePlaybackTrack implements MobileVoicePlaybackTrack {
  const FakeMobileVoicePlaybackTrack(this.id);

  final String id;

  @override
  bool operator ==(Object other) {
    return other is FakeMobileVoicePlaybackTrack && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

final class FakeMobileVoicePlaybackHandle implements MobileVoicePlaybackHandle {
  const FakeMobileVoicePlaybackHandle(this.id);

  final int id;

  @override
  bool operator ==(Object other) {
    return other is FakeMobileVoicePlaybackHandle && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
