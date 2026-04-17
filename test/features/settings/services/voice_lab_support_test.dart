import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/services/voice_lab_support.dart';

void main() {
  group('buildVoiceLabCapability', () {
    test('uses CAF remux path on iOS when Opus is supported', () {
      final capability = buildVoiceLabCapability(
        isWeb: false,
        platform: TargetPlatform.iOS,
        opusRecordingSupported: true,
      );

      expect(capability.isSupported, isTrue);
      expect(capability.needsCafToOggRemux, isTrue);
      expect(capability.sourceContainerLabel, 'CAF Opus');
      expect(capability.normalizedContainerLabel, 'Ogg Opus');
    });

    test('uses direct Ogg path on Android when Opus is supported', () {
      final capability = buildVoiceLabCapability(
        isWeb: false,
        platform: TargetPlatform.android,
        opusRecordingSupported: true,
      );

      expect(capability.isSupported, isTrue);
      expect(capability.needsCafToOggRemux, isFalse);
      expect(capability.outputFileExtension, 'opus');
    });

    test('rejects macOS for this spike even if recorder reports Opus', () {
      final capability = buildVoiceLabCapability(
        isWeb: false,
        platform: TargetPlatform.macOS,
        opusRecordingSupported: true,
      );

      expect(capability.isSupported, isFalse);
      expect(capability.unsupportedReason, contains('macOS'));
    });

    test('rejects web', () {
      final capability = buildVoiceLabCapability(
        isWeb: true,
        platform: TargetPlatform.android,
        opusRecordingSupported: true,
      );

      expect(capability.isSupported, isFalse);
      expect(capability.unsupportedReason, contains('Web'));
    });
  });

  group('detectVoiceLabContainer', () {
    test('detects Ogg Opus headers', () {
      final bytes = Uint8List.fromList([
        ...'OggS'.codeUnits,
        0,
        2,
        3,
        ...'OpusHead'.codeUnits,
      ]);

      expect(detectVoiceLabContainer(bytes), 'Ogg Opus');
    });

    test('detects CAF Opus headers', () {
      // Fake CAF: 'caff' header + 4 padding bytes + lowercase 'opus' FourCC
      // at offset 8, where _detectCafCodec's fallback scanner looks.
      final bytes = Uint8List.fromList([
        ...'caff'.codeUnits,
        0, 0, 0, 0,
        ...'opus'.codeUnits,
      ]);

      expect(detectVoiceLabContainer(bytes), 'CAF Opus');
    });

    test('returns unknown for unrelated bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);

      expect(detectVoiceLabContainer(bytes), 'Unknown');
    });
  });

  group('chooseVoiceLabPlaybackMode', () {
    test('uses buffer stream for Ogg Opus bytes', () {
      final bytes = Uint8List.fromList([
        ...'OggS'.codeUnits,
        0,
        2,
        3,
        ...'OpusHead'.codeUnits,
      ]);

      expect(
        chooseVoiceLabPlaybackMode(bytes),
        VoiceLabPlaybackMode.bufferStream,
      );
    });

    test('uses loadMem for non-Opus Ogg bytes', () {
      final bytes = Uint8List.fromList([
        ...'OggS'.codeUnits,
        0,
        2,
        3,
        ...'vorbis'.codeUnits,
      ]);

      expect(chooseVoiceLabPlaybackMode(bytes), VoiceLabPlaybackMode.loadMem);
    });
  });

  group('formatVoiceLabBytes', () {
    test('formats bytes under one kilobyte', () {
      expect(formatVoiceLabBytes(999), '999 B');
    });

    test('formats kilobytes', () {
      expect(formatVoiceLabBytes(1536), '1.5 KB');
    });
  });
}
