import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart'
    as domain;

class ConversationCategoryMapper {
  ConversationCategoryMapper._();

  static domain.ConversationCategory toDomain(ConversationCategoryRow row) {
    return domain.ConversationCategory(
      id: row.id,
      name: row.name,
      displayOrder: row.displayOrder,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  static ConversationCategoriesCompanion toCompanion(
      domain.ConversationCategory model) {
    return ConversationCategoriesCompanion(
      id: Value(model.id),
      name: Value(model.name),
      displayOrder: Value(model.displayOrder),
      createdAt: Value(model.createdAt),
      modifiedAt: Value(model.modifiedAt),
    );
  }
}
