import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart'
    show isPrivateHostLiteral;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// A single GIF result from the Klipy API.
class KlipyGif {
  final String id;
  final String title;
  final String contentDescription;
  final String mp4Url;
  final String previewUrl;
  final int width;
  final int height;

  const KlipyGif({
    required this.id,
    required this.title,
    required this.contentDescription,
    required this.mp4Url,
    required this.previewUrl,
    required this.width,
    required this.height,
  });

  /// Parse a single item from the Klipy API response.
  ///
  /// The response format nests media under `file` with size keys (`sm`, `xs`,
  /// `md`, `hd`) each containing format keys (`mp4`, `gif`, `webp`, etc.)
  /// with `url`, `width`, `height`, and `size` fields.
  factory KlipyGif.fromJson(Map<String, dynamic> json) {
    final file = json['file'] as Map<String, dynamic>? ?? {};

    // Pick the smallest mp4 for hardware-decoded playback.
    // Prefer xs → sm → md → hd.
    final mp4Info = _pickFormat(file, 'mp4', ['xs', 'sm', 'md', 'hd']);
    final mp4Url = mp4Info?['url'] as String? ?? '';

    // Pick a small gif/webp for static preview thumbnail.
    // Prefer xs → sm for gif, then webp as fallback.
    final previewInfo = _pickFormat(file, 'gif', ['xs', 'sm']) ??
        _pickFormat(file, 'webp', ['xs', 'sm']);
    final previewUrl = previewInfo?['url'] as String? ?? '';

    // Dimensions from the mp4 source (or preview fallback).
    final dimSource = mp4Info ?? previewInfo ?? <String, dynamic>{};
    var width = (dimSource['width'] as num?)?.toInt() ?? 0;
    var height = (dimSource['height'] as num?)?.toInt() ?? 0;

    // Clamp invalid dimensions to 0 (UI layer will handle).
    if (width <= 0 || width >= 10000) width = 0;
    if (height <= 0 || height >= 10000) height = 0;

    return KlipyGif(
      id: (json['id'] ?? json['slug'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      contentDescription: json['title'] as String? ?? '',
      mp4Url: mp4Url,
      previewUrl: previewUrl,
      width: width,
      height: height,
    );
  }

  /// Walk through [sizes] in order and return the first entry that has
  /// a non-null [format] with a `url` key.
  static Map<String, dynamic>? _pickFormat(
    Map<String, dynamic> file,
    String format,
    List<String> sizes,
  ) {
    for (final size in sizes) {
      final sizeMap = file[size] as Map<String, dynamic>?;
      if (sizeMap == null) continue;
      final formatMap = sizeMap[format] as Map<String, dynamic>?;
      if (formatMap != null && formatMap['url'] != null) return formatMap;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base error for Klipy API failures.
class KlipyApiError implements Exception {
  final int statusCode;
  final String message;
  const KlipyApiError(this.statusCode, this.message);

  @override
  String toString() => 'KlipyApiError($statusCode): $message';
}

/// 429 Too Many Requests — rate-limited.
class KlipyRateLimitError extends KlipyApiError {
  const KlipyRateLimitError(
      [String message = 'Rate limited — please wait and try again'])
      : super(429, message);
}

class GifServiceConfig {
  final bool enabled;
  final String? apiBaseUrl;
  final bool mediaProxyEnabled;

  const GifServiceConfig({
    required this.enabled,
    required this.apiBaseUrl,
    required this.mediaProxyEnabled,
  });

  factory GifServiceConfig.fromJson(
    Map<String, dynamic> json, {
    required String relayUrl,
  }) {
    final rawBaseUrl = json['api_base_url'] as String?;
    final resolvedBaseUrl = (rawBaseUrl == null || rawBaseUrl.isEmpty)
        ? null
        : sanitizeGifApiBaseUrl(
            Uri.parse(relayUrl).resolve(rawBaseUrl).toString(),
            relayUrl: relayUrl,
          );
    return GifServiceConfig(
      enabled: json['enabled'] as bool? ?? false,
      apiBaseUrl: resolvedBaseUrl,
      mediaProxyEnabled: json['media_proxy_enabled'] as bool? ?? false,
    );
  }

  /// Hosts explicitly trusted to serve the GIF proxy API.
  ///
  /// Suffix entries (leading `.`) match the registrable domain and any
  /// subdomain (e.g. `.klipy.com` matches `klipy.com` and `api.klipy.com`);
  /// non-suffix entries match the exact host only. Plus the relay's own host
  /// (resolved at call time) for the self-hosted GIF-proxy mode, where the relay
  /// legitimately proxies GIF requests through itself — see
  /// [sanitizeGifApiBaseUrl].
  ///
  /// Provenance (prism-sync `routes/gifs.rs` `gif_capabilities`):
  ///   * `*.klipy.com`   — the upstream Klipy provider (built-in default).
  ///   * `*.tenor.com`   — alternate provider (also accepted by [isValidGifUrl]).
  ///   * `gif.prism.app` — the Prism-hosted GIF service (PrismHosted mode).
  ///   * `*.prismsync.com` — Prism-operated relay/service domain.
  static const _trustedGifApiHostSuffixes = <String>[
    '.klipy.com',
    '.tenor.com',
    '.prismsync.com',
  ];

  /// Exact GIF-provider hosts that are trusted but are not under one of the
  /// trusted suffixes above.
  static const _trustedGifApiHostsExact = <String>[
    'gif.prism.app',
  ];

  /// Validate a relay-supplied GIF `api_base_url` before it is ever used as a
  /// request base. Returns the sanitized URL string, or `null` to reject it
  /// (callers fall back to the safe disabled/default behaviour).
  ///
  /// The base URL is served by the relay (untrusted under Prism's threat model)
  /// and was previously used verbatim — an SSRF / search-term-exfiltration
  /// vector. We require:
  ///   * a parseable absolute URL with an `https` scheme;
  ///   * a non-empty host that is NOT a private/loopback/link-local/CGNAT/
  ///     metadata literal (see [isPrivateHostLiteral]) — cheap first-line
  ///     defense against the obvious SSRF targets;
  ///   * a host that is on the GIF-provider allowlist
  ///     ([_trustedGifApiHostSuffixes] / [_trustedGifApiHostsExact]) **or** the
  ///     relay's own host.
  ///
  /// The allowlist is **enforcing**: any other host — including an off-allowlist
  /// public https host such as `evil.example.com` — is rejected. This closes
  /// both vectors the security review flagged: a malicious relay cannot point
  /// the GIF client at an internal service (SSRF), and it cannot redirect GIF
  /// search terms to an attacker-controlled server (exfiltration), because the
  /// only reachable hosts are trusted public GIF providers or the relay itself.
  ///
  /// The relay's own host is intentionally accepted: in the self-hosted GIF
  /// provider mode the relay advertises a *relative* `api_base_url` (e.g.
  /// `/v1/gifs`) that resolves to the relay, which proxies GIF requests upstream
  /// with its own API key. That is the documented design, and the relay is
  /// already where all sync traffic flows, so it is not an SSRF escalation —
  /// but note an arbitrary third-party host is never accepted just because the
  /// relay supplied it.
  @visibleForTesting
  static String? sanitizeGifApiBaseUrl(String url, {required String relayUrl}) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    if (uri.scheme != 'https') return null;

    final host = uri.host;
    if (host.isEmpty) return null;
    if (isPrivateHostLiteral(host)) return null;

    final lcHost = host.toLowerCase();
    final relayHost = Uri.tryParse(relayUrl)?.host.toLowerCase();
    final isTrusted =
        (relayHost != null && relayHost.isNotEmpty && lcHost == relayHost) ||
        _trustedGifApiHostsExact.contains(lcHost) ||
        _trustedGifApiHostSuffixes.any(
          (suffix) => lcHost == suffix.substring(1) || lcHost.endsWith(suffix),
        );

    if (!isTrusted) {
      // Enforcing allowlist: reject any host that is not a trusted GIF provider
      // or the relay's own host. Falling back to null makes the caller use the
      // safe disabled/default behaviour rather than talking to an
      // attacker-chosen server.
      debugPrint(
        '[GifServiceConfig] rejecting api_base_url host "$host": not a trusted '
        'GIF provider or the relay host.',
      );
      return null;
    }

    return uri.toString();
  }

  const GifServiceConfig.disabled()
      : enabled = false,
        apiBaseUrl = null,
        mediaProxyEnabled = false;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// HTTP client wrapping the Klipy REST API for GIF search and trending.
class KlipyService {
  static const _contentFilter = 'medium';
  static const _defaultLimit = 30;
  static const _httpTimeout = Duration(seconds: 15);

  final String _baseUrl;
  final http.Client _http;

  KlipyService({
    required String baseUrl,
    http.Client? httpClient,
  })  : _baseUrl =
            baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http = httpClient ?? http.Client();

  // -- public API -----------------------------------------------------------

  /// Fetch trending GIFs.
  Future<List<KlipyGif>> trending({int limit = _defaultLimit}) async {
    final uri = Uri.parse('$_baseUrl/trending').replace(
      queryParameters: {
        'per_page': limit.toString(),
        'content_filter': _contentFilter,
      },
    );

    return _fetchGifs(uri);
  }

  /// Search for GIFs by query.
  Future<List<KlipyGif>> search(
    String query, {
    int limit = _defaultLimit,
  }) async {
    if (query.trim().isEmpty) return trending(limit: limit);

    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'q': query.trim(),
        'per_page': limit.toString(),
        'content_filter': _contentFilter,
      },
    );

    return _fetchGifs(uri);
  }

  /// Validates that a URL points to a known Klipy/GIF CDN domain.
  /// Used when rendering GIFs from synced CRDT data to prevent URL injection.
  static bool isValidGifUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'https') return false;
    final host = uri.host;
    return host.endsWith('.klipy.com') ||
        host == 'klipy.com' ||
        host.endsWith('.tenor.com') ||
        host == 'tenor.com';
  }

  /// Dispose the underlying HTTP client.
  void dispose() => _http.close();

  // -- helpers --------------------------------------------------------------

  Future<List<KlipyGif>> _fetchGifs(Uri uri) async {
    final http.Response response;
    try {
      response = await _http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': BuildInfo.userAgent,
      }).timeout(_httpTimeout);
    } on Exception {
      // Network errors (DNS, timeout, etc.) — let them propagate.
      rethrow;
    }

    if (response.statusCode == 429) {
      throw const KlipyRateLimitError();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KlipyApiError(response.statusCode, response.body);
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? {};
      final items = data['data'] as List<dynamic>? ?? [];

      return items
          .whereType<Map<String, dynamic>>()
          .where((item) => item['type'] != 'ad')
          .map(KlipyGif.fromJson)
          .where((gif) => gif.mp4Url.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[KlipyService] Failed to parse response: $e');
      return [];
    }
  }
}
