import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';

void main() {
  // ── UploadProgress / UploadTask constructors ────────────────────────────

  group('UploadProgress', () {
    test('stores mediaId, state, and optional error', () {
      const p = UploadProgress(
        mediaId: 'abc',
        state: UploadState.pending,
      );
      expect(p.mediaId, 'abc');
      expect(p.state, UploadState.pending);
      expect(p.error, isNull);

      const pErr = UploadProgress(
        mediaId: 'abc',
        state: UploadState.failed,
        error: 'boom',
      );
      expect(pErr.error, 'boom');
    });
  });

  group('UploadTask', () {
    test('stores fields correctly', () {
      var called = false;
      final task = UploadTask(
        mediaId: 'media-1',
        contentHash: 'hash-1',
        encryptedData: Uint8List.fromList([1, 2, 3]),
        onSuccess: () => called = true,
      );
      expect(task.mediaId, 'media-1');
      expect(task.contentHash, 'hash-1');
      expect(task.encryptedData, Uint8List.fromList([1, 2, 3]));
      task.onSuccess?.call();
      expect(called, isTrue);
    });

    test('onSuccess defaults to null', () {
      final task = UploadTask(
        mediaId: 'media-2',
        contentHash: 'hash-2',
        encryptedData: Uint8List(0),
      );
      expect(task.onSuccess, isNull);
    });
  });

  // ── progressStream ─────────────────────────────────────────────────────

  group('progressStream', () {
    test('returns a broadcast stream', () {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      final stream = queue.progressStream('test-id');
      expect(stream.isBroadcast, isTrue);
    });

    test('reuses the same controller for the same mediaId', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      // Subscribe to two references of the same mediaId stream. If the
      // controller is shared, both listeners receive the same events.
      final events1 = <UploadProgress>[];
      final events2 = <UploadProgress>[];
      final sub1 = queue.progressStream('shared').listen(events1.add);
      final sub2 = queue.progressStream('shared').listen(events2.add);
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      await queue.enqueue(UploadTask(
        mediaId: 'shared',
        contentHash: 'h',
        encryptedData: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      // Both listeners should have received the same sequence of events.
      expect(events1.length, events2.length);
      expect(events1.length, greaterThan(0));
      for (var i = 0; i < events1.length; i++) {
        expect(events1[i].state, events2[i].state);
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('returns different streams for different mediaIds', () {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      // Subscribe to two different mediaIds to confirm they are independent.
      final events1 = <UploadProgress>[];
      final events2 = <UploadProgress>[];
      queue.progressStream('id-a').listen(events1.add);
      queue.progressStream('id-b').listen(events2.add);

      // With no enqueue, both should be empty and independent.
      expect(events1, isEmpty);
      expect(events2, isEmpty);
    });
  });

  // ── Null handle → immediate failure ────────────────────────────────────

  group('null handle', () {
    test('enqueue emits pending then failed with StateError message', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      final events = <UploadProgress>[];
      final sub = queue.progressStream('m1').listen(events.add);
      addTearDown(sub.cancel);

      await queue.enqueue(UploadTask(
        mediaId: 'm1',
        contentHash: 'h1',
        encryptedData: Uint8List(0),
      ));

      // Flush microtasks so async stream events are delivered.
      await Future<void>.delayed(Duration.zero);

      expect(events, isNotEmpty);
      expect(events.first.state, UploadState.pending);
      expect(events.last.state, UploadState.failed);
      expect(events.last.error, contains('Sync handle not available'));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('onSuccess callback is NOT called on failure', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      var successCalled = false;
      await queue.enqueue(UploadTask(
        mediaId: 'm2',
        contentHash: 'h2',
        encryptedData: Uint8List(0),
        onSuccess: () => successCalled = true,
      ));

      expect(successCalled, isFalse);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ── Retry behavior with null handle ────────────────────────────────────

  group('retry behavior', () {
    test('emits uploading state 3 times (maxRetries) before failing', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      final events = <UploadProgress>[];
      final sub = queue.progressStream('retry-test').listen(events.add);
      addTearDown(sub.cancel);

      await queue.enqueue(UploadTask(
        mediaId: 'retry-test',
        contentHash: 'h',
        encryptedData: Uint8List(0),
      ));

      // Flush microtasks — the broadcast stream controller is async, so
      // events added in the last retry loop iteration may not have been
      // delivered yet.
      await Future<void>.delayed(Duration.zero);

      final uploadingEvents =
          events.where((e) => e.state == UploadState.uploading).toList();
      expect(uploadingEvents.length, 3, reason: 'Should retry 3 times');

      final failedEvents =
          events.where((e) => e.state == UploadState.failed).toList();
      expect(failedEvents.length, 1);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('total events follow pattern: pending + 3x uploading + failed', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      final states = <UploadState>[];
      final sub = queue.progressStream('pattern').listen((e) {
        states.add(e.state);
      });
      addTearDown(sub.cancel);

      await queue.enqueue(UploadTask(
        mediaId: 'pattern',
        contentHash: 'h',
        encryptedData: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(states, [
        UploadState.pending,
        UploadState.uploading,
        UploadState.uploading,
        UploadState.uploading,
        UploadState.failed,
      ]);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ── dispose ────────────────────────────────────────────────────────────

  group('dispose', () {
    test('closes all progress stream controllers', () async {
      final queue = UploadQueue(handle: null);

      final stream1 = queue.progressStream('d1');
      final stream2 = queue.progressStream('d2');

      var s1Done = false;
      var s2Done = false;
      final sub1 = stream1.listen(null, onDone: () => s1Done = true);
      final sub2 = stream2.listen(null, onDone: () => s2Done = true);

      queue.dispose();

      // Allow the done callbacks to fire.
      await Future<void>.delayed(Duration.zero);

      expect(s1Done, isTrue);
      expect(s2Done, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('emitting after dispose does not throw', () {
      final queue = UploadQueue(handle: null);
      queue.progressStream('x');
      queue.dispose();

      // Calling dispose a second time shouldn't throw either, although
      // the controllers map is cleared so there's nothing to close.
      queue.dispose();
    });
  });

  // ── Sequential queue processing ────────────────────────────────────────

  group('queue processing', () {
    test('processes multiple tasks sequentially', () async {
      final queue = UploadQueue(handle: null);
      addTearDown(queue.dispose);

      final ids = <String>[];
      queue.progressStream('q1').listen((e) {
        if (e.state == UploadState.failed) ids.add(e.mediaId);
      });
      queue.progressStream('q2').listen((e) {
        if (e.state == UploadState.failed) ids.add(e.mediaId);
      });

      // Enqueue two tasks. Both will fail (null handle) but should process
      // in order.
      await queue.enqueue(UploadTask(
        mediaId: 'q1',
        contentHash: 'h',
        encryptedData: Uint8List(0),
      ));

      await queue.enqueue(UploadTask(
        mediaId: 'q2',
        contentHash: 'h',
        encryptedData: Uint8List(0),
      ));

      await Future<void>.delayed(Duration.zero);

      expect(ids, ['q1', 'q2']);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
