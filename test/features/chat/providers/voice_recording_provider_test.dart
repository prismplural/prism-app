import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_recorder_backend.dart';

class _FakeVoiceRecorderBackend implements VoiceRecorderBackend {
  _FakeVoiceRecorderBackend({this.failOnStart});

  final VoiceRecorderBackendException? failOnStart;

  @override
  final ValueNotifier<VoiceRecorderBackendState> state =
      ValueNotifier<VoiceRecorderBackendState>(
        const VoiceRecorderBackendState(),
      );

  final StreamController<double> _meterController =
      StreamController<double>.broadcast();

  bool startCalled = false;
  bool stopCalled = false;
  bool cancelCalled = false;
  bool disposeCalled = false;
  final Completer<void> stopGate = Completer<void>();

  @override
  Stream<double> get meterStream => _meterController.stream;

  @override
  Future<VoiceRecorderCapabilities> getCapabilities() async {
    return const VoiceRecorderCapabilities(
      isSupported: true,
      needsCafToOggRemux: true,
      outputFileExtension: 'caf',
      sourceContainerLabel: 'CAF Opus',
      normalizedContainerLabel: 'Ogg Opus',
      summary: 'Fake test recorder',
    );
  }

  @override
  Future<void> start() async {
    startCalled = true;
    if (failOnStart != null) {
      state.value = state.value.copyWith(
        status: VoiceRecorderBackendStatus.error,
        errorCode: failOnStart!.errorCode,
        errorMessage: failOnStart!.message,
        permissionStatus: VoiceRecorderPermissionStatus.blocked,
      );
      throw failOnStart!;
    }

    state.value = state.value.copyWith(
      status: VoiceRecorderBackendStatus.recording,
      permissionStatus: VoiceRecorderPermissionStatus.granted,
      elapsed: const Duration(milliseconds: 1200),
      clearArtifact: true,
      clearErrorCode: true,
      clearErrorMessage: true,
    );
    _meterController.add(-18);
    _meterController.add(-9);
  }

  @override
  Future<VoiceCaptureArtifact> stop() async {
    stopCalled = true;
    state.value = state.value.copyWith(
      status: VoiceRecorderBackendStatus.preparing,
      elapsed: const Duration(milliseconds: 1650),
      clearArtifact: true,
    );

    await stopGate.future;

    final artifact = VoiceCaptureArtifact(
      bytes: Uint8List.fromList(<int>[79, 103, 103, 83]),
      mimeType: 'audio/ogg',
      durationMs: 1650,
      waveformB64: 'AQID',
      debugBackend: 'fake-recorder',
    );

    state.value = state.value.copyWith(
      status: VoiceRecorderBackendStatus.readyToSend,
      elapsed: const Duration(milliseconds: 1650),
      artifact: artifact,
      clearErrorCode: true,
      clearErrorMessage: true,
    );

    return artifact;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    state.value = state.value.copyWith(
      status: VoiceRecorderBackendStatus.idle,
      elapsed: Duration.zero,
      clearArtifact: true,
      clearErrorCode: true,
      clearErrorMessage: true,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _meterController.close();
    state.dispose();
  }
}

void main() {
  group('VoiceRecordingState', () {
    test('default state has idle status and no artifact', () {
      const state = VoiceRecordingState();
      expect(state.status, VoiceRecordingStatus.idle);
      expect(state.elapsedMs, 0);
      expect(state.amplitudeSamples, isEmpty);
      expect(state.artifact, isNull);
      expect(state.audioBytes, isNull);
      expect(state.mimeType, isNull);
      expect(state.errorType, isNull);
    });
  });

  group('VoiceRecordingNotifier', () {
    test('provider exposes preparing state before ready to send', () async {
      final backend = _FakeVoiceRecorderBackend();
      final container = ProviderContainer(
        overrides: [voiceRecorderBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      final statuses = <VoiceRecordingStatus>[];
      final artifactsReady = <bool>[];
      final subscription = container.listen<VoiceRecordingState>(
        voiceRecordingProvider,
        (_, next) {
          statuses.add(next.status);
          artifactsReady.add(next.artifact != null);
        },
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final notifier = container.read(voiceRecordingProvider.notifier);
      await notifier.startRecording();

      final stopFuture = notifier.stopRecording();
      await Future<void>.delayed(Duration.zero);

      final preparingState = container.read(voiceRecordingProvider);
      expect(preparingState.status, VoiceRecordingStatus.preparing);
      expect(preparingState.artifact, isNull);

      backend.stopGate.complete();
      final readyState = await stopFuture;
      expect(readyState.status, VoiceRecordingStatus.readyToSend);
      expect(readyState.mimeType, 'audio/ogg');
      expect(readyState.audioBytes, isNotNull);

      expect(
        statuses,
        containsAllInOrder(<VoiceRecordingStatus>[
          VoiceRecordingStatus.idle,
          VoiceRecordingStatus.recording,
          VoiceRecordingStatus.preparing,
          VoiceRecordingStatus.readyToSend,
        ]),
      );

      final preparingIndex = statuses.indexOf(VoiceRecordingStatus.preparing);
      final readyIndex = statuses.indexOf(VoiceRecordingStatus.readyToSend);
      expect(preparingIndex, greaterThanOrEqualTo(0));
      expect(readyIndex, greaterThan(preparingIndex));
      expect(artifactsReady[preparingIndex], isFalse);
      expect(artifactsReady[readyIndex], isTrue);
    });

    test('maps blocked permission failures from backend', () async {
      final backend = _FakeVoiceRecorderBackend(
        failOnStart: const VoiceRecorderBackendException(
          errorCode: VoiceRecorderErrorCode.permissionBlocked,
          message: 'Microphone access is blocked.',
        ),
      );
      final container = ProviderContainer(
        overrides: [voiceRecorderBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      await container.read(voiceRecordingProvider.notifier).startRecording();

      final state = container.read(voiceRecordingProvider);
      expect(state.status, VoiceRecordingStatus.error);
      expect(state.errorType, VoiceRecordingError.permissionBlocked);
    });
  });
}
