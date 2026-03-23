import 'package:prism_plurality/domain/models/conversation_category.dart';

abstract class ConversationCategoriesRepository {
  Stream<List<ConversationCategory>> watchAll();
  Future<ConversationCategory?> getById(String id);
  Future<void> create(ConversationCategory category);
  Future<void> update(ConversationCategory category);
  Future<void> delete(String id);
}
