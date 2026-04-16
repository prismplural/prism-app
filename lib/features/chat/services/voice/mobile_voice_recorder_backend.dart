import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_format.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_recorder_backend.dart';
import 'package:record/record.dart';

abstract interface class MobileVoiceRecorderPlatform {
  bool get isIOS;
  bool get isAndroid;
}

enum MobileMicrophonePermissionStatus { granted, denied, blocked }

abstract interface class MobileMicrophonePermissionGate {
  Future<MobileMicrophonePermissionStatus> requestPermission();
}

abstract interface class MobileAudioSessionConfigurator {
  Future<void> configureForRecording();
}

abstract interface class MobileAudioRecorder {
  Future<void> start({required String path});
  Future<String?> stop();
  Future<void> cancel();
  Stream<double> amplitudeStream(Duration interval);
  Future<void> dispose();
}

abstract interface class MobileOggCafRemuxer {
  Future<Uint8List> remuxCafToOgg(String inputPath);
}

abstract interface class MobileVoiceRecorderFileStore {
  Future<String> createTempRecordingPath({required String extension});
  Future<Uint8List> readAsBytes(String path);
  Future<void> deleteIfExists(String path);
}

class MobileVoiceRecorderBackend implements VoiceRecorderBackend {
  MobileVoiceRecorderBackend({
    MobileVoiceRecorderPlatform? platform,
    MobileMicrophonePermissionGate? permissionGate,
    MobileAudioSessionConfigurator? audioSessionConfigurator,
    MobileAudioRecorder? recorder,
    MobileOggCafRemuxer? remuxer,
    MobileVoiceRecorderFileStore? fileStore,
    DateTime Function()? now,
    this.minDuration = const Duration(milliseconds: 500),
    this.maxDuration = const Duration(minutes: 10),
    this.maxInMemoryBytes = 16 * 1024 * 1024,
    this.amplitudeInterval = const Duration(milliseconds: 100),
  }) : _platform = platform ?? DefaultMobileVoiceRecorderPlatform(),
       _permissionGate =
           permissionGate ?? PermissionHandlerMicrophonePermissionGate(),
       _audioSessionConfigurator =
           audioSessionConfigurator ??
           AudioSessionMobileAudioSessionConfigurator(),
       _recorder = recorder ?? RecordMobileAudioRecorder(),
       _remuxer = remuxer ?? OggCafConverterMobileOggCafRemuxer(),
       _fileStore = fileStore ?? PathProviderMobileVoiceRecorderFileStore(),
       _now = now ?? DateTime.now;

  final MobileVoiceRecorderPlatform _platform;
  final MobileMicrophonePermissionGate _permissionGate;
  final MobileAudioSessionConfigurator _audioSessionConfigurator;
  final MobileAudioRecorder _recorder;
  final MobileOggCafRemuxer _remuxer;
  final MobileVoiceRecorderFileStore _fileStore;
  final DateTime Function() _now;

  final Duration minDuration;
  final Duration maxDuration;
  final int maxInMemoryBytes;
  final Duration amplitudeInterval;

  @override
  final ValueNotifier<VoiceRecorderBackendState> state =
      ValueNotifier<VoiceRecorderBackendState>(
        const VoiceRecorderBackendState(),
      );

  final StreamController<double> _meterController =
      StreamController<double>.broadcast();
  StreamSubscription<double>? _meterSubscription;
  final List<double> _amplitudeSamples = <double>[];

  VoiceRecorderCapabilities? _capabilities;
  String? _activeRecordingPath;
  DateTime? _recordingStartedAt;
  bool _isDisposed = false;

  @override
  Stream<double> get meterStream => _meterController.stream;

  @override
  Future<VoiceRecorderCapabilities> getCapabilities() async {
    final capabilities = _capabilities ?? _buildCapabilities();
    _capabilities = capabilities;
    if (capabilities.isSupported) {
      state.value = state.value.copyWith(
        capabilities: capabilities,
        status: state.value.status == VoiceRecorderBackendStatus.unsupported
            ? VoiceRecorderBackendStatus.idle
            : state.value.status,
      );
    } else {
      state.value = state.value.copyWith(
        capabilities: capabilities,
        status: VoiceRecorderBackendStatus.unsupported,
      );
    }
    return capabilities;
  }

