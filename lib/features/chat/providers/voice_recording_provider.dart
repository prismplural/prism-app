import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/chat/services/voice/mobile_voice_recorder_backend.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_recorder_backend.dart';

final voiceRecorderBackendProvider = Provider.autoDispose<VoiceRecorderBackend>(
  (ref) {
    final backend = MobileVoiceRecorderBackend();
    ref.onDispose(() {
      unawaited(backend.dispose());
    });
    return backend;
  },
);

enum VoiceRecordingStatus {
  idle,
  recording,
  preparing,
  readyToSend,
  error,
  unsupported,
}

enum VoiceRecordingError {
  permissionDenied,
  permissionBlocked,
  tooShort,
  unsupported,
  unknown,
}

class VoiceRecordingState {
  const VoiceRecordingState({
    this.status = VoiceRecordingStatus.idle,
    this.elapsedMs = 0,
    this.amplitudeSamples = const [],
    this.artifact,
    this.errorType,
    this.errorMessage,
  });

  final VoiceRecordingStatus status;
  final int elapsedMs;
  final List<double> amplitudeSamples;
  final VoiceCaptureArtifact? artifact;
  final VoiceRecordingError? errorType;
  final String? errorMessage;

  Uint8List? get audioBytes => artifact?.bytes;
  int get durationMs => artifact?.durationMs ?? 0;
  String get waveformB64 => artifact?.waveformB64 ?? '';
  String? get mimeType => artifact?.mimeType;

