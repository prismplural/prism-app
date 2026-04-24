import 'dart:async';
import 'dart:math';

import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Rate-limited request queue for PluralKit API (max 3 requests/second,
/// PK's write limit).
///
/// PK actually allows 10/s GETs and 3/s writes; we use a single 3/s bucket
/// (333ms interval) — the worst-case write cap covers everything without
/// complicating callers. Enqueue async operations and they will be executed
/// sequentially. Handles 429 responses with exponential backoff, honoring
/// any `Retry-After` / `X-RateLimit-Reset` delay the server provides.
class PkRequestQueue {
  static const defaultMinInterval = Duration(milliseconds: 333);
  static const defaultMaxRetries = 3;

  final Duration _minInterval;
  final int _maxRetries;

  final _queue = <_QueueEntry<dynamic>>[];
  bool _processing = false;
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  PkRequestQueue({
    Duration minInterval = defaultMinInterval,
    int maxRetries = defaultMaxRetries,
  }) : _minInterval = minInterval,
       _maxRetries = maxRetries;

  /// Enqueue a request. Returns a Future that completes with the result
  /// once the request has been executed (respecting rate limits).
  Future<T> enqueue<T>(Future<T> Function() request) {
    final completer = Completer<T>();
    _queue.add(_QueueEntry<T>(request: request, completer: completer));
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
        // Update only on success. Failed attempts don't count toward the
        // rate budget — the server told us it didn't process them.
        _lastRequestTime = DateTime.now();
        entry.completer.complete(result);
        return;
      } catch (e) {
        if (e is PluralKitRateLimitError && attempt < _maxRetries) {
          // Prefer server-provided delay (Retry-After / X-RateLimit-Reset).
          // Fall back to exponential backoff if the server didn't tell us.
          final serverDelay = e.retryAfter;
          final backoff =
              serverDelay ??
              Duration(milliseconds: 1000 * pow(2, attempt).toInt());
          await Future<void>.delayed(backoff);
          // Treat the rate-limit event as a "request" for pacing purposes so
          // the next attempt also respects _minInterval from this moment.
          _lastRequestTime = DateTime.now();
          continue;
        }
        entry.completer.completeError(e);
        return;
      }
    }
  }
}

class _QueueEntry<T> {
  final Future<T> Function() request;
  final Completer<T> completer;

  _QueueEntry({required this.request, required this.completer});
}