  @override
  Future<void> start() async {
    _ensureNotDisposed();
    if (_activeRecordingPath != null) {
      throw _setError(
        VoiceRecorderErrorCode.alreadyRecording,
        'Voice recording is already in progress.',
      );
    }

    final capabilities = await getCapabilities();
    if (!capabilities.isSupported) {
      throw _setError(
        VoiceRecorderErrorCode.unsupported,
        capabilities.unsupportedReason ?? 'Voice recording is unavailable.',
      );
    }

    final permission = await _permissionGate.requestPermission();
    switch (permission) {
      case MobileMicrophonePermissionStatus.granted:
        break;
      case MobileMicrophonePermissionStatus.denied:
        throw _setError(
          VoiceRecorderErrorCode.permissionDenied,
          'Microphone permission is required before recording.',
          permissionStatus: VoiceRecorderPermissionStatus.denied,
        );
      case MobileMicrophonePermissionStatus.blocked:
        throw _setError(
          VoiceRecorderErrorCode.permissionBlocked,
          'Microphone access is blocked. Enable it in Settings.',
          permissionStatus: VoiceRecorderPermissionStatus.blocked,
        );
    }

    final recordingPath = await _fileStore.createTempRecordingPath(
      extension: capabilities.outputFileExtension,
    );

    try {
      if (capabilities.needsCafToOggRemux) {
        await _audioSessionConfigurator.configureForRecording();
      }

      await _cancelMeterSubscription();
      _amplitudeSamples.clear();
      _recordingStartedAt = _now();
      _activeRecordingPath = recordingPath;
      await _recorder.start(path: recordingPath);
      _meterSubscription = _recorder.amplitudeStream(amplitudeInterval).listen((
        value,
      ) {
        _amplitudeSamples.add(value);
        if (!_meterController.isClosed) {
          _meterController.add(value);
        }
        _updateElapsed();
      });

      state.value = state.value.copyWith(
        capabilities: capabilities,
        status: VoiceRecorderBackendStatus.recording,
        permissionStatus: VoiceRecorderPermissionStatus.granted,
        elapsed: Duration.zero,
        clearArtifact: true,
        clearErrorCode: true,
        clearErrorMessage: true,
      );
    } catch (error) {
      await _cancelMeterSubscription();
      await _cleanupRecordingFiles(<String>{recordingPath});
      _activeRecordingPath = null;
      _recordingStartedAt = null;
      throw _setError(
        VoiceRecorderErrorCode.recorderFailure,
        'Could not start voice recording.',
        cause: error,
        permissionStatus: VoiceRecorderPermissionStatus.granted,
      );
    }
  }