  VoiceRecordingState copyWith({
    VoiceRecordingStatus? status,
    int? elapsedMs,
    List<double>? amplitudeSamples,
    VoiceCaptureArtifact? artifact,
    bool clearArtifact = false,
    VoiceRecordingError? errorType,
    bool clearErrorType = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return VoiceRecordingState(
      status: status ?? this.status,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      amplitudeSamples: amplitudeSamples ?? this.amplitudeSamples,
      artifact: clearArtifact ? null : (artifact ?? this.artifact),
      errorType: clearErrorType ? null : (errorType ?? this.errorType),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

class VoiceRecordingNotifier extends Notifier<VoiceRecordingState> {
  final List<double> _samples = <double>[];
  StreamSubscription<double>? _meterSubscription;
  VoiceRecorderBackend? _backend;
  VoidCallback? _backendListener;

  // Exponential moving average state for amplitude smoothing.
  // α=0.3 keeps bars visually stable while still tracking real loudness changes.
  static const _emaAlpha = 0.3;
  static const _floorDb = -60.0;
  double _emaValue = _floorDb;

  @override
  VoiceRecordingState build() {
    final backend = ref.watch(voiceRecorderBackendProvider);
    if (!identical(_backend, backend)) {
      final previousBackend = _backend;
      final previousListener = _backendListener;
      if (previousBackend != null && previousListener != null) {
        previousBackend.state.removeListener(previousListener);
      }
      unawaited(_meterSubscription?.cancel());

      _backend = backend;
      _backendListener = () {
        _syncFromBackend(backend.state.value);
      };
      backend.state.addListener(_backendListener!);
      _meterSubscription = backend.meterStream.listen((raw) {
        final clamped =
            raw.isFinite && raw > _floorDb ? raw : _floorDb;
        _emaValue = _emaAlpha * clamped + (1.0 - _emaAlpha) * _emaValue;
        _samples.add(_emaValue);
        state = state.copyWith(
          elapsedMs: backend.state.value.elapsed.inMilliseconds,
          amplitudeSamples: List<double>.unmodifiable(_samples),
        );
      });
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
    _backendListener = null;
    unawaited(_meterSubscription?.cancel());
    _meterSubscription = null;
    _samples.clear();
    _backend = null;
  }

  Future<void> startRecording() async {
    final backend = _backend;
    if (backend == null) {
      return;
    }

    _samples.clear();
    _emaValue = _floorDb;
    state = state.copyWith(
      elapsedMs: 0,
      amplitudeSamples: const <double>[],
      clearArtifact: true,
      clearErrorType: true,
      clearErrorMessage: true,
    );

    try {
      await backend.start();
      await _tryHaptic(HapticFeedback.mediumImpact);
    } on VoiceRecorderBackendException catch (error, stackTrace) {
      debugPrint('[VoiceRecording] startRecording failed: $error\n$stackTrace');
      _syncFromBackend(backend.state.value);
    } catch (error, stackTrace) {
      debugPrint('[VoiceRecording] startRecording failed: $error\n$stackTrace');
      state = const VoiceRecordingState(
        status: VoiceRecordingStatus.error,
        errorType: VoiceRecordingError.unknown,
      );
    }
  }

  Future<VoiceRecordingState> stopRecording() async {
    final backend = _backend;
    if (backend == null || state.status != VoiceRecordingStatus.recording) {
      return state;
    }

    try {
      await backend.stop();
      await _tryHaptic(HapticFeedback.lightImpact);
      _syncFromBackend(backend.state.value);
      return state;
    } on VoiceRecorderBackendException catch (error, stackTrace) {
      debugPrint('[VoiceRecording] stopRecording failed: $error\n$stackTrace');
      _syncFromBackend(backend.state.value);
      return state;
    } catch (error, stackTrace) {
      debugPrint('[VoiceRecording] stopRecording failed: $error\n$stackTrace');
      state = const VoiceRecordingState(
        status: VoiceRecordingStatus.error,
        errorType: VoiceRecordingError.unknown,
      );
      return state;
    }
  }

  Future<void> cancelRecording() async {
    final backend = _backend;
    if (backend == null) {
      return;
    }

    try {
      await backend.cancel();
    } catch (_) {
      state = const VoiceRecordingState();
    }

    _samples.clear();
    _emaValue = _floorDb;
    state = const VoiceRecordingState();
    await HapticFeedback.lightImpact();
  }

  void reset() {
    _samples.clear();
    _emaValue = _floorDb;
    state = const VoiceRecordingState();
    final backend = _backend;
    if (backend != null) {
      unawaited(backend.cancel());
    }
  }

  void _syncFromBackend(VoiceRecorderBackendState backendState) {
    state = _mapBackendState(backendState);
  }

  VoiceRecordingState _mapBackendState(VoiceRecorderBackendState backendState) {
    return VoiceRecordingState(
      status: switch (backendState.status) {
        VoiceRecorderBackendStatus.idle => VoiceRecordingStatus.idle,
        VoiceRecorderBackendStatus.recording => VoiceRecordingStatus.recording,
        VoiceRecorderBackendStatus.preparing => VoiceRecordingStatus.preparing,
        VoiceRecorderBackendStatus.readyToSend =>
          VoiceRecordingStatus.readyToSend,
        VoiceRecorderBackendStatus.error => VoiceRecordingStatus.error,
        VoiceRecorderBackendStatus.unsupported =>
          VoiceRecordingStatus.unsupported,
      },
      elapsedMs: backendState.elapsed.inMilliseconds,
      amplitudeSamples: List<double>.unmodifiable(_samples),
      artifact: backendState.artifact,
      errorType: _mapError(backendState.errorCode),
      errorMessage: backendState.errorMessage,
    );
  }

  Future<void> _tryHaptic(Future<void> Function() effect) async {
    try {
      await effect();
    } catch (_) {}
  }

  VoiceRecordingError? _mapError(VoiceRecorderErrorCode? errorCode) {
    return switch (errorCode) {
      VoiceRecorderErrorCode.permissionDenied =>
        VoiceRecordingError.permissionDenied,
      VoiceRecorderErrorCode.permissionBlocked =>
        VoiceRecordingError.permissionBlocked,
      VoiceRecorderErrorCode.tooShort => VoiceRecordingError.tooShort,
      VoiceRecorderErrorCode.unsupported => VoiceRecordingError.unsupported,
      null => null,
      _ => VoiceRecordingError.unknown,
    };
  }
}

final voiceRecordingProvider =
    NotifierProvider.autoDispose<VoiceRecordingNotifier, VoiceRecordingState>(
      VoiceRecordingNotifier.new,
    );
