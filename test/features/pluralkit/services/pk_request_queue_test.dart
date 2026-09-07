import 'dart:async';
import 'dart:collection';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

void main() {
  late _ControlledTime time;
  late PkRequestQueue queue;

  setUp(() {
    time = _ControlledTime();
    queue = time.queue();
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
    final requestTimes = <DateTime>[];

    final f1 = queue.enqueue(() async {
      requestTimes.add(time.now());
      return 'a';
    });
    final f2 = queue.enqueue(() async {
      requestTimes.add(time.now());
      return 'b';
    });

    await f1;
    await f2;

    expect(
      requestTimes[1].difference(requestTimes[0]),
      PkRequestQueue.defaultMinInterval,
    );
    expect(time.delays, [PkRequestQueue.defaultMinInterval]);
  });

  test(
    'minimum interval holds the next request until its delay is released',
    () async {
      time = _ControlledTime(autoAdvance: false);
      queue = time.queue(minInterval: const Duration(milliseconds: 100));
      final requestTimes = <DateTime>[];

      final first = queue.enqueue(() async {
        requestTimes.add(time.now());
        return 'first';
      });
      final second = queue.enqueue(() async {
        requestTimes.add(time.now());
        return 'second';
      });

    await first;
    await time.nextDelayScheduled;
      expect(requestTimes, hasLength(1));
      expect(time.delays, [const Duration(milliseconds: 100)]);

      time.releaseNextDelay();
      await expectLater(second, completion('second'));
      expect(requestTimes, hasLength(2));
      expect(
        requestTimes[1].difference(requestTimes[0]),
        const Duration(milliseconds: 100),
      );
    },
  );

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

    expect(result, 'ok');
    expect(attempts, 2);
    expect(time.delays, [
      const Duration(milliseconds: 400),
      PkRequestQueue.defaultMinInterval,
    ]);
  });

  test(
    'server retryAfter holds the retry until its delay is released',
    () async {
      time = _ControlledTime(autoAdvance: false);
      final retryQueue = time.queue(minInterval: Duration.zero);
      var attempts = 0;
      final result = retryQueue.enqueue(() async {
        attempts++;
        if (attempts == 1) {
          throw const PluralKitRateLimitError(
            'slow down',
            Duration(milliseconds: 400),
          );
        }
        return 'ok';
      });

    await time.nextDelayScheduled;
      expect(attempts, 1);
      expect(time.delays, [const Duration(milliseconds: 400)]);

      time.releaseNextDelay();
      await expectLater(result, completion('ok'));
      expect(attempts, 2);
    },
  );

  // ── Pacing on failure (M19) ───────────────────────────────────────────────

  test('failed (non-429) attempts are still paced', () async {
    // A run of non-429 errors must NOT bypass _minInterval — previously
    // _lastRequestTime was updated only on success, so failures bursted at
    // full speed. Here every call throws a plain error; the queue must still
    // space them by ~minInterval.
    final paced = time.queue(minInterval: const Duration(milliseconds: 100));

    final requestTimes = <DateTime>[];
    for (var i = 0; i < 3; i++) {
      await expectLater(
        paced.enqueue(() async {
          requestTimes.add(time.now());
          throw const PluralKitApiError(500, 'boom');
        }),
        throwsA(isA<PluralKitApiError>()),
      );
    }

    expect(
      requestTimes[1].difference(requestTimes[0]),
      const Duration(milliseconds: 100),
    );
    expect(
      requestTimes[2].difference(requestTimes[1]),
      const Duration(milliseconds: 100),
    );
  });

  // ── Idempotent retry on transient errors (M19) ────────────────────────────

  test('idempotent request retries a 5xx and succeeds on attempt 2', () async {
    final queue0 = time.queue(minInterval: Duration.zero);
    var attempts = 0;

    final result = await queue0.enqueue<String>(() async {
      attempts++;
      if (attempts == 1) {
        throw const PluralKitApiError(503, 'service unavailable');
      }
      return 'ok';
    }, idempotent: true);

    expect(result, 'ok');
    expect(attempts, 2, reason: '5xx retried once for an idempotent request');
  });

  test(
    'idempotent request retries a transport failure then succeeds',
    () async {
      final queue0 = time.queue(minInterval: Duration.zero);
      var attempts = 0;

      final result = await queue0.enqueue<String>(() async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('Connection refused');
        }
        return 'ok';
      }, idempotent: true);

      expect(result, 'ok');
      expect(attempts, 2);
    },
  );

  test(
    'idempotent retry is bounded to 2 extra attempts on persistent 5xx',
    () async {
      final queue0 = time.queue(minInterval: Duration.zero);
      var attempts = 0;

      final future = queue0.enqueue<String>(() async {
        attempts++;
        throw const PluralKitApiError(500, 'boom');
      }, idempotent: true);

      await expectLater(future, throwsA(isA<PluralKitApiError>()));
      // 1 initial + 2 bounded error-retries = 3 total.
      expect(attempts, 3);
    },
  );

  test('non-idempotent request does NOT retry a 5xx', () async {
    final queue0 = time.queue(minInterval: Duration.zero);
    var attempts = 0;

    final future = queue0.enqueue<String>(() async {
      attempts++;
      throw const PluralKitApiError(500, 'boom');
    });

    await expectLater(future, throwsA(isA<PluralKitApiError>()));
    expect(attempts, 1, reason: 'writes must never auto-retry on 5xx');
  });

  test('non-idempotent request does NOT retry a transport failure', () async {
    final queue0 = time.queue(minInterval: Duration.zero);
    var attempts = 0;

    final future = queue0.enqueue<String>(() async {
      attempts++;
      throw const SocketException('Connection refused');
    });

    await expectLater(future, throwsA(isA<SocketException>()));
    expect(attempts, 1);
  });

  test('idempotent retry does not fire on a 4xx', () async {
    final queue0 = time.queue(minInterval: Duration.zero);
    var attempts = 0;

    final future = queue0.enqueue<String>(() async {
      attempts++;
      throw const PluralKitApiError(404, 'not found');
    }, idempotent: true);

    await expectLater(future, throwsA(isA<PluralKitApiError>()));
    expect(attempts, 1, reason: '4xx is the caller\'s fault — never retried');
  });

  test('429 server retryAfter is preferred over exponential backoff', () async {
    // The queue must honor the parsed server delay (ms, from the body) rather
    // than its own 2^attempt backoff.
    final queue0 = time.queue(minInterval: Duration.zero);
    var attempts = 0;

    final result = await queue0.enqueue<String>(() async {
      attempts++;
      if (attempts < 2) {
        throw const PluralKitRateLimitError(
          'slow down',
          Duration(milliseconds: 150),
        );
      }
      return 'ok';
    });

    expect(result, 'ok');
    expect(attempts, 2);
    expect(
      time.delays,
      [const Duration(milliseconds: 150)],
      reason: 'must use the 150ms server delay, not 1s exponential backoff',
    );
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
        final busQueue = time.queue(
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
      final busQueue = time.queue(minInterval: Duration.zero, bus: capture.bus);

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
        final busQueue = time.queue(
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
      final busQueue = time.queue(minInterval: Duration.zero, bus: capture.bus);

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

    test(
      'queue constructed without a bus does not throw on 429 retry',
      () async {
        // Bus is null — _bus?.emit should be a no-op rather than NPE.
        final busQueue = time.queue(minInterval: Duration.zero);

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
      },
    );
  });
}

class _ControlledTime {
  _ControlledTime({this.autoAdvance = true}) : _now = DateTime.utc(2026, 1, 1);

  DateTime _now;
  final bool autoAdvance;
  final delays = <Duration>[];
  final _pendingDelays = Queue<_PendingDelay>();
  final _nextDelayScheduled = Completer<void>();

  DateTime now() => _now;

  Future<void> get nextDelayScheduled => _nextDelayScheduled.future;

  Future<void> delay(Duration duration) async {
    delays.add(duration);
    if (autoAdvance) {
      _now = _now.add(duration);
      return;
    }

    final pending = _PendingDelay(duration);
    _pendingDelays.add(pending);
    _nextDelayScheduled.complete();
    await pending.completer.future;
  }

  void releaseNextDelay() {
    final pending = _pendingDelays.removeFirst();
    _now = _now.add(pending.duration);
    pending.completer.complete();
  }

  PkRequestQueue queue({
    Duration minInterval = PkRequestQueue.defaultMinInterval,
    int maxRetries = PkRequestQueue.defaultMaxRetries,
    PkSyncEventBus? bus,
  }) => PkRequestQueue(
    minInterval: minInterval,
    maxRetries: maxRetries,
    bus: bus,
    now: now,
    delay: delay,
  );
}

class _PendingDelay {
  _PendingDelay(this.duration);

  final Duration duration;
  final completer = Completer<void>();
}
