import 'package:drift/drift.dart';

class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get isSystemMessage =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get editedAt => dateTime().nullable()();
  TextColumn get authorId => text().nullable()();
  TextColumn get conversationId => text()();
  TextColumn get reactions =>
      text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get replyToId => text().nullable()();
  TextColumn get replyToAuthorId => text().nullable()();
  TextColumn get replyToContent => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
