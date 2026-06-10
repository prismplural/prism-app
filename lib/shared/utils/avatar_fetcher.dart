import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'remote_image_fetcher.dart';

/// Fetch an avatar image from [url] as raw bytes.
///
/// Shared helper so SP import, PK sync, and any future importers apply the
/// same guardrails instead of reinventing them:
///
/// * 10-second request timeout (configurable via [timeout]).
/// * Three attempts for transient failures (timeouts, I/O errors, 408, 429,
///   5xx), with capped exponential backoff.
/// * 5 MiB payload cap (configurable via [maxBytes]) — avatars are small;
///   larger responses almost always indicate a misconfigured URL.
/// * Requires the response to be a supported image — by `content-type:
///   image/*`, or by a magic-byte sniff when the header is wrong/absent.
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
  int maxAttempts = 3,
  Duration initialRetryDelay = const Duration(milliseconds: 500),
  Duration maxRetryDelay = const Duration(seconds: 4),
}) async {
  return fetchRemoteImageBytes(
    url,
    client: client,
    timeout: timeout,
    maxBytes: maxBytes,
    maxAttempts: maxAttempts,
    initialRetryDelay: initialRetryDelay,
    maxRetryDelay: maxRetryDelay,
  );
}
