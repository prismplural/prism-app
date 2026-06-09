import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
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

  Stream<Conversation?> watchConversationById(String id) => (select(
    conversations,
  )..where((c) => c.id.equals(id))).watchSingleOrNull();

  Expression<bool> _visibleToMember(Conversations c, String memberId) {
    final quotedMember = '%"$memberId"%';
    return (c.participantIds.like(quotedMember) |
            c.includesAllMembers.equals(true)) &
        c.isDeleted.equals(false) &
        c.isDirectMessage.equals(false) &
        c.archivedForEveryone.equals(false) &
        c.archivedByMemberIds.like(quotedMember).not();
  }

  Future<List<Conversation>> getConversationsForMember(String memberId) =>
      (select(conversations)
            ..where((c) => _visibleToMember(c, memberId))
            ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
          .get();

  Future<List<({Conversation conversation, int messageCount})>>
  getConversationActivityForMember(String memberId, {int? limit}) async {
    if (limit != null && limit <= 0) {
      return const <({Conversation conversation, int messageCount})>[];
    }

    final limitSql = limit == null ? '' : 'LIMIT ?';
    final rows = await customSelect(
      '''
      SELECT c.*, COUNT(m.id) AS message_count
      FROM conversations c
      LEFT JOIN chat_messages m
        ON m.conversation_id = c.id
       AND m.is_deleted = 0
      WHERE (c.participant_ids LIKE ? OR c.includes_all_members = 1)
        AND c.is_deleted = 0
        AND c.is_direct_message = 0
        AND c.archived_for_everyone = 0
        AND c.archived_by_member_ids NOT LIKE ?
      GROUP BY c.id
      ORDER BY message_count DESC, c.last_activity_at DESC
      $limitSql
      ''',
      variables: [
        Variable.withString('%"$memberId"%'),
        Variable.withString('%"$memberId"%'),
        if (limit != null) Variable.withInt(limit),
      ],
      readsFrom: {conversations, attachedDatabase.chatMessages},
    ).get();

    return rows
        .map(
          (row) => (
            conversation: Conversation(
              id: row.read<String>('id'),
              createdAt: row.read<DateTime>('created_at'),
              lastActivityAt: row.read<DateTime>('last_activity_at'),
              title: row.read<String?>('title'),
              emoji: row.read<String?>('emoji'),
              isDirectMessage: row.read<bool>('is_direct_message'),
              creatorId: row.read<String?>('creator_id'),
              participantIds: row.read<String>('participant_ids'),
              lastReadTimestamps: row.read<String>('last_read_timestamps'),
              archivedByMemberIds: row.read<String>('archived_by_member_ids'),
              mutedByMemberIds: row.read<String>('muted_by_member_ids'),
              description: row.read<String?>('description'),
              categoryId: row.read<String?>('category_id'),
              displayOrder: row.read<int>('display_order'),
              isDeleted: row.read<bool>('is_deleted'),
              includesAllMembers: row.read<bool>('includes_all_members'),
              archivedForEveryone: row.read<bool>('archived_for_everyone'),
            ),
            messageCount: row.read<int>('message_count'),
          ),
        )
        .toList();
  }

  Future<int> insertConversation(ConversationsCompanion conversation) =>
      into(conversations).insert(conversation);

  /// Batch-insert conversations in a single Drift `batch()` round-trip.
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
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

  Future<void> updateArchivedForEveryone(String id, bool value) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(archivedForEveryone: Value(value)),
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
