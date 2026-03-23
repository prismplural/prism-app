// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_categories_dao.dart';

// ignore_for_file: type=lint
mixin _$ConversationCategoriesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ConversationCategoriesTable get conversationCategories =>
      attachedDatabase.conversationCategories;
  ConversationCategoriesDaoManager get managers =>
      ConversationCategoriesDaoManager(this);
}

class ConversationCategoriesDaoManager {
  final _$ConversationCategoriesDaoMixin _db;
  ConversationCategoriesDaoManager(this._db);
  $$ConversationCategoriesTableTableManager get conversationCategories =>
      $$ConversationCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.conversationCategories,
      );
}
