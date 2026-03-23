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
      (select(conversations)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Stream<Conversation?> watchConversationById(String id) =>
      (select(conversations)..where((c) => c.id.equals(id)))
          .watchSingleOrNull();

  Future<List<Conversation>> getConversationsForMember(
          String memberId) =>
      (select(conversations)
            ..where((c) =>
                c.participantIds.like('%"$memberId"%') &
                c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
          .get();

  Future<int> insertConversation(ConversationsCompanion conversation) =>
      into(conversations).insert(conversation);

  Future<void> updateConversation(ConversationsCompanion conversation) {
    assert(conversation.id.present, 'Conversation id is required for update');
    return (update(conversations)
          ..where((c) => c.id.equals(conversation.id.value)))
        .write(conversation);
  }

  Future<void> softDeleteConversation(String id) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
          const ConversationsCompanion(isDeleted: Value(true)));

  Future<void> updateLastActivity(String id) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
          ConversationsCompanion(lastActivityAt: Value(DateTime.now())));

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(conversations)
      ..where(conversations.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }
}
