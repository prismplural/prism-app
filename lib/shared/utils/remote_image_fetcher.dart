import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Fetches a remote image with shared importer guardrails.
///
/// Returns `null` for all validation, network, timeout, and size failures.
Future<Uint8List?> fetchRemoteImageBytes(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 10 * 1024 * 1024,
  int maxAttempts = 3,
  Duration initialRetryDelay = const Duration(milliseconds: 500),
  Duration maxRetryDelay = const Duration(seconds: 4),
}) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return null;
  }

  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }

  final owned = client == null;
  final effective = client ?? http.Client();
  final attempts = maxAttempts < 1 ? 1 : maxAttempts;

  try {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final result = await _fetchRemoteImageBytesOnce(
          uri,
          client: effective,
          timeout: timeout,
          maxBytes: maxBytes,
        );
        if (result.bytes != null) return result.bytes;
        if (!result.retryable || attempt == attempts - 1) return null;
      } on TimeoutException {
        if (attempt == attempts - 1) return null;
      } catch (_) {
        if (attempt == attempts - 1) return null;
      }

      final delay = _retryDelay(
        attempt,
        initialRetryDelay: initialRetryDelay,
        maxRetryDelay: maxRetryDelay,
      );
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }

    return null;
  } finally {
    if (owned) {
      effective.close();
    }
  }
}

Future<({Uint8List? bytes, bool retryable})> _fetchRemoteImageBytesOnce(
  Uri uri, {
  required http.Client client,
  required Duration timeout,
  required int maxBytes,
}) async {
  final request = http.Request('GET', uri);
  final response = await client.send(request).timeout(timeout);
  if (response.statusCode != 200) {
    return (bytes: null, retryable: _isTransientStatus(response.statusCode));
  }

  final contentType = response.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('image/')) {
    return (bytes: null, retryable: false);
  }

  final contentLength =
      response.contentLength ??
      int.tryParse(response.headers['content-length'] ?? '');
  if (contentLength != null && contentLength > maxBytes) {
    return (bytes: null, retryable: false);
  }

  final chunks = <List<int>>[];
  var total = 0;

  await for (final chunk in response.stream.timeout(timeout)) {
    total += chunk.length;
    if (total > maxBytes) return (bytes: null, retryable: false);
    chunks.add(chunk);
  }

  if (total == 0) return (bytes: null, retryable: false);

  final bytes = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    bytes.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  return (bytes: bytes, retryable: false);
}

bool _isTransientStatus(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;

Duration _retryDelay(
  int completedFailures, {
  required Duration initialRetryDelay,
  required Duration maxRetryDelay,
}) {
  var delayMicros = initialRetryDelay.inMicroseconds;
  final maxMicros = maxRetryDelay.inMicroseconds;

  for (var i = 0; i < completedFailures; i++) {
    delayMicros *= 2;
    if (delayMicros >= maxMicros) {
      return maxRetryDelay;
    }
  }

  if (delayMicros > maxMicros) return maxRetryDelay;
  return Duration(microseconds: delayMicros);
}
