import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base error for PluralKit API failures.
class PluralKitApiError implements Exception {
  final int statusCode;
  final String message;
  const PluralKitApiError(this.statusCode, this.message);

  @override
  String toString() => 'PluralKitApiError($statusCode): $message';
}

/// 401 Unauthorized — invalid or missing token.
class PluralKitAuthError extends PluralKitApiError {
  const PluralKitAuthError([String message = 'Unauthorized — check your token'])
      : super(401, message);
}

/// 429 Too Many Requests — rate-limited.
///
/// [retryAfter], when non-null, is the duration the server asked us to wait
/// before retrying. Parsed from (in priority order) `Retry-After` (seconds)
/// or `X-RateLimit-Reset` (unix epoch seconds) response headers.
class PluralKitRateLimitError extends PluralKitApiError {
  final Duration? retryAfter;

  const PluralKitRateLimitError(
      [String message = 'Rate limited — please wait and try again',
      this.retryAfter])
      : super(429, message);
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for PluralKit API v2.
///
/// All requests require an API token set via the constructor.
class PluralKitClient {
  static const _baseUrl = 'https://api.pluralkit.me/v2';
  static const _httpTimeout = Duration(seconds: 15);

  final String _token;
  final http.Client _http;
  final PkRequestQueue _queue;

  PluralKitClient({
    required String token,
    http.Client? httpClient,
    PkRequestQueue? queue,
  })  : _token = token,
        _http = httpClient ?? http.Client(),
        _queue = queue ?? PkRequestQueue();

  // -- helpers --------------------------------------------------------------

  Map<String, String> get _headers => {
        'Authorization': _token,
        'Content-Type': 'application/json',
        'User-Agent': 'PrismPlurality/1.0',
      };

