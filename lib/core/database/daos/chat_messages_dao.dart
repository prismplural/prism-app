import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/chat_messages_table.dart';

part 'chat_messages_dao.g.dart';

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
      ..where((m) =>
          m.conversationId.equals(conversationId) &
          m.isDeleted.equals(false))
      ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  Stream<List<ChatMessage>> watchMessagesForConversation(
          String conversationId) =>
      (select(chatMessages)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
          .watch();

  Future<List<ChatMessage>> getAllMessages() =>
      (select(chatMessages)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
          .get();

  Future<ChatMessage?> getMessageById(String id) =>
      (select(chatMessages)..where((m) => m.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertMessage(ChatMessagesCompanion message) =>
      into(chatMessages).insert(message);

  Future<void> updateMessage(ChatMessagesCompanion message) {
    assert(message.id.present, 'Message id is required for update');
    return (update(chatMessages)
          ..where((m) => m.id.equals(message.id.value)))
        .write(message);
  }

  Future<void> softDeleteMessage(String id) =>
      (update(chatMessages)..where((m) => m.id.equals(id))).write(
          const ChatMessagesCompanion(isDeleted: Value(true)));

  Future<ChatMessage?> getLatestMessage(String conversationId) =>
      (select(chatMessages)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
            ..limit(1))
          .getSingleOrNull();

  Stream<ChatMessage?> watchLatestMessage(String conversationId) =>
      (select(chatMessages)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.isDeleted.equals(false))
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

    // Single query: group by conversation_id with per-conversation cutoff via UNION ALL.
    final parts = <String>[];
    final vars = <Variable>[];
    for (final entry in conversationSince.entries) {
      parts.add(
        'SELECT conversation_id, COUNT(*) AS c FROM chat_messages '
        'WHERE conversation_id = ? AND timestamp > ? '
        'AND is_deleted = 0 AND is_system_message = 0',
      );
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

    // Build a single query with UNION ALL for each conversation.
    final parts = <String>[];
    final vars = <Variable>[];
    for (final entry in conversationSince.entries) {
      parts.add(
        'SELECT conversation_id FROM chat_messages '
        'WHERE conversation_id = ? AND timestamp > ? '
        'AND is_deleted = 0 AND is_system_message = 0 '
        "AND content LIKE '%@[' || ? || ']%' "
        'LIMIT 1',
      );
      vars.add(Variable.withString(entry.key));
      vars.add(Variable.withDateTime(entry.value));
      vars.add(Variable.withString(memberId));
    }

    return customSelect(
      parts.join(' UNION ALL '),
      variables: vars,
      readsFrom: {chatMessages},
    ).watch().map((rows) =>
        rows.map((r) => r.read<String>('conversation_id')).toSet());
  }

  Future<List<QueryRow>> searchMessages(String query, {int limit = 50}) {
    // Split into tokens, quote each for safety, append * for prefix matching.
    // "hel" matches "hello", "wor" matches "world", etc.
    final tokens = query.trim().split(RegExp(r'\s+'));
    final escaped = tokens
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .join(' ');
    if (escaped.isEmpty) return Future.value([]);
    return customSelect(
      'SELECT snippet(chat_messages_fts, 0, \'[\', \']\', \'...\', 20) AS snippet, '
      'fts.message_id, fts.conversation_id, '
      'm.timestamp, m.author_id '
      'FROM chat_messages_fts fts '
      'JOIN chat_messages m ON m.id = fts.message_id '
      'WHERE chat_messages_fts MATCH ? '
      'ORDER BY m.timestamp DESC '
      'LIMIT ?',
      variables: [Variable.withString(escaped), Variable.withInt(limit)],
    ).get();
  }
}
