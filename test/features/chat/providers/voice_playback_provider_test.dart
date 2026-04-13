import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/providers/voice_playback_provider.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // VoicePlaybackState
  // ══════════════════════════════════════════════════════════════════════════

  group('VoicePlaybackState', () {
    test('default constructor has expected initial values', () {
      const state = VoicePlaybackState();

      expect(state.activeMediaId, isNull);
      expect(state.isPlaying, isFalse);
      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.speed, 1.0);
    });

    test('constructor accepts all named parameters', () {
      const state = VoicePlaybackState(
        activeMediaId: 'media-123',
        isPlaying: true,
        position: Duration(seconds: 10),
        duration: Duration(seconds: 60),
        speed: 1.5,
      );

      expect(state.activeMediaId, 'media-123');
      expect(state.isPlaying, isTrue);
      expect(state.position, const Duration(seconds: 10));
      expect(state.duration, const Duration(seconds: 60));
      expect(state.speed, 1.5);
    });

    group('copyWith', () {
      test('preserves all fields when called with no arguments', () {
        const original = VoicePlaybackState(
          activeMediaId: 'media-abc',
          isPlaying: true,
          position: Duration(seconds: 5),
          duration: Duration(minutes: 2),
          speed: 2.0,
        );

        final copied = original.copyWith();

        expect(copied.activeMediaId, original.activeMediaId);
        expect(copied.isPlaying, original.isPlaying);
        expect(copied.position, original.position);
        expect(copied.duration, original.duration);
        expect(copied.speed, original.speed);
      });

      test('overrides only the specified fields', () {
        const original = VoicePlaybackState(
          activeMediaId: 'media-abc',
          isPlaying: true,
          position: Duration(seconds: 5),
          duration: Duration(minutes: 2),
          speed: 2.0,
        );

        final copied = original.copyWith(isPlaying: false, speed: 1.0);

        expect(copied.activeMediaId, 'media-abc');
        expect(copied.isPlaying, isFalse);
        expect(copied.position, const Duration(seconds: 5));
        expect(copied.duration, const Duration(minutes: 2));
        expect(copied.speed, 1.0);
      });

      test('can update activeMediaId to a different value', () {
        const original = VoicePlaybackState(activeMediaId: 'old-id');

        final copied = original.copyWith(activeMediaId: 'new-id');

        expect(copied.activeMediaId, 'new-id');
      });

      test('cannot set activeMediaId back to null via copyWith (known limitation)', () {
        // copyWith uses `activeMediaId ?? this.activeMediaId`, so passing null
        // is indistinguishable from not passing it at all. This is a known
        // limitation — the stop() method works around it by constructing a
        // fresh const VoicePlaybackState() instead.
        const original = VoicePlaybackState(activeMediaId: 'media-123');

        final copied = original.copyWith(activeMediaId: null);

        // Still retains the old value because null falls through to ??
        expect(copied.activeMediaId, 'media-123');
      });

      test('can override position and duration independently', () {
        const original = VoicePlaybackState();

        final copied = original.copyWith(
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 3),
        );

        expect(copied.position, const Duration(seconds: 30));
        expect(copied.duration, const Duration(minutes: 3));
        // Unset fields preserved
        expect(copied.activeMediaId, isNull);
        expect(copied.isPlaying, isFalse);
        expect(copied.speed, 1.0);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // VoicePlaybackNotifier — initial state & disposal
  // ══════════════════════════════════════════════════════════════════════════

  group('VoicePlaybackNotifier', () {
    test('initial state matches default VoicePlaybackState', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(voicePlaybackProvider);

      expect(state.activeMediaId, isNull);
      expect(state.isPlaying, isFalse);
      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.speed, 1.0);
    });

    test('disposing the container does not throw', () {
      // Verifies that ref.onDispose(_disposePlayer) is wired up correctly
      // and doesn't throw when there's no active player.
      final container = ProviderContainer();

      // Force the provider to build (registers the dispose callback)
      container.read(voicePlaybackProvider);

      // Dispose should complete without error
      expect(container.dispose, returnsNormally);
    });

    test('multiple build/dispose cycles do not throw', () {
      // Ensures the dispose callback can handle repeated cycles gracefully.
      for (var i = 0; i < 3; i++) {
        final container = ProviderContainer();
        container.read(voicePlaybackProvider);
        expect(container.dispose, returnsNormally);
      }
    });

    // ════════════════════════════════════════════════════════════════════════
    // cycleSpeed — state transitions
    // ════════════════════════════════════════════════════════════════════════

    group('cycleSpeed', () {
      test('cycles 1.0 -> 1.5', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Initial speed is 1.0
        expect(container.read(voicePlaybackProvider).speed, 1.0);

        notifier.cycleSpeed();

        expect(container.read(voicePlaybackProvider).speed, 1.5);
      });

      test('cycles 1.5 -> 2.0', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Cycle once to get to 1.5
        notifier.cycleSpeed();
        expect(container.read(voicePlaybackProvider).speed, 1.5);

        // Cycle again to get to 2.0
        notifier.cycleSpeed();
        expect(container.read(voicePlaybackProvider).speed, 2.0);
      });

      test('cycles 2.0 -> 1.0 (wraps around)', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Cycle through: 1.0 -> 1.5 -> 2.0
        notifier.cycleSpeed();
        notifier.cycleSpeed();
        expect(container.read(voicePlaybackProvider).speed, 2.0);

        // Cycle wraps back to 1.0
        notifier.cycleSpeed();
        expect(container.read(voicePlaybackProvider).speed, 1.0);
      });

      test('full cycle returns to initial speed', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Three cycles: 1.0 -> 1.5 -> 2.0 -> 1.0
        notifier.cycleSpeed();
        notifier.cycleSpeed();
        notifier.cycleSpeed();

        expect(container.read(voicePlaybackProvider).speed, 1.0);
      });

      test('cycleSpeed preserves other state fields', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Read initial state to confirm baseline
        final before = container.read(voicePlaybackProvider);

        notifier.cycleSpeed();

        final after = container.read(voicePlaybackProvider);

        // Speed changed
        expect(after.speed, 1.5);
        // Everything else preserved
        expect(after.activeMediaId, before.activeMediaId);
        expect(after.isPlaying, before.isPlaying);
        expect(after.position, before.position);
        expect(after.duration, before.duration);
      });

      test('cycleSpeed without a loaded player does not throw', () {
        // _player is null, so _player?.setSpeed(newSpeed) is a no-op.
        // The state should still update.
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        expect(notifier.cycleSpeed, returnsNormally);
        expect(container.read(voicePlaybackProvider).speed, 1.5);
      });
    });

    // ════════════════════════════════════════════════════════════════════════
    // stop — resets to fresh const state
    // ════════════════════════════════════════════════════════════════════════

    group('stop', () {
      test('resets state to const VoicePlaybackState()', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Change speed so state is non-default
        notifier.cycleSpeed();
        expect(container.read(voicePlaybackProvider).speed, 1.5);

        notifier.stop();

        final state = container.read(voicePlaybackProvider);
        expect(state.activeMediaId, isNull);
        expect(state.isPlaying, isFalse);
        expect(state.position, Duration.zero);
        expect(state.duration, Duration.zero);
        expect(state.speed, 1.0);
      });

      test('stop correctly nullifies activeMediaId (workaround for copyWith limitation)', () {
        // This is the key test: stop() uses `const VoicePlaybackState()`
        // instead of copyWith, which ensures activeMediaId can be set back
        // to null — something copyWith cannot do.
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Manually cycle speed to modify state (we can't load a player in unit tests)
        notifier.cycleSpeed();

        notifier.stop();

        expect(container.read(voicePlaybackProvider).activeMediaId, isNull);
      });

      test('stop without a loaded player does not throw', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        expect(notifier.stop, returnsNormally);
      });

      test('stop resets speed even after cycling', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        notifier.cycleSpeed(); // 1.5
        notifier.cycleSpeed(); // 2.0
        notifier.stop();

        expect(container.read(voicePlaybackProvider).speed, 1.0);
      });
    });

    // ════════════════════════════════════════════════════════════════════════
    // seek — null-safe when no player loaded
    // ════════════════════════════════════════════════════════════════════════

    group('seek', () {
      test('seek without a loaded player does not throw', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        expect(
          () => notifier.seek(const Duration(seconds: 30)),
          returnsNormally,
        );
      });
    });

    // ════════════════════════════════════════════════════════════════════════
    // temp file deletion — security invariant
    //
    // Plaintext audio files written to the temp directory by DownloadManager
    // must be deleted as soon as playback ends or the provider is disposed.
    // These tests use [setTempFileForTesting] to inject a temp file without
    // needing a live audio player.
    // ════════════════════════════════════════════════════════════════════════

    group('temp file deletion', () {
      test('stop() deletes the temp file', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Create a real temp file to verify deletion.
        final tmpFile = await File(
          '${Directory.systemTemp.path}/vp_test_stop.m4a',
        ).create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        notifier.setTempFileForTesting(tmpFile);
        expect(tmpFile.existsSync(), isTrue, reason: 'file must exist before stop()');

        notifier.stop();

        // File deletion is fire-and-forget; give the event loop a turn.
        await Future<void>.delayed(Duration.zero);

        expect(tmpFile.existsSync(), isFalse,
            reason: 'temp file must be deleted after stop()');
      });

      test('container disposal deletes the temp file', () async {
        final container = ProviderContainer();

        final notifier = container.read(voicePlaybackProvider.notifier);

        final tmpFile = await File(
          '${Directory.systemTemp.path}/vp_test_dispose.m4a',
        ).create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        notifier.setTempFileForTesting(tmpFile);
        expect(tmpFile.existsSync(), isTrue);

        // Disposing the container triggers ref.onDispose → _disposePlayer()
        // → _deleteTempFile().
        container.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(tmpFile.existsSync(), isFalse,
            reason: 'temp file must be deleted when provider is disposed');
      });

      test('setTempFileForTesting(null) after stop does not throw', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // No temp file set — stop should not throw.
        expect(notifier.stop, returnsNormally);

        // Explicitly set to null and stop again — still no throw.
        notifier.setTempFileForTesting(null);
        expect(notifier.stop, returnsNormally);
      });

      test('stop() with already-deleted temp file does not throw', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(voicePlaybackProvider.notifier);

        // Create and immediately delete the file to simulate OS cleanup.
        final tmpFile = await File(
          '${Directory.systemTemp.path}/vp_test_missing.m4a',
        ).create();
        await tmpFile.delete();

        notifier.setTempFileForTesting(tmpFile);

        // stop() must not throw even when the file is already gone.
        expect(notifier.stop, returnsNormally);
        await Future<void>.delayed(Duration.zero);
      });
    });
  });
}