  /// Extract a retry delay from 429 response headers, if any. Prefers
  /// the HTTP standard `Retry-After` header (seconds) and falls back to
  /// `X-RateLimit-Reset` (unix epoch seconds). Returns null if neither
  /// is present or parseable.
  static Duration? _parseRetryAfter(Map<String, String> headers) {
    // http package lowercases header names.
    final retryAfter = headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: seconds);
      }
    }
    final reset = headers['x-ratelimit-reset'];
    if (reset != null) {
      final epochSeconds = int.tryParse(reset.trim());
      if (epochSeconds != null) {
        final resetAt =
            DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true);
        final delta = resetAt.difference(DateTime.now().toUtc());
        if (delta > Duration.zero) return delta;
      }
    }
    return null;
  }

  /// Parse response body or throw typed error.
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    switch (response.statusCode) {
      case 401:
        throw const PluralKitAuthError();
      case 429:
        throw PluralKitRateLimitError(
          'Rate limited — please wait and try again',
          _parseRetryAfter(response.headers),
        );
      default:
        throw PluralKitApiError(response.statusCode, response.body);
    }
  }

  Future<dynamic> _get(String url) => _queue.enqueue(() async {
        final response = await _http
            .get(Uri.parse(url), headers: _headers)
            .timeout(_httpTimeout);
        return _handleResponse(response);
      });

  Future<dynamic> _post(String url, Map<String, dynamic> body) =>
      _queue.enqueue(() async {
        final response = await _http.post(
          Uri.parse(url),
          headers: _headers,
          body: jsonEncode(body),
        ).timeout(_httpTimeout);
        return _handleResponse(response);
      });

  Future<dynamic> _patch(String url, Map<String, dynamic> body) =>
      _queue.enqueue(() async {
        final response = await _http.patch(
          Uri.parse(url),
          headers: _headers,
          body: jsonEncode(body),
        ).timeout(_httpTimeout);
        return _handleResponse(response);
      });

  Future<dynamic> _delete(String url) => _queue.enqueue(() async {
        final response = await _http
            .delete(Uri.parse(url), headers: _headers)
            .timeout(_httpTimeout);
        return _handleResponse(response);
      });

  // -- public API -----------------------------------------------------------

  /// GET /systems/@me — fetch the authenticated system.
  Future<PKSystem> getSystem() async {
    final json = await _get('$_baseUrl/systems/@me') as Map<String, dynamic>;
    return PKSystem.fromJson(json);
  }

  /// GET /systems/@me/members — fetch all members of the authenticated system.
  Future<List<PKMember>> getMembers() async {
    final json = await _get('$_baseUrl/systems/@me/members') as List<dynamic>;
    return json
        .map((e) => PKMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /systems/@me/switches — fetch switches with optional pagination.
  ///
  /// [before] fetches switches before this timestamp (for pagination).
  /// [limit] defaults to 100 (PK API max per page).
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
    };
    if (before != null) {
      params['before'] = before.toUtc().toIso8601String();
    }

    final uri = Uri.parse('$_baseUrl/systems/@me/switches')
        .replace(queryParameters: params);
    final json = await _get(uri.toString()) as List<dynamic>;
    return json
        .map((e) => PKSwitch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /systems/@me/groups — fetch all groups of the authenticated system.
  ///
  /// When [withMembers] is true, PK inlines the members list on each group
  /// (member objects with `uuid` fields) to avoid an N+1 round-trip. When the
  /// inline list is absent (privacy or a server-side filter), callers can fall
  /// back to [getGroupMembers].
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    final uri = Uri.parse('$_baseUrl/systems/@me/groups').replace(
      queryParameters: withMembers ? {'with_members': 'true'} : null,
    );
    final response =
        await _http.get(uri, headers: _headers).timeout(_httpTimeout);
    final json = _handleResponse(response) as List<dynamic>;
    return json
        .map((e) => PKGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /groups/{ref}/members — fetch member UUIDs for a single group.
  ///
  /// Used as a fallback when privacy/scope hides the inline `members` field on
  /// `getGroups(withMembers: true)`. PK returns a list of member objects (or
  /// string UUIDs); we extract UUIDs either way.
  Future<List<String>> getGroupMembers(String groupRef) async {
    final response = await _http.get(
      Uri.parse('$_baseUrl/groups/$groupRef/members'),
      headers: _headers,
    ).timeout(_httpTimeout);
    final json = _handleResponse(response) as List<dynamic>;
    final out = <String>[];
    for (final entry in json) {
      if (entry is String) {
        out.add(entry);
      } else if (entry is Map<String, dynamic>) {
        final uuid = entry['uuid'];
        if (uuid is String) out.add(uuid);
      }
    }
    return out;
  }

  /// POST /members — create a new member.
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    final json =
        await _post('$_baseUrl/members', data) as Map<String, dynamic>;
    return PKMember.fromJson(json);
  }

  /// PATCH /members/{id} — update an existing member.
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    final json = await _patch('$_baseUrl/members/$id', data)
        as Map<String, dynamic>;
    return PKMember.fromJson(json);
  }

  /// POST /systems/@me/switches — create a new switch.
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{
      'members': memberIds,
    };
    if (timestamp != null) {
      body['timestamp'] = timestamp.toUtc().toIso8601String();
    }
    final json = await _post('$_baseUrl/systems/@me/switches', body)
        as Map<String, dynamic>;
    return PKSwitch.fromJson(json);
  }

  /// PATCH /systems/@me/switches/{switchId} — update a switch's timestamp.
  ///
  /// PK's PATCH endpoint on a switch only supports `timestamp`. Member changes
  /// go through [updateSwitchMembers] via `PATCH /switches/{id}/members`.
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) async {
    final body = <String, dynamic>{
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
    final json = await _patch(
      '$_baseUrl/systems/@me/switches/$switchId',
      body,
    ) as Map<String, dynamic>;
    return PKSwitch.fromJson(json);
  }

  /// PATCH /systems/@me/switches/{switchId}/members — replace the fronter list
  /// on an existing switch. Member IDs are PK 5-char short IDs.
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    final json = await _patch(
      '$_baseUrl/systems/@me/switches/$switchId/members',
      <String, dynamic>{'members': memberIds},
    );
    return PKSwitch.fromJson(json as Map<String, dynamic>);
  }

  /// DELETE /systems/@me/switches/{switchId} — delete a switch.
  Future<void> deleteSwitch(String switchId) async {
    await _delete('$_baseUrl/systems/@me/switches/$switchId');
  }

  /// DELETE /members/{id} — delete a member.
  Future<void> deleteMember(String id) async {
    await _delete('$_baseUrl/members/$id');
  }

  /// Download raw bytes from a URL (e.g. avatar images).
  ///
  /// Routed through the same rate-limit queue as API calls to prevent
  /// concurrent bursts during import. Avatar CDNs don't share the API's
  /// 3/s budget, but single-path pacing is a safe default.
  Future<List<int>> downloadBytes(String url) => _queue.enqueue(() async {
        final response =
            await _http.get(Uri.parse(url)).timeout(_httpTimeout);
        if (response.statusCode != 200) {
          throw PluralKitApiError(
              response.statusCode, 'Failed to download $url');
        }
        return response.bodyBytes;
      });

  /// Dispose the underlying HTTP client.
  void dispose() => _http.close();
}
