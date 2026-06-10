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

  /// Domains explicitly trusted to serve the GIF proxy API. When the
  /// relay-supplied base URL points at one of these (or back at the relay's own
  /// host), it is accepted; any other public host is allowed only after passing
  /// the SSRF host checks below.
  static const _trustedGifApiHostSuffixes = <String>[
    '.klipy.com',
    '.tenor.com',
    '.prismsync.com',
  ];

  /// Validate a relay-supplied GIF `api_base_url` before it is ever used as a
  /// request base. Returns the sanitized URL string, or `null` to reject it.
  ///
  /// The base URL is served by the relay (untrusted under Prism's threat model)
  /// and was previously used verbatim — an SSRF / search-term-exfiltration
  /// vector. We require:
  ///   * a parseable absolute URL with an `https` scheme;
  ///   * a non-empty host that is NOT a private/loopback/link-local/CGNAT/
  ///     metadata literal (see [isPrivateHostLiteral]).
  ///
  /// As defense-in-depth we *prefer* an allowlist: a known GIF-proxy domain or
  /// the relay's own host is accepted directly. Other public https hosts still
  /// pass (the GIF feature is opt-in and disabled by default) but only after the
  /// SSRF literal check, so the relay cannot redirect GIF traffic at an internal
  /// service.
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
        _trustedGifApiHostSuffixes.any(
          (suffix) => lcHost == suffix.substring(1) || lcHost.endsWith(suffix),
        );

    if (!isTrusted) {
      // Not on the allowlist: still permit a public https host (GIF is an
      // opt-in, off-by-default feature), but log so the relay-supplied host is
      // visible in diagnostics. The SSRF literal check above already rejected
      // the dangerous targets.
      debugPrint(
        '[GifServiceConfig] api_base_url host "$host" is not on the GIF '
        'allowlist; accepting as a public https host after SSRF checks.',
      );
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
