import 'package:drift/drift.dart';

@DataClassName('ConversationCategoryRow')
class ConversationCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
