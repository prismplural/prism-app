import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// HTTP client wrapping the Klipy REST API for GIF search and trending.
class KlipyService {
  // TODO(security): Replace with relay proxy before public release — this key
  // ships in the client binary. See gif-search spec for proxy design.
  static const _apiKey = 'PRISM_KLIPY_DEV';

  static const _baseUrl = 'https://api.klipy.com';
  static const _contentFilter = 'medium';
  static const _defaultLimit = 30;

  final http.Client _http;

  KlipyService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  // -- public API -----------------------------------------------------------

  /// Fetch trending GIFs.
  Future<List<KlipyGif>> trending({int limit = _defaultLimit}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/$_apiKey/gifs/trending').replace(
      queryParameters: {
        'per_page': limit.toString(),
        'page': '1',
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

    final uri = Uri.parse('$_baseUrl/api/v1/$_apiKey/gifs/search').replace(
      queryParameters: {
        'q': query.trim(),
        'per_page': limit.toString(),
        'page': '1',
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
        'User-Agent': 'PrismPlurality/1.0',
      });
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
