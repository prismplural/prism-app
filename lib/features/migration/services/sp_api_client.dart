import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:prism_plurality/features/migration/services/sp_parser.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base error for Simply Plural API failures.
class SpApiError implements Exception {
  final int statusCode;
  final String message;
  const SpApiError(this.statusCode, this.message);

  @override
  String toString() => 'SpApiError($statusCode): $message';
}

/// 401 Unauthorized — invalid or missing token.
class SpAuthError extends SpApiError {
  const SpAuthError([String message = 'Unauthorized — check your token'])
      : super(401, message);
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for the Simply Plural API v1.
///
/// All requests require an API token set via the constructor.
class SpApiClient {
  static const _baseUrl = 'https://api.apparyllis.com/v1';

  final String _token;
  final http.Client _http;

  late final Map<String, String> _headers;

  SpApiClient({
    required String token,
    http.Client? httpClient,
  })  : _token = token.trim(),
        _http = httpClient ?? http.Client() {
    if (_token.isEmpty) {
      throw ArgumentError('SP API token must not be empty');
    }
    _headers = {
      'Authorization': _token,
      'Content-Type': 'application/json',
      'User-Agent': 'PrismPlurality/1.0',
    };
  }

  /// Parse response body or throw typed error.
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    switch (response.statusCode) {
      case 401:
      case 403:
        throw const SpAuthError();
      default:
        throw SpApiError(response.statusCode, response.body);
    }
  }

