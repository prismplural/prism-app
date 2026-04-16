import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/services/voice/mobile_voice_recorder_backend.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_recorder_backend.dart';

void main() {
  group('MobileVoiceRecorderBackend', () {
    test('stop returns validated audio/ogg artifact after iOS remux', () async {
      final clock = _MutableClock(DateTime(2026, 4, 15, 12));
      final fileStore = FakeMobileVoiceRecorderFileStore();
      final recorder = FakeMobileAudioRecorder();
      final remuxer = FakeMobileOggCafRemuxer();
      final backend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.iOS(),
        permissionGate: FakeMobileMicrophonePermissionGate.granted(),
        audioSessionConfigurator: FakeMobileAudioSessionConfigurator(),
        recorder: recorder,
        remuxer: remuxer,
        fileStore: fileStore,
        now: clock.call,
      );
      final statuses = <VoiceRecorderBackendStatus>[];
      backend.state.addListener(() {
        statuses.add(backend.state.value.status);
      });

      await backend.start();
      clock.advance(const Duration(seconds: 2));
      recorder.emitAmplitude(-18);
      recorder.emitAmplitude(-9);
      fileStore.seedBytes(recorder.startedPath!, _validCafOpusBytes());
      remuxer.outputBytes = _validOggOpusBytes();

      final artifact = await backend.stop();

      expect(statuses, contains(VoiceRecorderBackendStatus.preparing));
      expect(artifact.mimeType, 'audio/ogg');
      expect(artifact.durationMs, 2000);
      expect(artifact.waveformB64, isNotEmpty);
      expect(artifact.debugBackend, 'mobile-ios-opus');
      expect(fileStore.deletedPaths, contains(recorder.startedPath));
      expect(remuxer.inputs, [recorder.startedPath]);
      expect(
        backend.state.value.status,
        VoiceRecorderBackendStatus.readyToSend,
      );
      expect(
        backend.state.value.permissionStatus,
        VoiceRecorderPermissionStatus.granted,
      );
    });

    test(
      'android returns direct validated ogg capture without remux',
      () async {
        final clock = _MutableClock(DateTime(2026, 4, 15, 12));
        final fileStore = FakeMobileVoiceRecorderFileStore();
        final recorder = FakeMobileAudioRecorder();
        final remuxer = FakeMobileOggCafRemuxer();
        final backend = MobileVoiceRecorderBackend(
          platform: const FakeMobileVoiceRecorderPlatform.android(),
          permissionGate: FakeMobileMicrophonePermissionGate.granted(),
          recorder: recorder,
          remuxer: remuxer,
          fileStore: fileStore,
          now: clock.call,
        );

        await backend.start();
        clock.advance(const Duration(seconds: 1));
        recorder.emitAmplitude(-12);
        fileStore.seedBytes(recorder.startedPath!, _validOggOpusBytes());

        final artifact = await backend.stop();

        expect(artifact.mimeType, 'audio/ogg');
        expect(remuxer.inputs, isEmpty);
        expect(recorder.startedPath, endsWith('.ogg'));
      },
    );

    test('permission denied and blocked stay distinct', () async {
      final deniedBackend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.iOS(),
        permissionGate: FakeMobileMicrophonePermissionGate.denied(),
        recorder: FakeMobileAudioRecorder(),
        remuxer: FakeMobileOggCafRemuxer(),
        fileStore: FakeMobileVoiceRecorderFileStore(),
      );
      final blockedBackend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.iOS(),
        permissionGate: FakeMobileMicrophonePermissionGate.blocked(),
        recorder: FakeMobileAudioRecorder(),
        remuxer: FakeMobileOggCafRemuxer(),
        fileStore: FakeMobileVoiceRecorderFileStore(),
      );

      await expectLater(
        deniedBackend.start(),
        throwsA(
          isA<VoiceRecorderBackendException>().having(
            (error) => error.errorCode,
            'errorCode',
            VoiceRecorderErrorCode.permissionDenied,
          ),
        ),
      );
      await expectLater(
        blockedBackend.start(),
        throwsA(
          isA<VoiceRecorderBackendException>().having(
            (error) => error.errorCode,
            'errorCode',
            VoiceRecorderErrorCode.permissionBlocked,
          ),
        ),
      );
      expect(
        deniedBackend.state.value.permissionStatus,
        VoiceRecorderPermissionStatus.denied,
      );
      expect(
        blockedBackend.state.value.permissionStatus,
        VoiceRecorderPermissionStatus.blocked,
      );
    });

    test('remux failure cleans temp files and surfaces error', () async {
      final clock = _MutableClock(DateTime(2026, 4, 15, 12));
      final fileStore = FakeMobileVoiceRecorderFileStore();
      final recorder = FakeMobileAudioRecorder();
      final remuxer = FakeMobileOggCafRemuxer()
        ..error = StateError('converter failed');
      final backend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.iOS(),
        permissionGate: FakeMobileMicrophonePermissionGate.granted(),
        audioSessionConfigurator: FakeMobileAudioSessionConfigurator(),
        recorder: recorder,
        remuxer: remuxer,
        fileStore: fileStore,
        now: clock.call,
      );

      await backend.start();
      clock.advance(const Duration(seconds: 2));
      recorder.emitAmplitude(-10);
      fileStore.seedBytes(recorder.startedPath!, _validCafOpusBytes());

      await expectLater(
        backend.stop(),
        throwsA(
          isA<VoiceRecorderBackendException>().having(
            (error) => error.errorCode,
            'errorCode',
            VoiceRecorderErrorCode.remuxFailed,
          ),
        ),
      );

      expect(fileStore.deletedPaths, contains(recorder.startedPath));
      expect(backend.state.value.status, VoiceRecorderBackendStatus.error);
      expect(backend.state.value.artifact, isNull);
    });

    test('too-short recordings fail fast', () async {
      final clock = _MutableClock(DateTime(2026, 4, 15, 12));
      final fileStore = FakeMobileVoiceRecorderFileStore();
      final recorder = FakeMobileAudioRecorder();
      final backend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.android(),
        permissionGate: FakeMobileMicrophonePermissionGate.granted(),
        recorder: recorder,
        remuxer: FakeMobileOggCafRemuxer(),
        fileStore: fileStore,
        now: clock.call,
        minDuration: const Duration(milliseconds: 500),
      );

      await backend.start();
      clock.advance(const Duration(milliseconds: 300));
      recorder.emitAmplitude(-20);
      fileStore.seedBytes(recorder.startedPath!, _validOggOpusBytes());

      await expectLater(
        backend.stop(),
        throwsA(
          isA<VoiceRecorderBackendException>().having(
            (error) => error.errorCode,
            'errorCode',
            VoiceRecorderErrorCode.tooShort,
          ),
        ),
      );
      expect(fileStore.deletedPaths, contains(recorder.startedPath));
    });

    test('budget guard blocks oversized iOS remux path', () async {
      final clock = _MutableClock(DateTime(2026, 4, 15, 12));
      final fileStore = FakeMobileVoiceRecorderFileStore();
      final recorder = FakeMobileAudioRecorder();
      final backend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.iOS(),
        permissionGate: FakeMobileMicrophonePermissionGate.granted(),
        audioSessionConfigurator: FakeMobileAudioSessionConfigurator(),
        recorder: recorder,
        remuxer: FakeMobileOggCafRemuxer(),
        fileStore: fileStore,
        now: clock.call,
        maxDuration: const Duration(seconds: 5),
      );

      await backend.start();
      clock.advance(const Duration(seconds: 6));
      recorder.emitAmplitude(-16);
      fileStore.seedBytes(recorder.startedPath!, _validCafOpusBytes());

      await expectLater(
        backend.stop(),
        throwsA(
          isA<VoiceRecorderBackendException>().having(
            (error) => error.errorCode,
            'errorCode',
            VoiceRecorderErrorCode.budgetExceeded,
          ),
        ),
      );
      expect(fileStore.deletedPaths, contains(recorder.startedPath));
    });

    test('cancel owns temp-file cleanup', () async {
      final fileStore = FakeMobileVoiceRecorderFileStore();
      final recorder = FakeMobileAudioRecorder();
      final backend = MobileVoiceRecorderBackend(
        platform: const FakeMobileVoiceRecorderPlatform.android(),
        permissionGate: FakeMobileMicrophonePermissionGate.granted(),
        recorder: recorder,
        remuxer: FakeMobileOggCafRemuxer(),
        fileStore: fileStore,
      );

      await backend.start();
      fileStore.seedBytes(recorder.startedPath!, _validOggOpusBytes());
      await backend.cancel();

      expect(fileStore.deletedPaths, contains(recorder.startedPath));
      expect(recorder.cancelCallCount, 1);
      expect(backend.state.value.status, VoiceRecorderBackendStatus.idle);
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

Uint8List _validCafOpusBytes() {
  return Uint8List.fromList([
    ...'caff'.codeUnits,
    ...List<int>.filled(20, 0),
    ...'OpusHead'.codeUnits,
    ...List<int>.filled(32, 2),
  ]);
}

final class _MutableClock {
  _MutableClock(this._value);

  DateTime _value;

  DateTime call() => _value;

  void advance(Duration duration) {
    _value = _value.add(duration);
  }
}

final class FakeMobileVoiceRecorderPlatform
    implements MobileVoiceRecorderPlatform {
  const FakeMobileVoiceRecorderPlatform.iOS() : isIOS = true, isAndroid = false;

  const FakeMobileVoiceRecorderPlatform.android()
    : isIOS = false,
      isAndroid = true;

  @override
  final bool isIOS;

  @override
  final bool isAndroid;
}

final class FakeMobileMicrophonePermissionGate
    implements MobileMicrophonePermissionGate {
  const FakeMobileMicrophonePermissionGate._(this.permissionStatus);

  factory FakeMobileMicrophonePermissionGate.granted() {
    return const FakeMobileMicrophonePermissionGate._(
      MobileMicrophonePermissionStatus.granted,
    );
  }

  factory FakeMobileMicrophonePermissionGate.denied() {
    return const FakeMobileMicrophonePermissionGate._(
      MobileMicrophonePermissionStatus.denied,
    );
  }

  factory FakeMobileMicrophonePermissionGate.blocked() {
    return const FakeMobileMicrophonePermissionGate._(
      MobileMicrophonePermissionStatus.blocked,
    );
  }

  final MobileMicrophonePermissionStatus permissionStatus;

  @override
  Future<MobileMicrophonePermissionStatus> requestPermission() async {
    return permissionStatus;
  }
}

final class FakeMobileAudioSessionConfigurator
    implements MobileAudioSessionConfigurator {
  int configureCallCount = 0;

  @override
  Future<void> configureForRecording() async {
    configureCallCount += 1;
  }
}

final class FakeMobileAudioRecorder implements MobileAudioRecorder {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  String? startedPath;
  int cancelCallCount = 0;

  @override
  Stream<double> amplitudeStream(Duration interval) =>
      _amplitudeController.stream;

  void emitAmplitude(double value) {
    _amplitudeController.add(value);
  }

  @override
  Future<void> cancel() async {
    cancelCallCount += 1;
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
  }

  @override
  Future<void> start({required String path}) async {
    startedPath = path;
  }

  @override
  Future<String?> stop() async {
    return startedPath;
  }
}

final class FakeMobileOggCafRemuxer implements MobileOggCafRemuxer {
  final List<String> inputs = <String>[];
  Uint8List outputBytes = Uint8List(0);
  Object? error;

  @override
  Future<Uint8List> remuxCafToOgg(String inputPath) async {
    inputs.add(inputPath);
    if (error != null) {
      throw error!;
    }
    return outputBytes;
  }
}

final class FakeMobileVoiceRecorderFileStore
    implements MobileVoiceRecorderFileStore {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final List<String> deletedPaths = <String>[];
  int _nextId = 0;

  @override
  Future<String> createTempRecordingPath({required String extension}) async {
    _nextId += 1;
    return '/voice-test-$_nextId.$extension';
  }

  @override
  Future<void> deleteIfExists(String path) async {
    deletedPaths.add(path);
    _files.remove(path);
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    final bytes = _files[path];
    if (bytes == null) {
      throw StateError('No bytes seeded for $path');
    }
    return bytes;
  }

  void seedBytes(String path, Uint8List bytes) {
    _files[path] = bytes;
  }
}
