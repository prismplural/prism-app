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
      (update(conversations)..where((c) => c.id.equals(id)))
          .write(ConversationsCompanion(includesAllMembers: Value(value)));

  Future<void> updateArchivedForEveryone(String id, bool value) =>
      (update(conversations)..where((c) => c.id.equals(id)))
          .write(ConversationsCompanion(archivedForEveryone: Value(value)));

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
