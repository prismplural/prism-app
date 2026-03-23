import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/conversation_categories_table.dart';

part 'conversation_categories_dao.g.dart';

@DriftAccessor(tables: [ConversationCategories])
class ConversationCategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationCategoriesDaoMixin {
  ConversationCategoriesDao(super.db);

  Stream<List<ConversationCategoryRow>> watchAll() =>
      (select(conversationCategories)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.displayOrder)]))
          .watch();

  Future<List<ConversationCategoryRow>> getAll() =>
      (select(conversationCategories)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.displayOrder)]))
          .get();

  Future<ConversationCategoryRow?> getById(String id) =>
      (select(conversationCategories)
            ..where((c) => c.id.equals(id) & c.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<int> create(ConversationCategoriesCompanion companion) =>
      into(conversationCategories).insert(companion);

  Future<void> updateCategory(
          String id, ConversationCategoriesCompanion companion) =>
      (update(conversationCategories)..where((c) => c.id.equals(id)))
          .write(companion);

  Future<void> softDelete(String id) =>
      (update(conversationCategories)..where((c) => c.id.equals(id)))
          .write(const ConversationCategoriesCompanion(isDeleted: Value(true)));
}
