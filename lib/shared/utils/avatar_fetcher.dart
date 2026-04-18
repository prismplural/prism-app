import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Fetch an avatar image from [url] as raw bytes.
///
/// Shared helper so SP import, PK sync, and any future importers apply the
/// same guardrails instead of reinventing them:
///
/// * 10-second request timeout (configurable via [timeout]).
/// * 5 MiB payload cap (configurable via [maxBytes]) — avatars are small;
///   larger responses almost always indicate a misconfigured URL.
/// * Requires a `content-type: image/*` response header.
/// * Silently returns `null` on any failure (non-2xx, timeout, wrong MIME,
///   oversize, I/O error). Callers record a warning if they want one.
///
/// Stateless: if [client] is omitted a short-lived [http.Client] is created
/// and closed before returning. No on-disk cache; bytes are intended to be
/// written straight into the Drift blob column by the caller.
Future<Uint8List?> fetchAvatarBytes(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 5 * 1024 * 1024,
}) async {
  if (url.isEmpty) return null;

  Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }

  final owned = client == null;
  final http.Client effective = client ?? http.Client();

  try {
    final response = await effective.get(uri).timeout(timeout);
    if (response.statusCode != 200) return null;

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) return null;

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return null;
    if (bytes.length > maxBytes) return null;

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
