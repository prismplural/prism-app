import 'dart:async';
import 'dart:math';

import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Rate-limited request queue for PluralKit API (max 2 requests/second).
///
/// Enqueue async operations and they will be executed sequentially with
/// a minimum 500ms gap between requests. Handles 429 responses with
/// exponential backoff.
class PkRequestQueue {
  static const _minInterval = Duration(milliseconds: 500);
  static const _maxRetries = 3;

  final _queue = <_QueueEntry<dynamic>>[];
  bool _processing = false;
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

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
    // Wait until the minimum interval has elapsed since the last request
    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < _minInterval) {
      await Future<void>.delayed(_minInterval - elapsed);
    }

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        _lastRequestTime = DateTime.now();
        final result = await entry.request();
        entry.completer.complete(result);
        return;
      } catch (e) {
        // Check if it's a 429 rate limit error
        if (_isRateLimitError(e) && attempt < _maxRetries) {
          final backoff = Duration(
            milliseconds: 1000 * pow(2, attempt).toInt(),
          );
          await Future<void>.delayed(backoff);
          continue;
        }
        entry.completer.completeError(e);
        return;
      }
    }
  }

  bool _isRateLimitError(Object error) {
    return error is PluralKitRateLimitError;
  }
}

class _QueueEntry<T> {
  final Future<T> Function() request;
  final Completer<T> completer;

  _QueueEntry({required this.request, required this.completer});
}
