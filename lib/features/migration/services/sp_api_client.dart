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
  static const _avatarServeBaseUrl = 'https://serve.apparyllis.com/avatars';

  final String _token;
  final http.Client _http;

  late final Map<String, String> _headers;

  SpApiClient({required String token, http.Client? httpClient})
    : _token = token.trim(),
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
        .get(Uri.parse('$_baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<
    ({
      String systemId,
      String? username,
      String? systemName,
      String? systemColor,
      String? systemDescription,
      String? systemAvatarUrl,
      Map<String, String> customFieldValueKeyMap,
    })
  >
  _getSelfProfile() async {
    final json = await _get('/me') as Map<String, dynamic>;
    final content =
        (json['content'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final uid =
        content['uid']?.toString() ??
        json['id']?.toString() ??
        json['uid']?.toString() ??
        json['_id']?.toString() ??
        '';
    final username =
        content['username'] as String? ?? json['username'] as String?;
    final systemName =
        (content['name'] as String?) ?? (json['name'] as String?) ?? username;
    final avatarUrl =
        (content['avatarUrl'] as String?) ?? (json['avatarUrl'] as String?);
    final avatarUuid =
        (content['avatarUuid'] as String?) ?? (json['avatarUuid'] as String?);
    final systemAvatarUrl = avatarUrl != null && avatarUrl.isNotEmpty
        ? avatarUrl
        : (avatarUuid != null && avatarUuid.isNotEmpty && uid.isNotEmpty)
        ? '$_avatarServeBaseUrl/$uid/$avatarUuid'
        : null;

    return (
      systemId: uid,
      username: username,
      systemName: systemName,
      systemColor: (content['color'] as String?) ?? (json['color'] as String?),
      systemDescription:
          (content['desc'] as String?) ?? (json['desc'] as String?),
      systemAvatarUrl: systemAvatarUrl,
      customFieldValueKeyMap: extractSpCustomFieldValueKeyMap(
        content['fields'],
      ),
    );
  }

  // -- public API -----------------------------------------------------------

  /// GET /v1/me — returns the system user ID and username.
  ///
  /// The /me response wraps user data inside a `content` field:
  /// `{ "id": "...", "content": { "uid": "...", "username": "..." } }`
  Future<({String systemId, String? username})> verifyToken() async {
    final profile = await _getSelfProfile();
    return (systemId: profile.systemId, username: profile.username);
  }

  /// SP API list responses wrap each item in `{exists, id, content: {...}}`.
  /// This helper merges `content` into the top level and exposes the
  /// wrapper's `id` as `_id` so all existing `fromJson` factories work
  /// identically for both file exports (already flat) and API responses.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    final content = raw['content'];
    if (content is! Map<String, dynamic>) return raw;
    return {...content, '_id': raw['id'] ?? raw['_id']};
  }

  /// Parse a list response — unwraps content-wrapped items and returns
  /// empty list on non-list bodies.
  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final json = await _get(path);
    if (json is List) {
      return json.cast<Map<String, dynamic>>().map(_unwrap).toList();
    }
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

  /// GET /v1/poll/:sid/:pollId
  Future<Map<String, dynamic>?> getPoll(String sid, String pollId) async {
    final json = await _get('/poll/${_enc(sid)}/${_enc(pollId)}');
    if (json is Map<String, dynamic>) {
      return _unwrap(json);
    }
    return null;
  }

  /// GET /v1/notes/:sid/:memberId
  Future<List<Map<String, dynamic>>> getNotes(String sid, String memberId) =>
      _getList('/notes/${_enc(sid)}/${_enc(memberId)}');

  /// GET /v1/comments/:type/:docId
  Future<List<Map<String, dynamic>>> getComments(String type, String docId) =>
      _getList('/comments/${_enc(type)}/${_enc(docId)}');

  /// GET /v1/chat/channels — all chat channels for the authenticated user.
  Future<List<Map<String, dynamic>>> getChannels() =>
      _getList('/chat/channels');

  /// GET /v1/chat/categories — all chat categories for the authenticated user.
  Future<List<Map<String, dynamic>>> getChannelCategories() =>
      _getList('/chat/categories');

  /// GET /v1/chat/messages/:channelId — messages in a channel.
  ///
  /// The current SP API requires a `limit` query parameter and paginates via
  /// `skipTo=<lastMessageId>`. We walk forward until the server returns a short
  /// page or stops advancing the cursor, deduping by message id defensively in
  /// case the terminal page repeats.
  Future<List<Map<String, dynamic>>> getChannelMessages(
    String channelId,
  ) async {
    const pageSize = 100;
    final allMessages = <Map<String, dynamic>>[];
    final seenMessageIds = <String>{};
    String? cursor;

    while (true) {
      final query = <String>[
        'limit=$pageSize',
        'sortOrder=1',
        if (cursor != null) 'skipTo=${_enc(cursor)}',
      ].join('&');
      final page = await _getList('/chat/messages/${_enc(channelId)}?$query');
      if (page.isEmpty) break;

      final lastId = (page.last['_id'] ?? page.last['id'] ?? '').toString();
      if (cursor != null && (lastId.isEmpty || lastId == cursor)) {
        break;
      }

      for (final message in page) {
        final messageId = (message['_id'] ?? message['id'] ?? '').toString();
        if (messageId.isNotEmpty && !seenMessageIds.add(messageId)) {
          continue;
        }
        allMessages.add(message);
      }

      if (page.length < pageSize || lastId.isEmpty) {
        break;
      }
      cursor = lastId;
    }

    return allMessages;
  }

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
    // 1. Get the authenticated user's profile once and reuse it.
    final profile = await _getSelfProfile();
    final sid = profile.systemId;

    // 2. Fetch main collections in parallel.
    final results = await Future.wait([
      getMembers(sid),
      getCustomFronts(sid),
      getFrontHistory(),
      getGroups(sid),
      getCustomFields(sid),
      getPolls(sid),
      getChannelCategories(),
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
    final pollSummaries = results[5];
    final channelCategories = results[6];
    onProgress?.call('Categories', channelCategories.length);

    final polls = <Map<String, dynamic>>[];
    for (var i = 0; i < pollSummaries.length; i += 5) {
      final chunk = pollSummaries.skip(i).take(5);
      final pollResults = await Future.wait(
        chunk.map((summary) async {
          final pollId = (summary['_id'] ?? summary['id'] ?? '').toString();
          if (pollId.isEmpty) return summary;
          final detail = await getPoll(sid, pollId).catchError((_) => null);
          return _mergePollPayload(summary, detail);
        }),
      );
      polls.addAll(pollResults);
      onProgress?.call('Polls', polls.length);
    }

    // 3. Fetch notes per member (5 concurrent).
    final allNotes = <Map<String, dynamic>>[];
    for (var i = 0; i < members.length; i += 5) {
      final chunk = members.skip(i).take(5);
      final noteResults = await Future.wait(
        chunk.map((m) {
          final mid = (m['_id'] ?? m['id'] ?? '').toString();
          return getNotes(sid, mid).catchError((_) => <Map<String, dynamic>>[]);
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
          return getComments(
            'frontHistory',
            fhId,
          ).catchError((_) => <Map<String, dynamic>>[]);
        }),
      );
      for (final comments in commentResults) {
        allComments.addAll(comments);
      }
      onProgress?.call('Comments', allComments.length);
    }

    // 5. Fetch chat channels and their messages.
    final channels = await getChannels().catchError(
      (_) => <Map<String, dynamic>>[],
    );
    onProgress?.call('Channels', channels.length);

    final allChatMessages = <SpMessage>[];
    for (var i = 0; i < channels.length; i += 5) {
      final chunk = channels.skip(i).take(5);
      final msgResults = await Future.wait(
        chunk.map((ch) {
          final chId = (ch['_id'] ?? ch['id'] ?? '').toString();
          return getChannelMessages(chId)
              .then(
                (msgs) => msgs.map((m) => SpMessage.fromJson(m, chId)).toList(),
              )
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
          return _getList(
            '/board/member/${_enc(mid)}',
          ).catchError((_) => <Map<String, dynamic>>[]);
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
      members: members
          .map(
            (memberJson) => SpMember.fromJson(
              normalizeSpMemberJsonInfoKeys(
                memberJson,
                profile.customFieldValueKeyMap,
              ),
            ),
          )
          .toList(),
      customFronts: customFronts.map(SpCustomFront.fromJson).toList(),
      frontHistory: frontHistory.map(SpFrontHistory.fromJson).toList(),
      groups: groups.map(SpGroup.fromJson).toList(),
      channels: channels.map(SpChannel.fromJson).toList(),
      channelCategories: channelCategories
          .map(SpChannelCategory.fromJson)
          .toList(),
      messages: allChatMessages,
      polls: polls.map(SpPoll.fromJson).toList(),
      notes: allNotes.map(SpNote.fromJson).toList(),
      comments: allComments.map(SpComment.fromJson).toList(),
      customFields: customFields.map(SpCustomFieldDef.fromJson).toList(),
      boardMessages: allBoardMessages.map(SpBoardMessage.fromJson).toList(),
      automatedTimers: const [],
      repeatedTimers: const [],
      systemName: profile.systemName,
      systemColor: profile.systemColor,
      systemDescription: profile.systemDescription,
      systemAvatarUrl: profile.systemAvatarUrl,
    );
  }

  Map<String, dynamic> _mergePollPayload(
    Map<String, dynamic> summary,
    Map<String, dynamic>? detail,
  ) {
    if (detail == null) return summary;
    return {
      ...summary,
      ...detail,
      'options': detail['options'] ?? summary['options'],
      'votes': detail['votes'] ?? summary['votes'],
      'allowAbstain': detail['allowAbstain'] ?? summary['allowAbstain'],
      'allowVeto': detail['allowVeto'] ?? summary['allowVeto'],
      'allowMultiple': detail['allowMultiple'] ?? summary['allowMultiple'],
      'custom': detail['custom'] ?? summary['custom'],
      'desc': detail['desc'] ?? summary['desc'],
      'endTime': detail['endTime'] ?? summary['endTime'],
    };
  }

  /// Dispose the underlying HTTP client.
  void dispose() {
    _headers.clear();
    _http.close();
  }
}
