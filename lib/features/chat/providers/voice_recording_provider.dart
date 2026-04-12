import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

enum VoiceRecordingStatus { idle, recording, processing, done, error }

enum VoiceRecordingError {
  /// OS permission prompt was dismissed without granting access.
  permissionDenied,

  /// Permission was previously denied and is now permanently blocked —
  /// user must open Settings to grant it.
  permissionBlocked,

  /// Recording failed for a non-permission reason (hardware, codec, etc.).
  unknown,
}

class VoiceRecordingState {
  const VoiceRecordingState({
    this.status = VoiceRecordingStatus.idle,
    this.elapsedMs = 0,
    this.amplitudeSamples = const [],
    this.audioBytes,
    this.durationMs = 0,
    this.waveformB64 = '',
    this.errorType,
  });

  final VoiceRecordingStatus status;
  final int elapsedMs;
  final List<double> amplitudeSamples;
  final Uint8List? audioBytes;
  final int durationMs;
  final String waveformB64;

  /// Set when [status] is [VoiceRecordingStatus.error]. The widget layer
  /// maps this to a localized string.
  final VoiceRecordingError? errorType;

  VoiceRecordingState copyWith({
    VoiceRecordingStatus? status,
    int? elapsedMs,
    List<double>? amplitudeSamples,
    Uint8List? audioBytes,
    int? durationMs,
    String? waveformB64,
    VoiceRecordingError? errorType,
  }) {
    return VoiceRecordingState(
      status: status ?? this.status,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      amplitudeSamples: amplitudeSamples ?? this.amplitudeSamples,
      audioBytes: audioBytes ?? this.audioBytes,
      durationMs: durationMs ?? this.durationMs,
      waveformB64: waveformB64 ?? this.waveformB64,
      errorType: errorType ?? this.errorType,
    );
  }
}

class VoiceRecordingNotifier extends Notifier<VoiceRecordingState> {
  FlutterSoundRecorder? _recorder;
  StreamSubscription<RecordingDisposition>? _progressSub;
  String? _tempFilePath;
  static const _uuid = Uuid();
  final List<double> _samples = [];

  @override
  VoiceRecordingState build() {
    ref.onDispose(_cleanup);
    return const VoiceRecordingState();
  }

  void _cleanup() {
    _progressSub?.cancel();
    _progressSub = null;
    _samples.clear();
    _recorder?.closeRecorder();
    _recorder = null;
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).deleteSync();
      } catch (_) {}
      _tempFilePath = null;
    }
  }

  Future<void> startRecording() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        state = VoiceRecordingState(
          status: VoiceRecordingStatus.error,
          errorType: micStatus.isPermanentlyDenied
              ? VoiceRecordingError.permissionBlocked
              : VoiceRecordingError.permissionDenied,
        );
        return;
      }

      _recorder ??= FlutterSoundRecorder();
      await _recorder!.openRecorder();

      final dir = await getTemporaryDirectory();
      _tempFilePath = '${dir.path}/voice_${_uuid.v4()}.ogg';

      await _recorder!.setSubscriptionDuration(
        const Duration(milliseconds: 50),
      );

      await _recorder!.startRecorder(
        toFile: _tempFilePath,
        codec: Codec.opusOGG,
        sampleRate: 48000,
        numChannels: 1,
      );

      _progressSub = _recorder!.onProgress!.listen((event) {
        _samples.add(event.decibels ?? -160.0);
        state = state.copyWith(
          elapsedMs: event.duration.inMilliseconds,
          amplitudeSamples: List.unmodifiable(_samples),
        );
      });

      await HapticFeedback.mediumImpact();

      state = state.copyWith(status: VoiceRecordingStatus.recording);
    } catch (e) {
      state = const VoiceRecordingState(
        status: VoiceRecordingStatus.error,
        errorType: VoiceRecordingError.unknown,
      );
    }
  }

  Future<VoiceRecordingState> stopRecording() async {
    if (state.status != VoiceRecordingStatus.recording) return state;

    try {
      state = state.copyWith(status: VoiceRecordingStatus.processing);

      await _recorder!.stopRecorder();
      await _progressSub?.cancel();
      _progressSub = null;

      await _recorder!.closeRecorder();
      _recorder = null;

      final bytes = await File(_tempFilePath!).readAsBytes();
      await _deleteTempFile();

      final samples = _samples;
      if (samples.isEmpty) {
        state = const VoiceRecordingState(
          status: VoiceRecordingStatus.error,
          errorType: VoiceRecordingError.unknown,
        );
        return state;
      }

      final minDb = samples.reduce(min);
      final maxDb = samples.reduce(max);
      final range = (maxDb - minDb).abs();
      final normalized = samples.map((s) {
        if (range < 0.01) return 128;
        return ((s - minDb) / range * 255).round().clamp(0, 255);
      }).toList();
      final waveformB64 = base64Encode(Uint8List.fromList(normalized));

      state = state.copyWith(
        status: VoiceRecordingStatus.done,
        audioBytes: bytes,
        durationMs: state.elapsedMs,
        waveformB64: waveformB64,
      );

      await HapticFeedback.lightImpact();

      return state;
    } catch (e) {
      state = const VoiceRecordingState(
        status: VoiceRecordingStatus.error,
        errorType: VoiceRecordingError.unknown,
      );
      return state;
    }
  }

  Future<void> cancelRecording() async {
    if (state.status != VoiceRecordingStatus.recording) return;

    try {
      await _recorder?.stopRecorder();
    } catch (_) {
      // Fire-and-forget: ignore errors during cancellation.
    }

    try {
      await _recorder?.closeRecorder();
    } catch (_) {}
    _recorder = null;

    await _progressSub?.cancel();
    _progressSub = null;

    await _deleteTempFile();

    state = const VoiceRecordingState();

    await HapticFeedback.lightImpact();
  }

  void reset() {
    _samples.clear();
    _deleteTempFile();
    state = const VoiceRecordingState();
  }

  Future<void> _deleteTempFile() async {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _tempFilePath = null;
    }
  }
}

final voiceRecordingProvider =
    NotifierProvider.autoDispose<VoiceRecordingNotifier, VoiceRecordingState>(
  VoiceRecordingNotifier.new,
);