  Future<dynamic> _get(String path) async {
    final response = await _http
        .get(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  // -- public API -----------------------------------------------------------

  /// GET /v1/me — returns the system user ID and username.
  ///
  /// The /me response wraps user data inside a `content` field:
  /// `{ "id": "...", "content": { "uid": "...", "username": "..." } }`
  Future<({String systemId, String? username})> verifyToken() async {
    final json = await _get('/me') as Map<String, dynamic>;
    final content =
        (json['content'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final uid = content['uid']?.toString() ??
        json['id']?.toString() ??
        json['uid']?.toString() ??
        json['_id']?.toString() ??
        '';
    final username =
        content['username'] as String? ?? json['username'] as String?;
    return (systemId: uid, username: username);
  }

  /// Parse a list response — returns empty list on non-list bodies.
  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final json = await _get(path);
    if (json is List) return json.cast<Map<String, dynamic>>();
    return [];
  }

  /// Encode a path segment to prevent path traversal from API-returned IDs.
  static String _enc(String segment) => Uri.encodeComponent(segment);

  /// GET /v1/members/:sid
  Future<List<Map<String, dynamic>>> getMembers(String sid) =>
      _getList('/members/${_enc(sid)}');

  /// GET /v1/customFronts/:sid
  Future<List<Map<String, dynamic>>> getCustomFronts(String sid) =>
      _getList('/customFronts/${_enc(sid)}');

  /// GET /v1/frontHistory
  Future<List<Map<String, dynamic>>> getFrontHistory() =>
      _getList('/frontHistory');

  /// GET /v1/groups/:sid
  Future<List<Map<String, dynamic>>> getGroups(String sid) =>
      _getList('/groups/${_enc(sid)}');

  /// GET /v1/customFields/:sid
  Future<List<Map<String, dynamic>>> getCustomFields(String sid) =>
      _getList('/customFields/${_enc(sid)}');

  /// GET /v1/polls/:sid
  Future<List<Map<String, dynamic>>> getPolls(String sid) =>
      _getList('/polls/${_enc(sid)}');

  /// GET /v1/notes/:sid/:memberId
  Future<List<Map<String, dynamic>>> getNotes(
          String sid, String memberId) =>
      _getList('/notes/${_enc(sid)}/${_enc(memberId)}');

  /// GET /v1/comments/:type/:docId
  Future<List<Map<String, dynamic>>> getComments(
          String type, String docId) =>
      _getList('/comments/${_enc(type)}/${_enc(docId)}');

  /// GET /v1/chat/channels — all chat channels for the authenticated user.
  Future<List<Map<String, dynamic>>> getChannels() =>
      _getList('/chat/channels');

  /// GET /v1/chat/channel/messages/:channelId — messages in a channel.
  Future<List<Map<String, dynamic>>> getChannelMessages(String channelId) =>
      _getList('/chat/channel/messages/${_enc(channelId)}');

  // -------------------------------------------------------------------------
  // fetchAll — assemble a full SpExportData from the API
  // -------------------------------------------------------------------------

  /// Fetch all data from SP and assemble into [SpExportData].
  ///
  /// [onProgress] reports (collectionName, itemCount) as each collection
  /// completes.
  Future<SpExportData> fetchAll({
    void Function(String collection, int count)? onProgress,
  }) async {
    // 1. Get system ID.
    final verified = await verifyToken();
    final sid = verified.systemId;

    // 2. Fetch main collections in parallel.
    final results = await Future.wait([
      getMembers(sid),
      getCustomFronts(sid),
      getFrontHistory(),
      getGroups(sid),
      getCustomFields(sid),
      getPolls(sid),
    ]);

    final members = results[0];
    onProgress?.call('Members', members.length);
    final customFronts = results[1];
    onProgress?.call('Custom fronts', customFronts.length);
    final frontHistory = results[2];
    onProgress?.call('Front history', frontHistory.length);
    final groups = results[3];
    onProgress?.call('Groups', groups.length);
    final customFields = results[4];
    onProgress?.call('Custom fields', customFields.length);
    final polls = results[5];
    onProgress?.call('Polls', polls.length);

    // 3. Fetch notes per member (5 concurrent).
    final allNotes = <Map<String, dynamic>>[];
    for (var i = 0; i < members.length; i += 5) {
      final chunk = members.skip(i).take(5);
      final noteResults = await Future.wait(
        chunk.map((m) {
          final mid = (m['_id'] ?? m['id'] ?? '').toString();
          return getNotes(sid, mid)
              .catchError((_) => <Map<String, dynamic>>[]);
        }),
      );
      for (final notes in noteResults) {
        allNotes.addAll(notes);
      }
      onProgress?.call('Notes', allNotes.length);
    }

    // 4. Fetch comments per front history entry (25 concurrent).
    final allComments = <Map<String, dynamic>>[];
    for (var i = 0; i < frontHistory.length; i += 25) {
      final chunk = frontHistory.skip(i).take(25);
      final commentResults = await Future.wait(
        chunk.map((fh) {
          final fhId = (fh['_id'] ?? fh['id'] ?? '').toString();
          return getComments('frontHistory', fhId)
              .catchError((_) => <Map<String, dynamic>>[]);
        }),
      );
      for (final comments in commentResults) {
        allComments.addAll(comments);
      }
      onProgress?.call('Comments', allComments.length);
    }

    // 5. Fetch chat channels and their messages.
    final channels = await getChannels()
        .catchError((_) => <Map<String, dynamic>>[]);
    onProgress?.call('Channels', channels.length);

    final allChatMessages = <SpMessage>[];
    for (var i = 0; i < channels.length; i += 5) {
      final chunk = channels.skip(i).take(5);
      final msgResults = await Future.wait(
        chunk.map((ch) {
          final chId = (ch['_id'] ?? ch['id'] ?? '').toString();
          return getChannelMessages(chId)
              .then((msgs) => msgs
                  .map((m) => SpMessage.fromJson(m, chId))
                  .toList())
              .catchError((_) => <SpMessage>[]);
        }),
      );
      for (final msgs in msgResults) {
        allChatMessages.addAll(msgs);
      }
    }
    onProgress?.call('Chat messages', allChatMessages.length);

    // 6. Fetch board messages per member (5 concurrent).
    final allBoardMessages = <Map<String, dynamic>>[];
    for (var i = 0; i < members.length; i += 5) {
      final chunk = members.skip(i).take(5);
      final boardResults = await Future.wait(
        chunk.map((m) {
          final mid = (m['_id'] ?? m['id'] ?? '').toString();
          return _getList('/board/member/${_enc(mid)}')
              .catchError((_) => <Map<String, dynamic>>[]);
        }),
      );
      for (final msgs in boardResults) {
        allBoardMessages.addAll(msgs);
      }
    }
    onProgress?.call('Board messages', allBoardMessages.length);

    // 7. Assemble into SpExportData using existing fromJson factories.
    // Note: automatedTimers and repeatedTimers are not available via the SP
    // API (no public endpoints), so they are only imported via file export.
    return SpExportData(
      members: members.map(SpMember.fromJson).toList(),
      customFronts: customFronts.map(SpCustomFront.fromJson).toList(),
      frontHistory: frontHistory.map(SpFrontHistory.fromJson).toList(),
      groups: groups.map(SpGroup.fromJson).toList(),
      channels: channels.map(SpChannel.fromJson).toList(),
      messages: allChatMessages,
      polls: polls.map(SpPoll.fromJson).toList(),
      notes: allNotes.map(SpNote.fromJson).toList(),
      comments: allComments.map(SpComment.fromJson).toList(),
      customFields: customFields.map(SpCustomFieldDef.fromJson).toList(),
      boardMessages: allBoardMessages.map(SpBoardMessage.fromJson).toList(),
      automatedTimers: const [],
      repeatedTimers: const [],
    );
  }

  /// Dispose the underlying HTTP client.
  void dispose() {
    _headers.clear();
    _http.close();
  }
}
