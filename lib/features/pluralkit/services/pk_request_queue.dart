import 'dart:async';
import 'dart:math';

import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Rate-limited request queue for PluralKit API (max 3 requests/second,
/// PK's write limit).
///
/// PK actually allows 10/s GETs and 3/s writes; we use a single 3/s bucket
/// (333ms interval) — the worst-case write cap covers everything without
/// complicating callers. Enqueue async operations and they will be executed
/// sequentially. Handles 429 responses with backoff, honoring any
/// server-provided delay (body `retry_after`, falling back to headers).
/// Pacing is enforced after every completed attempt — success or error — so a
/// run of failures can't burst past the rate budget. Idempotent requests
/// (passed via `enqueue(..., idempotent: true)`) additionally retry transient
/// transport / 5xx errors a couple of times.
class PkRequestQueue {
  static const defaultMinInterval = Duration(milliseconds: 333);
  static const defaultMaxRetries = 3;

  final Duration _minInterval;
  final int _maxRetries;
  final PkSyncEventBus? _bus;

  final _queue = <_QueueEntry<dynamic>>[];
  bool _processing = false;
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  PkRequestQueue({
    Duration minInterval = defaultMinInterval,
    int maxRetries = defaultMaxRetries,
    PkSyncEventBus? bus,
  }) : _minInterval = minInterval,
       _maxRetries = maxRetries,
       _bus = bus;

  /// Enqueue a request. Returns a Future that completes with the result
  /// once the request has been executed (respecting rate limits).
  ///
  /// [idempotent] requests (GETs — no side effects) additionally retry
  /// transport failures and 5xx up to 2 extra attempts; non-idempotent
  /// requests only get the shared 429 retry. Defaults to false.
  Future<T> enqueue<T>(
    Future<T> Function() request, {
    bool idempotent = false,
  }) {
    final completer = Completer<T>();
    _queue.add(
      _QueueEntry<T>(
        request: request,
        completer: completer,
        idempotent: idempotent,
      ),
    );
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final entry = _queue.removeAt(0);
      await _executeEntry(entry);
    }

    _processing = false;
  }

  Future<void> _executeEntry<T>(_QueueEntry<T> entry) async {
    // Extra attempts beyond the 429 budget, granted only to idempotent
    // requests, to ride out a transient 5xx / transport blip.
    var errorRetriesLeft = entry.idempotent ? 2 : 0;
    var errorRetryNumber = 0;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      // Always enforce the minimum inter-request interval — including
      // between retries — so a server-delayed retry followed by a short
      // server delay can never push us above 3/s for the *next* call.
      final elapsed = DateTime.now().difference(_lastRequestTime);
      if (elapsed < _minInterval) {
        await Future<void>.delayed(_minInterval - elapsed);
      }

      try {
        final result = await entry.request();
        // Update after the attempt settles so pacing is enforced between
        // *every* completed HTTP exchange — see the catch block.
        _lastRequestTime = DateTime.now();
        entry.completer.complete(result);
        return;
      } catch (e) {
        // Update after every attempt that completed an HTTP exchange (success
        // OR error). A run of non-429 HTTP errors used to bypass pacing
        // entirely and burst at full speed; pacing now applies regardless of
        // outcome. Transport failures (no exchange) are also counted — pacing
        // them is harmless and keeps the rule simple.
        _lastRequestTime = DateTime.now();

        if (e is PluralKitRateLimitError && attempt < _maxRetries) {
          // Prefer server-provided delay (body retry_after / headers).
          // Fall back to exponential backoff if the server didn't tell us.
          final serverDelay = e.retryAfter;
          final backoff =
              serverDelay ??
              Duration(milliseconds: 1000 * pow(2, attempt).toInt());
          // Emit BEFORE the backoff sleep. `attempt + 1` is the 1-indexed
          // retry number: the first 429 emits attempt: 1, the second 2, etc.
          _bus?.emit(
            PkRateLimitHit(
              attempt: attempt + 1,
              backoffSeconds: backoff.inSeconds,
            ),
          );
          await Future<void>.delayed(backoff);
          // Treat the rate-limit event as a "request" for pacing purposes so
          // the next attempt also respects _minInterval from this moment.
          _lastRequestTime = DateTime.now();
          continue;
        }

        // Idempotent-only retry on transient transport / 5xx errors. Bounded
        // and outside the 429 attempt counter: 1s then 2s (still gated by
        // _minInterval). Never applied to non-idempotent requests.
        if (errorRetriesLeft > 0 && _isRetriableError(e)) {
          errorRetriesLeft--;
          errorRetryNumber++;
          await Future<void>.delayed(Duration(seconds: errorRetryNumber));
          _lastRequestTime = DateTime.now();
          // Don't consume a 429 attempt slot for an error retry.
          attempt--;
          continue;
        }

        entry.completer.completeError(e);
        return;
      }
    }
  }

  /// Whether [e] is a transient error worth retrying for idempotent requests:
  /// a transport failure, or a 5xx API error (Fly/Caddy blip). 4xx errors are
  /// the caller's fault and never retried here; 429 has its own path.
  static bool _isRetriableError(Object e) {
    if (isPluralKitNetworkException(e)) return true;
    if (e is PluralKitRateLimitError) return false;
    if (e is PluralKitApiError) return e.statusCode >= 500;
    return false;
  }
}

class _QueueEntry<T> {
  final Future<T> Function() request;
  final Completer<T> completer;
  final bool idempotent;

  _QueueEntry({
    required this.request,
    required this.completer,
    this.idempotent = false,
  });
}
