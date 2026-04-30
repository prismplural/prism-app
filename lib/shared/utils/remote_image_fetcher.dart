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

  try {
    final request = http.Request('GET', uri);
    final response = await effective.send(request).timeout(timeout);
    if (response.statusCode != 200) return null;

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) return null;

    final contentLength =
        response.contentLength ??
        int.tryParse(response.headers['content-length'] ?? '');
    if (contentLength != null && contentLength > maxBytes) return null;

    final chunks = <List<int>>[];
    var total = 0;

    await for (final chunk in response.stream.timeout(timeout)) {
      total += chunk.length;
      if (total > maxBytes) return null;
      chunks.add(chunk);
    }

    if (total == 0) return null;

    final bytes = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return bytes;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (owned) {
      effective.close();
    }
  }
}
