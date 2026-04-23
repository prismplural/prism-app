import 'dart:async';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/chat_messages_table.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

part 'chat_messages_dao.g.dart';

const _maxUnreadConversationBatchSize = 400;

typedef ChatMessageSearchHit = ({
  String messageId,
  String conversationId,
  String snippet,
  DateTime timestamp,
  String? authorId,
});

@DriftAccessor(tables: [ChatMessages])
class ChatMessagesDao extends DatabaseAccessor<AppDatabase>
    with _$ChatMessagesDaoMixin {
  ChatMessagesDao(super.db);

  Future<List<ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) {
    final query = select(chatMessages)
      ..where(
        (m) =>
            m.conversationId.equals(conversationId) & m.isDeleted.equals(false),
      )
      ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  Stream<List<ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) =>
      (select(chatMessages)
            ..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.isDeleted.equals(false),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
          .watch();

  /// Watch messages with a limit — used for paginated display.
  Stream<List<ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) =>
      (select(chatMessages)
            ..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.isDeleted.equals(false),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
            ..limit(limit))
          .watch();

  Future<List<ChatMessage>> getAllMessages() =>
      (select(chatMessages)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
          .get();

  Future<ChatMessage?> getMessageById(String id) =>
      (select(chatMessages)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<int> insertMessage(ChatMessagesCompanion message) =>
      into(chatMessages).insert(message);

  Future<void> updateMessage(ChatMessagesCompanion message) {
    assert(message.id.present, 'Message id is required for update');
    return (update(
      chatMessages,
    )..where((m) => m.id.equals(message.id.value))).write(message);
  }

  Future<void> softDeleteMessage(String id) =>
      (update(chatMessages)..where((m) => m.id.equals(id))).write(
        const ChatMessagesCompanion(isDeleted: Value(true)),
      );

  Future<ChatMessage?> getLatestMessage(String conversationId) =>
      (select(chatMessages)
            ..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.isDeleted.equals(false),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
            ..limit(1))
          .getSingleOrNull();

  Stream<ChatMessage?> watchLatestMessage(String conversationId) =>
      (select(chatMessages)
            ..where(
              (m) =>
                  m.conversationId.equals(conversationId) &
                  m.isDeleted.equals(false),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
            ..limit(1))
          .watchSingleOrNull();

  /// Watch the count of unread messages in a conversation since [since].
  Stream<int> watchUnreadCount(String conversationId, DateTime since) {
    return customSelect(
      'SELECT COUNT(*) AS c FROM chat_messages '
      'WHERE conversation_id = ? AND timestamp > ? '
      'AND is_deleted = 0 AND is_system_message = 0',
      variables: [
        Variable.withString(conversationId),
        Variable.withDateTime(since),
      ],
      readsFrom: {chatMessages},
    ).watch().map((rows) => rows.isEmpty ? 0 : rows.first.read<int>('c'));
  }

  /// Watch the count of unread messages mentioning [memberId] since [since].
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) {
    return customSelect(
      'SELECT COUNT(*) AS c FROM chat_messages '
      'WHERE conversation_id = ? AND timestamp > ? '
      'AND is_deleted = 0 AND is_system_message = 0 '
      "AND content LIKE '%@[' || ? || ']%'",
      variables: [
        Variable.withString(conversationId),
        Variable.withDateTime(since),
        Variable.withString(memberId),
      ],
      readsFrom: {chatMessages},
    ).watch().map((rows) => rows.isEmpty ? 0 : rows.first.read<int>('c'));
  }

  /// Watch unread message counts for multiple conversations in a single query.
  ///
  /// [conversationSince] maps conversationId → cutoff DateTime.
  /// Returns a map of conversationId → unread count (only entries with count > 0).
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) {
    if (conversationSince.isEmpty) return Stream.value({});
    final entries = conversationSince.entries.toList(growable: false);
    if (entries.length <= _maxUnreadConversationBatchSize) {
      return _watchUnreadCountsBatch(conversationSince);
    }

    return _combineBatchedStreams<Map<String, int>>(
      _chunkConversationEntries(entries).map(
        (batch) =>
            _watchUnreadCountsBatch(Map<String, DateTime>.fromEntries(batch)),
      ),
      seed: const <String, int>{},
      merge: (events) {
        final combined = <String, int>{};
        for (final batch in events) {
          combined.addAll(batch);
        }
        return combined;
      },
    );
  }

  Stream<Map<String, int>> _watchUnreadCountsBatch(
    Map<String, DateTime> conversationSince,
  ) {
    assert(
      conversationSince.length <= _maxUnreadConversationBatchSize,
      'watchAllUnreadCounts batch exceeded the safe UNION ALL limit.',
    );

    final parts = <String>[];
    final vars = <Variable>[];
    for (final entry in conversationSince.entries) {
      parts.add(
        'SELECT ? AS conversation_id, COUNT(*) AS c FROM chat_messages '
        'WHERE conversation_id = ? AND timestamp > ? '
        'AND is_deleted = 0 AND is_system_message = 0 '
        'HAVING COUNT(*) > 0',
      );
      vars.add(Variable.withString(entry.key));
      vars.add(Variable.withString(entry.key));
      vars.add(Variable.withDateTime(entry.value));
    }

    return customSelect(
      parts.join(' UNION ALL '),
      variables: vars,
      readsFrom: {chatMessages},
    ).watch().map((rows) {
      final map = <String, int>{};
      for (final row in rows) {
        final id = row.read<String>('conversation_id');
        final count = row.read<int>('c');
        if (count > 0) map[id] = count;
      }
      return map;
    });
  }

  /// Watch the set of conversation IDs that have messages mentioning [memberId]
  /// since their respective cutoff times.
  ///
  /// [conversationSince] maps conversationId → cutoff DateTime.
  /// Returns the set of conversation IDs that have at least one mention.
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) {
    if (conversationSince.isEmpty) return Stream.value({});
    final entries = conversationSince.entries.toList(growable: false);
    if (entries.length <= _maxUnreadConversationBatchSize) {
      return _watchConversationsWithMentionsBatch(conversationSince, memberId);
    }

    return _combineBatchedStreams<Set<String>>(
      _chunkConversationEntries(entries).map(
        (batch) => _watchConversationsWithMentionsBatch(
          Map<String, DateTime>.fromEntries(batch),
          memberId,
        ),
      ),
      seed: const <String>{},
      merge: (events) => events.expand((batch) => batch).toSet(),
    );
  }

  Stream<Set<String>> _watchConversationsWithMentionsBatch(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) {
    assert(
      conversationSince.length <= _maxUnreadConversationBatchSize,
      'watchConversationsWithMentions batch exceeded the safe UNION ALL limit.',
    );

    final parts = <String>[];
    final vars = <Variable>[];
    for (final entry in conversationSince.entries) {
      parts.add(
        'SELECT ? AS conversation_id '
        'WHERE EXISTS ('
        'SELECT 1 FROM chat_messages '
        'WHERE conversation_id = ? AND timestamp > ? '
        'AND is_deleted = 0 AND is_system_message = 0 '
        "AND content LIKE '%@[' || ? || ']%'"
        ')',
      );
      vars.add(Variable.withString(entry.key));
      vars.add(Variable.withString(entry.key));
      vars.add(Variable.withDateTime(entry.value));
      vars.add(Variable.withString(memberId));
    }

    return customSelect(
      parts.join(' UNION ALL '),
      variables: vars,
      readsFrom: {chatMessages},
    ).watch().map(
      (rows) => rows.map((r) => r.read<String>('conversation_id')).toSet(),
    );
  }

  Iterable<List<MapEntry<String, DateTime>>> _chunkConversationEntries(
    List<MapEntry<String, DateTime>> entries,
  ) sync* {
    for (
      var start = 0;
      start < entries.length;
      start += _maxUnreadConversationBatchSize
    ) {
      final end = start + _maxUnreadConversationBatchSize;
      yield entries.sublist(start, end > entries.length ? entries.length : end);
    }
  }

  Stream<T> _combineBatchedStreams<T>(
    Iterable<Stream<T>> streams, {
    required T seed,
    required T Function(List<T> events) merge,
  }) {
    final batchStreams = streams.toList(growable: false);
    if (batchStreams.isEmpty) return Stream.value(seed);

    return Stream.multi((controller) {
      final latest = List<T>.filled(batchStreams.length, seed);
      final hasValue = List<bool>.filled(batchStreams.length, false);
      final subscriptions = <StreamSubscription<T>>[];
      var completed = 0;

      for (var i = 0; i < batchStreams.length; i++) {
        final subscription = batchStreams[i].listen(
          (event) {
            latest[i] = event;
            hasValue[i] = true;
            if (hasValue.every((value) => value)) {
              controller.add(merge(latest));
            }
          },
          onError: controller.addError,
          onDone: () {
            completed += 1;
            if (completed == batchStreams.length) {
              controller.close();
            }
          },
        );
        subscriptions.add(subscription);
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  Future<List<ChatMessageSearchHit>> searchMessages(
    String query, {
    int limit = 50,
  }) async {
    // Split into tokens, quote each for safety, append * for prefix matching.
    // "hel" matches "hello", "wor" matches "world", etc.
    final rawTokens = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final escaped = rawTokens
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .join(' ');
    if (escaped.isEmpty) return [];

    // We build the match-highlighted snippet Dart-side from the *redacted*
    // full content instead of SQLite's `snippet(...)`. FTS5's snippet picks
    // a window that can start/end mid-way through a `||spoiler||` span,
    // stripping the `||` delimiters — which would cause the downstream
    // `redactSpoilers(...)` in SearchResultTile to be a no-op and leak
    // spoiler plaintext into the result list.
    final rows = await customSelect(
      'SELECT m.content AS content, '
      'fts.message_id, fts.conversation_id, '
      'm.timestamp, m.author_id '
      'FROM chat_messages_fts fts '
      'JOIN chat_messages m ON m.id = fts.message_id '
      'WHERE chat_messages_fts MATCH ? '
      'ORDER BY m.timestamp DESC '
      'LIMIT ?',
      variables: [Variable.withString(escaped), Variable.withInt(limit)],
    ).get();

    return rows.map((row) {
      final content = row.read<String>('content');
      return (
        messageId: row.read<String>('message_id'),
        conversationId: row.read<String>('conversation_id'),
        snippet: _buildSafeSnippet(content, rawTokens),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('timestamp') * 1000,
        ),
        authorId: row.readNullable<String>('author_id'),
      );
    }).toList();
  }
}

/// Build a match-highlighted snippet from [rawContent] that can never leak
/// spoiler plaintext.
///
/// The full message is redacted first (so any `||…||` spans are already
/// `▮`-blocks), then whole-word matches for any [queryTokens] prefix are
/// located and wrapped in `[…]`. The surrounding window is ~40 chars before
/// the first match and ~80 chars after the last match inside that window,
/// bounded by the content ends. If no token matches inside the redacted
/// content (i.e. the FTS hit was on a term that lived entirely inside a
/// spoiler), a plain head-of-message preview is returned with no highlights.
String _buildSafeSnippet(String rawContent, List<String> queryTokens) {
  final safe = redactSpoilers(rawContent);
  const maxPreview = 120;
  final headPreview = safe.length <= maxPreview
      ? safe
      : '${safe.substring(0, maxPreview)}...';

  if (queryTokens.isEmpty) return headPreview;

  // Dart's `\b` and `\w` are ASCII-only even with `unicode: true`, so a
  // Cyrillic or Greek query would never bracket its match. We build an
  // equivalent boundary using a lookbehind for non-word Unicode chars and
  // extend with `\p{L}\p{N}_` for the rest of the word. Known limit:
  // continuous-script languages like CJK have no word separators, so a
  // query mid-sentence may not highlight — falls back to a plain head
  // preview, which is still safe.
  final tokenAlt = queryTokens.map(RegExp.escape).join('|');
  final pattern = RegExp(
    r'(?:(?<=^)|(?<=[^\p{L}\p{N}_]))(?:' + tokenAlt + r')[\p{L}\p{N}_]*',
    caseSensitive: false,
    unicode: true,
  );
  final matches = pattern.allMatches(safe).toList();
  if (matches.isEmpty) return headPreview;

  const beforeChars = 40;
  const afterChars = 80;
  final first = matches.first;
  final snipStart = (first.start - beforeChars).clamp(0, safe.length);
  final snipEnd = (first.end + afterChars).clamp(0, safe.length);

  final buf = StringBuffer();
  if (snipStart > 0) buf.write('...');
  var cursor = snipStart;
  for (final m in matches) {
    if (m.start < cursor || m.end > snipEnd) continue;
    buf.write(safe.substring(cursor, m.start));
    buf.write('[');
    buf.write(safe.substring(m.start, m.end));
    buf.write(']');
    cursor = m.end;
  }
  if (cursor < snipEnd) buf.write(safe.substring(cursor, snipEnd));
  if (snipEnd < safe.length) buf.write('...');
  return buf.toString();
}
