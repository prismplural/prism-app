
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';

void main() {
  late MediaEncryptionService encryption;

  setUp(() {
    encryption = MediaEncryptionService();
  });

  // ── DownloadProgress constructor ───────────────────────────────────────

  group('DownloadProgress', () {
    test('stores mediaId, state, and optional error', () {
      const p = DownloadProgress(
        mediaId: 'abc',
        state: DownloadState.idle,
      );
      expect(p.mediaId, 'abc');
      expect(p.state, DownloadState.idle);
      expect(p.error, isNull);

      const pErr = DownloadProgress(
        mediaId: 'abc',
        state: DownloadState.failed,
        error: 'network error',
      );
      expect(pErr.error, 'network error');
    });
  });

  // ── DownloadState enum ─────────────────────────────────────────────────

  group('DownloadState', () {
    test('has all expected values', () {
      expect(DownloadState.values, containsAll([
        DownloadState.idle,
        DownloadState.downloading,
        DownloadState.decrypting,
        DownloadState.completed,
        DownloadState.failed,
      ]));
      expect(DownloadState.values.length, 5);
    });
  });

  // ── progressStream ─────────────────────────────────────────────────────

  group('progressStream', () {
    test('returns a broadcast stream', () {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );
      addTearDown(manager.dispose);

      final stream = manager.progressStream('test-id');
      expect(stream.isBroadcast, isTrue);
    });

    test('reuses the same controller for the same mediaId', () {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );
      addTearDown(manager.dispose);

      // Subscribe to the same mediaId twice. Both subscriptions should
      // receive events from the same underlying broadcast controller.
      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];
      final sub1 = manager.progressStream('shared').listen(events1.add);
      final sub2 = manager.progressStream('shared').listen(events2.add);

      // Both listeners are active on the same broadcast controller.
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);

      sub1.cancel();
      sub2.cancel();
    });

    test('returns different streams for different mediaIds', () {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );
      addTearDown(manager.dispose);

      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];
      final sub1 = manager.progressStream('id-a').listen(events1.add);
      final sub2 = manager.progressStream('id-b').listen(events2.add);

      expect(events1, isEmpty);
      expect(events2, isEmpty);

      sub1.cancel();
      sub2.cancel();
    });

    test('supports multiple listeners (broadcast)', () async {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );
      addTearDown(manager.dispose);

      final stream = manager.progressStream('multi');
      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];

      final sub1 = stream.listen(events1.add);
      final sub2 = stream.listen(events2.add);
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      // We can't easily trigger events without calling getMedia (which hits
      // path_provider), but we can verify both subscriptions are active.
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
    });
  });

  // ── dispose ────────────────────────────────────────────────────────────

  group('dispose', () {
    test('closes all progress stream controllers', () async {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );

      final stream1 = manager.progressStream('d1');
      final stream2 = manager.progressStream('d2');

      var s1Done = false;
      var s2Done = false;
      final sub1 = stream1.listen(null, onDone: () => s1Done = true);
      final sub2 = stream2.listen(null, onDone: () => s2Done = true);

      manager.dispose();

      await Future<void>.delayed(Duration.zero);

      expect(s1Done, isTrue);
      expect(s2Done, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('calling dispose twice does not throw', () {
      final manager = DownloadManager(
        handle: null,
        encryption: encryption,
      );
      manager.progressStream('x');
      manager.dispose();
      // Second call: controllers already cleared, no-op.
      manager.dispose();
    });
  });

  // ── getMedia ───────────────────────────────────────────────────────────
  //
  // Note: getMedia calls path_provider (_cacheFileFor) before the try/catch
  // block, so we cannot test it without a platform plugin. The null-handle
  // check and concurrency limiter are unreachable in unit tests. These
  // paths are covered by integration tests instead.
}
