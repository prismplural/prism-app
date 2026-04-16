import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/features/chat/providers/voice_playback_provider.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_playback_backend.dart';

void main() {
  group('MediaService.prepareVoiceNote', () {
    test('stores audio/ogg metadata for voice notes', () async {
      final encryption = _FakeMediaEncryptionService();
      final service = MediaService(
        compression: ImageCompressionService(),
        encryption: encryption,
        uploadQueue: UploadQueue(handle: null),
        downloadManager: DownloadManager(handle: null, encryption: encryption),
      );

      final result = await service.prepareVoiceNote(
        _validOggOpusBytes(),
        1200,
        'abcd',
      );

      expect(result.mimeType, 'audio/ogg');
    });

    test('rejects non-ogg bytes before upload', () async {
      final encryption = _FakeMediaEncryptionService();
      final service = MediaService(
        compression: ImageCompressionService(),
        encryption: encryption,
        uploadQueue: UploadQueue(handle: null),
        downloadManager: DownloadManager(handle: null, encryption: encryption),
      );

      await expectLater(
        () => service.prepareVoiceNote(
          Uint8List.fromList([1, 2, 3, 4]),
          1200,
          'abcd',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VoicePlaybackNotifier', () {
    test('routes ogg playback through the backend contract', () async {
      final backend = FakeVoicePlaybackBackend();
      final container = ProviderContainer(
        overrides: [voicePlaybackBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(voicePlaybackProvider.notifier);
      final source = VoicePlaybackSource.bytes(
        bytes: _validOggOpusBytes(),
        mimeType: 'audio/ogg',
        mediaId: 'voice-1',
      );

      await notifier.togglePlayPause(source);

      expect(backend.loadedSources, hasLength(1));
      expect(backend.loadedSources.single.mediaId, 'voice-1');
      expect(backend.loadedSources.single.bytes, isNotNull);
      expect(backend.playCallCount, 1);

      backend.state.value = backend.state.value.copyWith(
        mediaId: 'voice-1',
        status: VoicePlaybackStatus.playing,
        position: const Duration(seconds: 2),
        duration: const Duration(seconds: 5),
        speed: 1.5,
      );

      final state = container.read(voicePlaybackProvider);
      expect(state.activeMediaId, 'voice-1');
      expect(state.isPlaying, isTrue);
      expect(state.position, const Duration(seconds: 2));
      expect(state.duration, const Duration(seconds: 5));
      expect(state.speed, 1.5);
      expect(state.error, isNull);
    });

    test('pause and resume reuse the loaded backend track', () async {
      final backend = FakeVoicePlaybackBackend();
      final container = ProviderContainer(
        overrides: [voicePlaybackBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(voicePlaybackProvider.notifier);
      final source = VoicePlaybackSource.bytes(
        bytes: _validOggOpusBytes(),
        mimeType: 'audio/ogg',
        mediaId: 'voice-2',
      );

      await notifier.togglePlayPause(source);
      backend.state.value = backend.state.value.copyWith(
        mediaId: 'voice-2',
        status: VoicePlaybackStatus.playing,
      );

      await notifier.togglePlayPause(source);
      expect(backend.pauseCallCount, 1);
      expect(backend.loadedSources, hasLength(1));

      backend.state.value = backend.state.value.copyWith(
        mediaId: 'voice-2',
        status: VoicePlaybackStatus.paused,
      );

      await notifier.togglePlayPause(source);
      expect(backend.playCallCount, 2);
      expect(backend.loadedSources, hasLength(1));
    });

    test('seek and speed changes flow through the backend', () async {
      final backend = FakeVoicePlaybackBackend();
      final container = ProviderContainer(
        overrides: [voicePlaybackBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(voicePlaybackProvider.notifier);
      final source = VoicePlaybackSource.bytes(
        bytes: _validOggOpusBytes(),
        mimeType: 'audio/ogg',
        mediaId: 'voice-3',
      );

      await notifier.togglePlayPause(source);
      await notifier.seek(const Duration(seconds: 3));
      await notifier.cycleSpeed();

      expect(backend.seekPositions, [const Duration(seconds: 3)]);
      expect(backend.cycleSpeedCallCount, 1);
      expect(container.read(voicePlaybackProvider).speed, 1.5);
    });

    test(
      'backend validation failures surface a retryable error state',
      () async {
        final backend = FakeVoicePlaybackBackend()..failNextLoad = true;
        final container = ProviderContainer(
          overrides: [voicePlaybackBackendProvider.overrideWithValue(backend)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);
        final source = VoicePlaybackSource.bytes(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          mimeType: 'audio/ogg',
          mediaId: 'broken-voice',
        );

        await notifier.togglePlayPause(source);

        final state = container.read(voicePlaybackProvider);
        expect(state.activeMediaId, 'broken-voice');
        expect(state.isPlaying, isFalse);
        expect(state.error, contains('validated Ogg Opus'));
        expect(backend.playCallCount, 0);

        backend.failNextLoad = false;
        await notifier.togglePlayPause(
          VoicePlaybackSource.bytes(
            bytes: _validOggOpusBytes(),
            mimeType: 'audio/ogg',
            mediaId: 'broken-voice',
          ),
        );

        expect(backend.loadedSources, hasLength(2));
        expect(backend.playCallCount, 1);
      },
    );
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

final class FakeVoicePlaybackBackend implements VoicePlaybackBackend {
  @override
  final ValueNotifier<VoicePlaybackBackendState> state =
      ValueNotifier<VoicePlaybackBackendState>(
        const VoicePlaybackBackendState(),
      );

  final List<VoicePlaybackSource> loadedSources = <VoicePlaybackSource>[];
  final List<Duration> seekPositions = <Duration>[];
  int playCallCount = 0;
  int pauseCallCount = 0;
  int cycleSpeedCallCount = 0;
  bool failNextLoad = false;

  @override
  Future<double> cycleSpeed() async {
    cycleSpeedCallCount += 1;
    final newSpeed = nextVoicePlaybackSpeed(state.value.speed);
    state.value = state.value.copyWith(speed: newSpeed);
    return newSpeed;
  }

  @override
  Future<void> dispose() async {
    state.dispose();
  }

  @override
  Future<void> load(VoicePlaybackSource source) async {
    loadedSources.add(source);
    if (failNextLoad) {
      state.value = state.value.copyWith(
        mediaId: source.mediaId,
        status: VoicePlaybackStatus.error,
        errorMessage:
            'Voice playback requires validated Ogg Opus bytes; got Unknown.',
      );
      return;
    }

    state.value = state.value.copyWith(
      mediaId: source.mediaId,
      status: VoicePlaybackStatus.ready,
      position: Duration.zero,
      duration: const Duration(seconds: 5),
      clearErrorMessage: true,
    );
  }

  @override
  Future<void> pause() async {
    pauseCallCount += 1;
    state.value = state.value.copyWith(status: VoicePlaybackStatus.paused);
  }

  @override
  Future<void> play() async {
    if (state.value.status == VoicePlaybackStatus.error) {
      return;
    }
    playCallCount += 1;
    state.value = state.value.copyWith(status: VoicePlaybackStatus.playing);
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
    state.value = state.value.copyWith(position: position);
  }

  @override
  Future<void> stop() async {
    state.value = const VoicePlaybackBackendState();
  }
}

final class _FakeMediaEncryptionService extends MediaEncryptionService {
  @override
  Future<EncryptedMedia> encryptMedia(Uint8List plaintext) async {
    final ciphertext = Uint8List.fromList(plaintext.reversed.toList());
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    return EncryptedMedia(
      ciphertext: ciphertext,
      key: key,
      plaintextHash: sha256.convert(plaintext).toString(),
      ciphertextHash: sha256.convert(ciphertext).toString(),
    );
  }
}
