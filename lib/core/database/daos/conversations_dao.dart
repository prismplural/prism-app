import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/sql_like.dart';
import 'package:prism_plurality/core/database/tables/conversations_table.dart';

part 'conversations_dao.g.dart';

@DriftAccessor(tables: [Conversations])
class ConversationsDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationsDaoMixin {
  ConversationsDao(super.db);

  Future<List<Conversation>> getAllConversations() =>
      (select(conversations)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
          .get();

  Stream<List<Conversation>> watchAllConversations() =>
      (select(conversations)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
          .watch();

  Future<Conversation?> getConversationById(String id) =>
      (select(conversations)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<Conversation>> getConversationsByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const <Conversation>[]);
    return (select(conversations)..where((c) => c.id.isIn(ids))).get();
  }

  Future<Conversation?> getMentionConversationById(String id) =>
      (select(conversations)
            ..where((c) => c.id.equals(id) & c.isDeleted.equals(false)))
          .getSingleOrNull();

  Stream<List<Conversation>> watchMentionConversationsByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <Conversation>[]);
    return (select(
      conversations,
    )..where((c) => c.id.isIn(ids) & c.isDeleted.equals(false))).watch();
  }

  Future<List<Conversation>> searchMentionCandidates(
    String filter, {
    int limit = 12,
    List<String> activeFronterIds = const [],
    bool includeAdminGroups = false,
  }) {
    final trimmed = filter.trim();
    final activeIds = activeFronterIds.toSet().toList(growable: false);
    final q = select(conversations)
      ..where((c) {
        final participantMatch = activeIds.isEmpty
            ? const Constant<bool>(false)
            : activeIds
                  .map((id) => c.participantIds.like('%"$id"%'))
                  .reduce((a, b) => a | b);
        final visible =
            c.isDeleted.equals(false) &
            (participantMatch |
                (c.includesAllMembers.equals(true) &
                    c.isDirectMessage.equals(false)) |
                (activeIds.isEmpty
                    ? const Constant<bool>(false)
                    : (c.isDirectMessage.equals(true) &
                          c.participantIds.equals('[]'))) |
                (includeAdminGroups
                    ? c.isDirectMessage.equals(false)
                    : const Constant<bool>(false)));
        if (trimmed.isEmpty) return visible;
        final pattern = escapedSqlLikeContainsPattern(trimmed);
        return visible &
            (c.title.like(pattern, escapeChar: sqlLikeEscapeChar) |
                c.description.like(pattern, escapeChar: sqlLikeEscapeChar) |
                c.emoji.like(pattern, escapeChar: sqlLikeEscapeChar));
      })
      ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)])
      ..limit(limit);
    return q.get();
  }

  Stream<Conversation?> watchConversationById(String id) => (select(
    conversations,
  )..where((c) => c.id.equals(id))).watchSingleOrNull();

  Future<List<Conversation>> getConversationsForMember(String memberId) =>
      (select(conversations)
            ..where(
              (c) =>
                  (c.participantIds.like('%"$memberId"%') |
                      c.includesAllMembers.equals(true)) &
                  c.isDeleted.equals(false),
            )
            ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
          .get();

  Future<int> insertConversation(ConversationsCompanion conversation) =>
      into(conversations).insert(conversation);

  /// Batch-insert conversations in a single Drift `batch()` round-trip.
  Future<void> batchInsertConversations(
    List<ConversationsCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(conversations, rows));
  }

  Future<void> updateConversation(ConversationsCompanion conversation) {
    assert(conversation.id.present, 'Conversation id is required for update');
    return (update(
      conversations,
    )..where((c) => c.id.equals(conversation.id.value))).write(conversation);
  }

  Future<void> updateParticipantIds(String id, String participantIdsJson) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(participantIds: Value(participantIdsJson)),
      );

  Future<void> updateIncludesAllMembers(String id, bool value) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(includesAllMembers: Value(value)),
      );

  Future<void> updateArchivedByMemberIds(String id, String archivedByJson) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(archivedByMemberIds: Value(archivedByJson)),
      );

  Future<void> updateMutedByMemberIds(String id, String mutedByJson) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(mutedByMemberIds: Value(mutedByJson)),
      );

  Future<void> updateLastReadTimestamps(String id, String timestampsJson) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(lastReadTimestamps: Value(timestampsJson)),
      );

  Future<void> softDeleteConversation(String id) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        const ConversationsCompanion(isDeleted: Value(true)),
      );

  Future<void> updateLastActivity(String id) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(lastActivityAt: Value(DateTime.now())),
      );

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(conversations)
      ..where(conversations.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }
}
