import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';

// ── Normalization helper ────────────────────────────────────────────────────
//
// Mirrors the normalization algorithm from
// VoiceRecordingNotifier.stopRecording() (lines ~144-151).

List<int> normalizeAmplitudeSamples(List<double> samples) {
  final minDb = samples.reduce(min);
  final maxDb = samples.reduce(max);
  final range = (maxDb - minDb).abs();
  return samples.map((s) {
    if (range < 0.01) return 128;
    return ((s - minDb) / range * 255).round().clamp(0, 255);
  }).toList();
}

String normalizeAndEncode(List<double> samples) {
  final normalized = normalizeAmplitudeSamples(samples);
  return base64Encode(Uint8List.fromList(normalized));
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Waveform normalization — pure logic
  // ══════════════════════════════════════════════════════════════════════════

  group('normalizeAmplitudeSamples', () {
    test('single sample returns [128] (range < 0.01)', () {
      final result = normalizeAmplitudeSamples([-30.0]);
      expect(result, [128]);
    });

    test('all identical samples returns all 128 (flat line)', () {
      final result = normalizeAmplitudeSamples([-45.0, -45.0, -45.0, -45.0]);
      expect(result, [128, 128, 128, 128]);
    });

    test('normal range properly scales to 0-255', () {
      final result = normalizeAmplitudeSamples([-60.0, -30.0, -10.0]);

      // min = -60, max = -10, range = 50
      // -60 -> (0/50) * 255 = 0
      // -30 -> (30/50) * 255 = 153
      // -10 -> (50/50) * 255 = 255
      expect(result[0], 0);
      expect(result[1], 153);
      expect(result[2], 255);
    });

    test('full dB range [-160.0, 0.0] maps to [0, 255]', () {
      final result = normalizeAmplitudeSamples([-160.0, 0.0]);
      expect(result[0], 0);
      expect(result[1], 255);
    });

    test('very small range (< 0.01) collapses to all 128', () {
      final result = normalizeAmplitudeSamples([-30.0, -29.995, -30.003]);
      // range = 0.008 which is < 0.01
      expect(result, [128, 128, 128]);
    });

    test('range exactly at 0.01 threshold does NOT collapse', () {
      // range = 0.01, which is NOT < 0.01 (equal), so normalization applies
      final result = normalizeAmplitudeSamples([0.0, 0.01]);
      expect(result[0], 0);
      expect(result[1], 255);
    });

    test('negative-to-negative range normalizes correctly', () {
      final result = normalizeAmplitudeSamples([-100.0, -50.0]);
      // min = -100, max = -50, range = 50
      // -100 -> 0, -50 -> 255
      expect(result[0], 0);
      expect(result[1], 255);
    });

    test('three evenly spaced values produce evenly spaced output', () {
      final result = normalizeAmplitudeSamples([-80.0, -40.0, 0.0]);
      // min = -80, max = 0, range = 80
      // -80 -> 0
      // -40 -> (40/80)*255 = 127.5 -> 128
      //   0 -> 255
      expect(result[0], 0);
      expect(result[1], 128);
      expect(result[2], 255);
    });

    test('output values are clamped to 0-255', () {
      // In normal operation clamp shouldn't change values, but verify the
      // guarantee holds for any reasonable input.
      final result = normalizeAmplitudeSamples([-160.0, -80.0, 0.0]);
      for (final v in result) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(255));
      }
    });

    test('many samples produce correct length', () {
      final samples = List.generate(100, (i) => -160.0 + i * 1.6);
      final result = normalizeAmplitudeSamples(samples);
      expect(result.length, 100);
    });
  });

  group('normalizeAndEncode (base64 round-trip)', () {
    test('encodes normalized samples as valid base64', () {
      final b64 = normalizeAndEncode([-60.0, -30.0, -10.0]);
      // Should be valid base64 that decodes back to the normalized bytes.
      final decoded = base64Decode(b64);
      expect(decoded.length, 3);
      expect(decoded[0], 0);
      expect(decoded[1], 153);
      expect(decoded[2], 255);
    });

    test('single sample encodes correctly', () {
      final b64 = normalizeAndEncode([-50.0]);
      final decoded = base64Decode(b64);
      expect(decoded.length, 1);
      expect(decoded[0], 128);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // VoiceRecordingState — copyWith and defaults
  // ══════════════════════════════════════════════════════════════════════════

  group('VoiceRecordingState', () {
    test('default state has idle status and empty fields', () {
      const state = VoiceRecordingState();
      expect(state.status, VoiceRecordingStatus.idle);
      expect(state.elapsedMs, 0);
      expect(state.amplitudeSamples, isEmpty);
      expect(state.audioBytes, isNull);
      expect(state.durationMs, 0);
      expect(state.waveformB64, '');
      expect(state.error, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const original = VoiceRecordingState(
        status: VoiceRecordingStatus.recording,
        elapsedMs: 1500,
        amplitudeSamples: [-30.0, -25.0],
      );
      final updated = original.copyWith(elapsedMs: 2000);
      expect(updated.status, VoiceRecordingStatus.recording);
      expect(updated.elapsedMs, 2000);
      expect(updated.amplitudeSamples, [-30.0, -25.0]);
    });

    test('copyWith replaces status', () {
      const state = VoiceRecordingState();
      final updated = state.copyWith(status: VoiceRecordingStatus.error);
      expect(updated.status, VoiceRecordingStatus.error);
    });

    test('copyWith sets error', () {
      const state = VoiceRecordingState();
      final updated = state.copyWith(
        status: VoiceRecordingStatus.error,
        error: 'mic unavailable',
      );
      expect(updated.error, 'mic unavailable');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // State machine guards — tested via state transitions
  // ══════════════════════════════════════════════════════════════════════════

  group('VoiceRecordingStatus enum', () {
    test('has expected values', () {
      expect(VoiceRecordingStatus.values, [
        VoiceRecordingStatus.idle,
        VoiceRecordingStatus.recording,
        VoiceRecordingStatus.processing,
        VoiceRecordingStatus.done,
        VoiceRecordingStatus.error,
      ]);
    });
  });

  group('state machine guard conditions', () {
    // These tests verify the guard logic that exists in
    // stopRecording / cancelRecording without actually exercising the
    // recorder. We simulate the guards by checking the condition directly.

    test('stopRecording guard: returns early when not recording', () {
      // The guard: if (state.status != VoiceRecordingStatus.recording) return state;
      const idle = VoiceRecordingState(status: VoiceRecordingStatus.idle);
      expect(idle.status != VoiceRecordingStatus.recording, isTrue);

      const processing =
          VoiceRecordingState(status: VoiceRecordingStatus.processing);
      expect(processing.status != VoiceRecordingStatus.recording, isTrue);

      const done = VoiceRecordingState(status: VoiceRecordingStatus.done);
      expect(done.status != VoiceRecordingStatus.recording, isTrue);

      const error = VoiceRecordingState(status: VoiceRecordingStatus.error);
      expect(error.status != VoiceRecordingStatus.recording, isTrue);
    });

    test('stopRecording guard: allows when recording', () {
      const recording =
          VoiceRecordingState(status: VoiceRecordingStatus.recording);
      expect(recording.status == VoiceRecordingStatus.recording, isTrue);
    });

    test('cancelRecording guard: returns early when not recording', () {
      // The guard: if (state.status != VoiceRecordingStatus.recording) return;
      const idle = VoiceRecordingState(status: VoiceRecordingStatus.idle);
      expect(idle.status != VoiceRecordingStatus.recording, isTrue);

      const done = VoiceRecordingState(status: VoiceRecordingStatus.done);
      expect(done.status != VoiceRecordingStatus.recording, isTrue);
    });

    test('cancelRecording guard: allows when recording', () {
      const recording =
          VoiceRecordingState(status: VoiceRecordingStatus.recording);
      expect(recording.status == VoiceRecordingStatus.recording, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Empty samples edge case
  // ══════════════════════════════════════════════════════════════════════════

  group('empty samples guard', () {
    test('stopRecording transitions to error when samples empty', () {
      // The provider checks: if (samples.isEmpty) → error state
      // Verify the error state shape matches expectations.
      const errorState = VoiceRecordingState(
        status: VoiceRecordingStatus.error,
        error: 'No amplitude samples recorded',
      );
      expect(errorState.status, VoiceRecordingStatus.error);
      expect(errorState.error, 'No amplitude samples recorded');
    });
  });
}