  @override
  Future<VoiceCaptureArtifact> stop() async {
    _ensureNotDisposed();
    final inputPath = _activeRecordingPath;
    final startedAt = _recordingStartedAt;
    final capabilities = _capabilities ?? await getCapabilities();
    if (inputPath == null || startedAt == null) {
      throw _setError(
        VoiceRecorderErrorCode.notRecording,
        'Voice recording is not active.',
      );
    }

    String? outputPath;
    try {
      outputPath = await _recorder.stop() ?? inputPath;
      await _cancelMeterSubscription();

      final duration = _now().difference(startedAt);

      if (duration < minDuration) {
        throw _setError(
          VoiceRecorderErrorCode.tooShort,
          'Voice recording is too short to send.',
          elapsed: duration,
        );
      }
      if (duration > maxDuration) {
        throw _setError(
          VoiceRecorderErrorCode.budgetExceeded,
          'Voice recording exceeded the safe processing budget.',
          elapsed: duration,
        );
      }

      final rawBytes = await _fileStore.readAsBytes(outputPath);
      if (rawBytes.isEmpty) {
        throw _setError(
          VoiceRecorderErrorCode.emptyRecording,
          'Voice recording produced no audio bytes.',
          elapsed: duration,
        );
      }
      if (rawBytes.length > maxInMemoryBytes) {
        throw _setError(
          VoiceRecorderErrorCode.budgetExceeded,
          'Voice recording exceeded the in-memory size budget.',
          elapsed: duration,
        );
      }

      Uint8List normalizedBytes;
      if (capabilities.needsCafToOggRemux) {
        state.value = state.value.copyWith(
          status: VoiceRecorderBackendStatus.preparing,
          permissionStatus: VoiceRecorderPermissionStatus.granted,
          elapsed: duration,
          clearErrorCode: true,
          clearErrorMessage: true,
        );
        final rawFormat = detectVoiceFormat(rawBytes);
        if (!rawFormat.isCafOpus) {
          throw _setError(
            VoiceRecorderErrorCode.invalidFormat,
            'iOS voice recording must stay inside the CAF remux boundary.',
            elapsed: duration,
          );
        }

        try {
          normalizedBytes = await _remuxer.remuxCafToOgg(outputPath);
        } catch (error) {
          throw _setError(
            VoiceRecorderErrorCode.remuxFailed,
            'Could not finalize the recorded voice note.',
            cause: error,
            elapsed: duration,
          );
        }
      } else {
        normalizedBytes = rawBytes;
      }

      if (normalizedBytes.isEmpty) {
        throw _setError(
          VoiceRecorderErrorCode.emptyRecording,
          'Voice recording produced no normalized audio bytes.',
          elapsed: duration,
        );
      }
      if (normalizedBytes.length > maxInMemoryBytes) {
        throw _setError(
          VoiceRecorderErrorCode.budgetExceeded,
          'Voice recording exceeded the safe upload size budget.',
          elapsed: duration,
        );
      }

      final normalizedFormat = detectVoiceFormat(
        normalizedBytes,
        fallbackMimeType: 'audio/ogg',
      );
      if (!normalizedFormat.isOggOpus) {
        throw _setError(
          VoiceRecorderErrorCode.invalidFormat,
          'Voice recording must normalize to validated Ogg Opus bytes.',
          elapsed: duration,
        );
      }

      final artifact = VoiceCaptureArtifact(
        bytes: normalizedBytes,
        mimeType: resolveVoiceMimeType(
          normalizedBytes,
          fallbackMimeType: 'audio/ogg',
        ),
        durationMs: duration.inMilliseconds,
        waveformB64: _buildWaveform(_amplitudeSamples),
        debugBackend: capabilities.needsCafToOggRemux
            ? 'mobile-ios-opus'
            : 'mobile-android-opus',
      );

      state.value = state.value.copyWith(
        status: VoiceRecorderBackendStatus.readyToSend,
        permissionStatus: VoiceRecorderPermissionStatus.granted,
        elapsed: duration,
        artifact: artifact,
        clearErrorCode: true,
        clearErrorMessage: true,
      );
      return artifact;
    } on VoiceRecorderBackendException {
      rethrow;
    } catch (error) {
      throw _setError(
        VoiceRecorderErrorCode.recorderFailure,
        'Voice recording failed while finalizing.',
        cause: error,
      );
    } finally {
      await _cancelMeterSubscription();
      await _cleanupRecordingFiles(<String>{inputPath, ?outputPath});
      _activeRecordingPath = null;
      _recordingStartedAt = null;
      _amplitudeSamples.clear();
    }
  }

  @override
  Future<void> cancel() async {
    _ensureNotDisposed();
    final inputPath = _activeRecordingPath;
    await _cancelMeterSubscription();
    try {
      if (inputPath != null) {
        await _recorder.cancel();
      }
    } finally {
      await _cleanupRecordingFiles(<String>{?inputPath});
      _activeRecordingPath = null;
      _recordingStartedAt = null;
      _amplitudeSamples.clear();
      state.value = state.value.copyWith(
        status: VoiceRecorderBackendStatus.idle,
        elapsed: Duration.zero,
        clearArtifact: true,
        clearErrorCode: true,
        clearErrorMessage: true,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    try {
      await cancel();
    } catch (_) {
      await _cancelMeterSubscription();
    }
    await _recorder.dispose();
    await _meterController.close();
    state.dispose();
  }

  VoiceRecorderCapabilities _buildCapabilities() {
    if (_platform.isIOS) {
      return const VoiceRecorderCapabilities(
        isSupported: true,
        needsCafToOggRemux: true,
        outputFileExtension: 'caf',
        sourceContainerLabel: 'CAF Opus',
        normalizedContainerLabel: 'Ogg Opus',
        summary: 'Records Opus in CAF and remuxes to Ogg before upload.',
      );
    }
    if (_platform.isAndroid) {
      return const VoiceRecorderCapabilities(
        isSupported: true,
        needsCafToOggRemux: false,
        outputFileExtension: 'ogg',
        sourceContainerLabel: 'Ogg Opus',
        normalizedContainerLabel: 'Ogg Opus',
        summary: 'Records Ogg Opus directly.',
      );
    }
    return const VoiceRecorderCapabilities.unsupported(
      unsupportedReason:
          'Voice recording is only supported on iOS and Android.',
      summary: 'Voice recording unavailable on this platform.',
    );
  }

  Future<void> _cancelMeterSubscription() async {
    await _meterSubscription?.cancel();
    _meterSubscription = null;
  }

  Future<void> _cleanupRecordingFiles(Set<String> paths) async {
    for (final path in paths.whereType<String>()) {
      if (path.isEmpty) {
        continue;
      }
      try {
        await _fileStore.deleteIfExists(path);
      } catch (_) {}
    }
  }

  void _updateElapsed() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) {
      return;
    }
    state.value = state.value.copyWith(
      elapsed: _now().difference(startedAt),
      status: state.value.status,
    );
  }

