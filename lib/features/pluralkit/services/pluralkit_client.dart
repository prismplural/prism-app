import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;

import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base error for PluralKit API failures.
///
/// [message] is always the raw response body — callers (e.g. the sync
/// service) match substrings like `40004` against it, so it must never be
/// reshaped. [code] is the parsed PK error code from the body's `code` field
/// (e.g. 40004 identical-front, 40005 duplicate-timestamp), or null when the
/// body wasn't JSON or carried no code.
class PluralKitApiError implements Exception {
  final int statusCode;
  final String message;
  final int? code;
  const PluralKitApiError(this.statusCode, this.message, {this.code});

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
/// before retrying. Parsed in priority order from: the JSON body's
/// `retry_after` (milliseconds — the only signal the deployed PK actually
/// sends), then the `Retry-After` (seconds) and `X-RateLimit-Reset` (epoch
/// seconds, or ms when the value is > 10^12) response headers as fallbacks.
class PluralKitRateLimitError extends PluralKitApiError {
  final Duration? retryAfter;

  const PluralKitRateLimitError([
    String message = 'Rate limited — please wait and try again',
    this.retryAfter,
  ]) : super(429, message);
}

/// Returns true when [e] is a network-layer failure (DNS lookup, connection
/// refused, TLS handshake, timeout, etc) rather than an HTTP-level error.
///
/// PK's HTTP responses go through [_handleResponse] which throws typed
/// errors ([PluralKitApiError], [PluralKitAuthError],
/// [PluralKitRateLimitError]). Anything else is by definition a transport
/// failure — the request never reached PK.
bool isPluralKitNetworkException(Object e) {
  if (e is SocketException) return true;
  if (e is HandshakeException) return true;
  if (e is TimeoutException) return true;
  if (e is http.ClientException) {
    // http package wraps SocketException as ClientException on platforms
    // where dart:io is available. The toString() always includes the
    // underlying type.
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused') ||
        s.contains('Connection closed') ||
        s.contains('Connection failed') ||
        s.contains('Connection terminated') ||
        s.contains('Connection reset by peer') ||
        s.contains('Network is unreachable') ||
        s.contains('No route to host') ||
        s.contains('Software caused connection abort') ||
        s.contains('Operation timed out') ||
        s.contains('Broken pipe') ||
        s.contains('XMLHttpRequest error');
  }
  return false;
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
    PkSyncEventBus? bus,
  }) : _token = token,
       _http = httpClient ?? http.Client(),
       _queue = queue ?? PkRequestQueue(bus: bus);

  /// The bearer token this client was configured with. Exposed so callers
  /// (e.g., [PkMappingApplier]) can pass it to [PkSyncEvent.redact] when
  /// emitting failure events, ensuring the token never enters the sync log.
  /// Never logged or persisted by this client itself.
  String get currentToken => _token;

  // -- helpers --------------------------------------------------------------

  Map<String, String> get _headers => {
    'Authorization': _token,
    'Content-Type': 'application/json',
    'User-Agent': BuildInfo.userAgent,
  };

  /// Extract a retry delay for a 429, if any. Prefers the JSON body's
  /// `retry_after` (milliseconds — the only signal the deployed PK actually
  /// sends), then falls back to the `Retry-After` (seconds) and
  /// `X-RateLimit-Reset` headers. Returns null if none is present/parseable.
  static Duration? _parseRetryAfter(http.Response response) {
    // Primary: JSON body `retry_after` (milliseconds). Body may be non-JSON
    // (Fly/Caddy HTML) — guard the decode.
    final body = response.body;
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final ms = decoded['retry_after'];
          final msInt = ms is int
              ? ms
              : (ms is num ? ms.toInt() : int.tryParse('$ms'));
          if (msInt != null && msInt >= 0) {
            return Duration(milliseconds: msInt);
          }
        }
      } catch (_) {
        // Non-JSON body — fall through to header fallbacks.
      }
    }

    // http package lowercases header names.
    final headers = response.headers;
    final retryAfter = headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: seconds);
      }
    }
    final reset = headers['x-ratelimit-reset'];
    if (reset != null) {
      final resetValue = int.tryParse(reset.trim());
      if (resetValue != null) {
        // Implementation sends epoch seconds; docs claim ms. Disambiguate by
        // magnitude: a value > 10^12 can only be milliseconds (epoch seconds
        // won't reach 10^12 until the year 33658).
        final resetAt = resetValue > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(resetValue, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(
                resetValue * 1000,
                isUtc: true,
              );
        final delta = resetAt.difference(DateTime.now().toUtc());
        if (delta > Duration.zero) return delta;
      }
    }
    return null;
  }

  /// Try to extract the PK error `code` from a response body. Returns null
  /// when the body isn't JSON or carries no integer `code`.
  static int? _parseErrorCode(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final code = decoded['code'];
        if (code is int) return code;
        if (code is num) return code.toInt();
      }
    } catch (_) {
      // Non-JSON body (e.g. Fly/Caddy HTML on 5xx).
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
          _parseRetryAfter(response),
        );
      default:
        throw PluralKitApiError(
          response.statusCode,
          response.body,
          code: _parseErrorCode(response.body),
        );
    }
  }

  Future<dynamic> _get(String url) => _queue.enqueue(() async {
    final response = await _http
        .get(Uri.parse(url), headers: _headers)
        .timeout(_httpTimeout);
    return _handleResponse(response);
  }, idempotent: true);

  Future<dynamic> _post(String url, Map<String, dynamic> body) =>
      _postRaw(url, body);

  /// Internal: POST with any JSON-encodable body. Public-facing methods
  /// type the body specifically (Map for object endpoints, List for the
  /// group-membership /members/add and /members/remove endpoints which
  /// PluralKit documents as taking a raw JSON array of member references).
  /// Centralizes header/queue/timeout/error handling for both shapes.
  Future<dynamic> _postRaw(String url, Object body) => _queue.enqueue(() async {
    final response = await _http
        .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
        .timeout(_httpTimeout);
    return _handleResponse(response);
  });

  Future<dynamic> _patch(String url, Map<String, dynamic> body) =>
      _patchRaw(url, body);

  /// Internal: PATCH with any JSON-encodable body. Mirrors [_postRaw] — most
  /// PATCH endpoints take an object, but `PATCH /switches/{id}/members`
  /// requires a bare JSON array of member references. Centralizes
  /// header/queue/timeout/error handling for both shapes.
  Future<dynamic> _patchRaw(String url, Object body) =>
      _queue.enqueue(() async {
        final response = await _http
            .patch(Uri.parse(url), headers: _headers, body: jsonEncode(body))
            .timeout(_httpTimeout);
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

  /// GET /members/{ref} — fetch one member by short ID or UUID.
  Future<PKMember> getMember(String memberRef) async {
    final ref = memberRef.trim();
    if (ref.isEmpty) {
      throw ArgumentError.value(memberRef, 'memberRef', 'Must not be blank');
    }
    final encoded = Uri.encodeComponent(ref);
    final json =
        await _get('$_baseUrl/members/$encoded') as Map<String, dynamic>;
    return PKMember.fromJson(json);
  }

  /// GET /systems/@me/switches — fetch switches with optional pagination.
  ///
  /// [before] fetches switches before this timestamp (for pagination).
  /// [limit] defaults to 100 (PK API max per page).
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) {
      params['before'] = before.toUtc().toIso8601String();
    }

    final uri = Uri.parse(
      '$_baseUrl/systems/@me/switches',
    ).replace(queryParameters: params);
    final json = await _get(uri.toString()) as List<dynamic>;
    return json
        .map((e) => PKSwitch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /systems/@me/switches/{switchRef} — fetch one switch by UUID.
  ///
  /// Returns the switch with its FULL fronting-member snapshot (PK inlines
  /// member objects on this endpoint; [PKSwitch.fromJson] normalizes them to
  /// short ids either way). Used by the deletion pusher (2026-06 PK audit H2)
  /// to obtain the PK-authoritative co-fronter list before removing a single
  /// member from a shared switch — local rows only carry ENTRANT switch
  /// uuids, so they cannot reconstruct members who entered earlier and were
  /// still fronting. A deleted switch returns 404 with code `20007`.
  Future<PKSwitch> getSwitch(String switchRef) async {
    final ref = switchRef.trim();
    if (ref.isEmpty) {
      throw ArgumentError.value(switchRef, 'switchRef', 'Must not be blank');
    }
    final encoded = Uri.encodeComponent(ref);
    final json =
        await _get('$_baseUrl/systems/@me/switches/$encoded')
            as Map<String, dynamic>;
    return PKSwitch.fromJson(json);
  }

  /// GET /systems/@me/fronters — fetch the current front.
  ///
  /// Returns the current switch (id, timestamp, fronting members) or null
  /// when the system has no switches yet (PK returns 204). One cheap request
  /// — intended for periodic foreground polling.
  Future<PKSwitch?> getCurrentFronters() async {
    final json = await _get('$_baseUrl/systems/@me/fronters');
    if (json == null) return null;
    return PKSwitch.fromJson(json as Map<String, dynamic>);
  }

  /// GET /systems/@me/groups — fetch all groups of the authenticated system.
  ///
  /// When [withMembers] is true, PK inlines the members list on each group
  /// (member objects with `uuid` fields) to avoid an N+1 round-trip. When the
  /// inline list is absent (privacy or a server-side filter), callers can fall
  /// back to [getGroupMembers].
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    final uri = Uri.parse(
      '$_baseUrl/systems/@me/groups',
    ).replace(queryParameters: withMembers ? {'with_members': 'true'} : null);
    final json = await _get(uri.toString()) as List<dynamic>;
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
    final json =
        await _get('$_baseUrl/groups/$groupRef/members') as List<dynamic>;
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

  /// POST /groups/{ref}/members/add — bulk add members to a group.
  ///
  /// Body is a raw JSON array of member references (UUIDs or short IDs).
  /// Returns 204 on success; throws on 4xx/5xx via [_handleResponse]. Used
  /// by the bidirectional push orchestrator to ship local push_add intents
  /// to PluralKit. Routes through [PkRequestQueue] so rate-limit handling
  /// is shared with every other PK call.
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async {
    if (memberRefs.isEmpty) return;
    await _postRaw('$_baseUrl/groups/$groupRef/members/add', memberRefs);
  }

  /// POST /groups/{ref}/members/remove — bulk remove members from a group.
  ///
  /// Body is a raw JSON array of member references. Returns 204 on success.
  /// Same shape and gates as [addMembersToGroup].
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async {
    if (memberRefs.isEmpty) return;
    await _postRaw('$_baseUrl/groups/$groupRef/members/remove', memberRefs);
  }

  /// POST /members — create a new member.
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    final json = await _post('$_baseUrl/members', data) as Map<String, dynamic>;
    return PKMember.fromJson(json);
  }

  /// PATCH /members/{id} — update an existing member.
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    final json =
        await _patch('$_baseUrl/members/$id', data) as Map<String, dynamic>;
    return PKMember.fromJson(json);
  }

  /// POST /systems/@me/switches — create a new switch.
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{'members': memberIds};
    if (timestamp != null) {
      body['timestamp'] = timestamp.toUtc().toIso8601String();
    }
    final json =
        await _post('$_baseUrl/systems/@me/switches', body)
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
    final json =
        await _patch('$_baseUrl/systems/@me/switches/$switchId', body)
            as Map<String, dynamic>;
    return PKSwitch.fromJson(json);
  }

  /// PATCH /systems/@me/switches/{switchId}/members — replace the fronter list
  /// on an existing switch. Member IDs are PK short IDs (or UUIDs).
  ///
  /// The body is a **bare JSON array** of member references (`["id1","id2"]`),
  /// not an object — sending `{"members":[...]}` returns 400. PATCHing the
  /// list that already matches the switch's current members returns 400 with
  /// code `40004` (identical-front), surfaced as a [PluralKitApiError].
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) async {
    final json = await _patchRaw(
      '$_baseUrl/systems/@me/switches/$switchId/members',
      memberIds,
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
    final response = await _http
        .get(Uri.parse(url), headers: {'User-Agent': BuildInfo.userAgent})
        .timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw PluralKitApiError(response.statusCode, 'Failed to download $url');
    }
    return response.bodyBytes;
  }, idempotent: true);

  /// Dispose the underlying HTTP client.
  void dispose() => _http.close();
}
