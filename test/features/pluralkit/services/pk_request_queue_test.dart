import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
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
}