  VoiceRecorderBackendException _setError(
    VoiceRecorderErrorCode errorCode,
    String message, {
    Object? cause,
    VoiceRecorderPermissionStatus? permissionStatus,
    Duration? elapsed,
  }) {
    state.value = state.value.copyWith(
      status: errorCode == VoiceRecorderErrorCode.unsupported
          ? VoiceRecorderBackendStatus.unsupported
          : VoiceRecorderBackendStatus.error,
      permissionStatus: permissionStatus ?? state.value.permissionStatus,
      elapsed: elapsed ?? state.value.elapsed,
      clearArtifact: true,
      errorCode: errorCode,
      errorMessage: message,
    );
    return VoiceRecorderBackendException(
      errorCode: errorCode,
      message: message,
      cause: cause,
    );
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('MobileVoiceRecorderBackend is disposed.');
    }
  }
}

class DefaultMobileVoiceRecorderPlatform
    implements MobileVoiceRecorderPlatform {
  @override
  bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
}

class PermissionHandlerMicrophonePermissionGate
    implements MobileMicrophonePermissionGate {
  @override
  Future<MobileMicrophonePermissionStatus> requestPermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted) {
      return MobileMicrophonePermissionStatus.granted;
    }

    final requested = await Permission.microphone.request();
    if (requested.isGranted) {
      return MobileMicrophonePermissionStatus.granted;
    }
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      return MobileMicrophonePermissionStatus.blocked;
    }
    return MobileMicrophonePermissionStatus.denied;
  }
}

class AudioSessionMobileAudioSessionConfigurator
    implements MobileAudioSessionConfigurator {
  @override
  Future<void> configureForRecording() async {
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
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
  }
}

class RecordMobileAudioRecorder implements MobileAudioRecorder {
  RecordMobileAudioRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Stream<double> amplitudeStream(Duration interval) {
    return _recorder.onAmplitudeChanged(interval).map((value) => value.current);
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();

  @override
  Future<void> start({required String path}) {
    return _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        bitRate: 32000,
        sampleRate: 48000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();
}

class OggCafConverterMobileOggCafRemuxer implements MobileOggCafRemuxer {
  OggCafConverterMobileOggCafRemuxer({OggCafConverter? converter})
    : _converter = converter ?? OggCafConverter();

  final OggCafConverter _converter;

  @override
  Future<Uint8List> remuxCafToOgg(String inputPath) {
    return _converter.convertCafToOggInMemory(input: inputPath);
  }
}

class PathProviderMobileVoiceRecorderFileStore
    implements MobileVoiceRecorderFileStore {
  @override
  Future<String> createTempRecordingPath({required String extension}) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(directory.path, 'voice_$timestamp.$extension');
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<Uint8List> readAsBytes(String path) {
    return File(path).readAsBytes();
  }
}

String _buildWaveform(List<double> samples) {
  final values = samples.isEmpty ? <double>[-24.0] : List<double>.from(samples);
  final minDb = values.reduce(min);
  final maxDb = values.reduce(max);
  final range = (maxDb - minDb).abs();
  final normalized = values
      .map((sample) {
        if (range < 0.01) {
          return 128;
        }
        return ((sample - minDb) / range * 255).round().clamp(0, 255);
      })
      .toList(growable: false);
  return base64Encode(Uint8List.fromList(normalized));
}
