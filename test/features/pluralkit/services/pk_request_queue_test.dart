import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

void main() {
  late PkRequestQueue queue;

  setUp(() {
    queue = PkRequestQueue();
  });

  // ── Ordering ──────────────────────────────────────────────────────────────

  test('requests execute in order', () async {
    final results = <int>[];

    final f1 = queue.enqueue(() async {
      results.add(1);
      return 1;
    });
    final f2 = queue.enqueue(() async {
      results.add(2);
      return 2;
    });
    final f3 = queue.enqueue(() async {
      results.add(3);
      return 3;
    });

    await Future.wait([f1, f2, f3]);
    expect(results, [1, 2, 3]);
  });

  // ── Minimum interval ─────────────────────────────────────────────────────

  test('minimum interval between requests is respected', () async {
    final stopwatch = Stopwatch()..start();

    final f1 = queue.enqueue(() async => 'a');
    final f2 = queue.enqueue(() async => 'b');

    await f1;
    await f2;

    stopwatch.stop();
    // The second request should wait at least ~333ms after the first
    // (3/s bucket). Use a slightly lower threshold to account for timer
    // imprecision.
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(280));
  });

  // ── Error propagation ─────────────────────────────────────────────────────

  test('non-rate-limit errors propagate immediately', () async {
    final future = queue.enqueue(() async {
      throw Exception('some error');
    });

    expect(future, throwsA(isA<Exception>()));
  });

  // ── Rate-limit retry ──────────────────────────────────────────────────────

  test('PluralKitRateLimitError triggers retry with backoff', () async {
    var attempts = 0;

    final result = await queue.enqueue(() async {
      attempts++;
      if (attempts < 3) {
        throw const PluralKitRateLimitError();
      }
      return 'success';
    });

    expect(result, 'success');
    expect(attempts, 3);
  });

  test('max retries exhausted propagates the error', () async {
    var attempts = 0;

    final future = queue.enqueue<String>(() async {
      attempts++;
      throw const PluralKitRateLimitError();
    });

    await expectLater(future, throwsA(isA<PluralKitRateLimitError>()));
    // Should attempt 1 initial + 3 retries = 4 total
    expect(attempts, 4);
  });

  test('rate-limit retry honors server-provided retryAfter', () async {
    var attempts = 0;
    final stopwatch = Stopwatch()..start();

    final result = await queue.enqueue(() async {
      attempts++;
      if (attempts < 2) {
        throw const PluralKitRateLimitError(
          'slow down',
          Duration(milliseconds: 400),
        );
      }
      return 'ok';
    });

    stopwatch.stop();
    expect(result, 'ok');
    expect(attempts, 2);
    // Should have waited roughly the server-provided 400ms before retry.
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(350));
  });

  // ── Multiple queued requests ──────────────────────────────────────────────

  test('multiple queued requests all complete', () async {
    final futures = <Future<int>>[];
    for (var i = 0; i < 5; i++) {
      final val = i;
      futures.add(queue.enqueue(() async => val * 10));
    }

    final results = await Future.wait(futures);
    expect(results, [0, 10, 20, 30, 40]);
  });

  // ── Event emission ────────────────────────────────────────────────────────

  group('event emission', () {
    setUp(markPkBusMainIsolate);
    tearDown(resetPkBusMainIsolateForTest);

    test(
      'a single 429 retry that succeeds on attempt 2 emits one PkRateLimitHit',
      () async {
        final capture = PkSyncEventBusCapture();
        final busQueue = PkRequestQueue(
          minInterval: Duration.zero,
          bus: capture.bus,
        );

        var attempts = 0;
        final result = await busQueue.enqueue(() async {
          attempts++;
          if (attempts < 2) {
            throw const PluralKitRateLimitError(
              'slow down',
              Duration(seconds: 4),
            );
          }
          return 'ok';
        });

        expect(result, 'ok');
        expect(attempts, 2);
        expect(capture.events, hasLength(1));
        final event = capture.events.single as PkRateLimitHit;
        expect(event.attempt, 1);
        expect(event.backoffSeconds, 4);
      },
    );

    test('two 429 retries emits two events with attempt 1 and 2', () async {
      final capture = PkSyncEventBusCapture();
      final busQueue = PkRequestQueue(
        minInterval: Duration.zero,
        bus: capture.bus,
      );

      var attempts = 0;
      final result = await busQueue.enqueue(() async {
        attempts++;
        if (attempts < 3) {
          throw const PluralKitRateLimitError(
            'slow down',
            Duration(seconds: 2),
          );
        }
        return 'ok';
      });

      expect(result, 'ok');
      expect(attempts, 3);
      expect(capture.events, hasLength(2));
      final first = capture.events[0] as PkRateLimitHit;
      final second = capture.events[1] as PkRateLimitHit;
      expect(first.attempt, 1);
      expect(first.backoffSeconds, 2);
      expect(second.attempt, 2);
      expect(second.backoffSeconds, 2);
    });

    test(
      'max retries exhausted emits 3 events before the final throw',
      () async {
        final capture = PkSyncEventBusCapture();
        final busQueue = PkRequestQueue(
          minInterval: Duration.zero,
          // 3 retries (per spec: "3 retries then propagate").
          maxRetries: 3,
          bus: capture.bus,
        );

        var attempts = 0;
        final future = busQueue.enqueue<String>(() async {
          attempts++;
          throw const PluralKitRateLimitError(
            'slow down',
            Duration(seconds: 1),
          );
        });

        await expectLater(future, throwsA(isA<PluralKitRateLimitError>()));
        // 1 initial attempt + 3 retries = 4 total invocations.
        expect(attempts, 4);
        // But only 3 events: one per retry decision (before the final throw).
        expect(capture.events, hasLength(3));
        expect(
          capture.events.map((e) => (e as PkRateLimitHit).attempt).toList(),
          [1, 2, 3],
        );
      },
    );

    test('a non-429 error does NOT emit PkRateLimitHit', () async {
      final capture = PkSyncEventBusCapture();
      final busQueue = PkRequestQueue(
        minInterval: Duration.zero,
        bus: capture.bus,
      );

      // PluralKitApiError(500, ...) — non-rate-limit API error.
      await expectLater(
        busQueue.enqueue(() async {
          throw const PluralKitApiError(500, 'kaboom');
        }),
        throwsA(isA<PluralKitApiError>()),
      );

      // A plain Exception too.
      await expectLater(
        busQueue.enqueue(() async {
          throw Exception('boom');
        }),
        throwsA(isA<Exception>()),
      );

      expect(capture.events, isEmpty);
    });

    test('queue constructed without a bus does not throw on 429 retry',
        () async {
      // Bus is null — _bus?.emit should be a no-op rather than NPE.
      final busQueue = PkRequestQueue(minInterval: Duration.zero);

      var attempts = 0;
      final result = await busQueue.enqueue(() async {
        attempts++;
        if (attempts < 2) {
          throw const PluralKitRateLimitError(
            'slow down',
            Duration(seconds: 1),
          );
        }
        return 'ok';
      });

      expect(result, 'ok');
      expect(attempts, 2);
    });
  });
}
