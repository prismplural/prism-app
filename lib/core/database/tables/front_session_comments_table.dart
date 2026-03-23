import 'package:drift/drift.dart';

@DataClassName('FrontSessionCommentRow')
class FrontSessionComments extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get body => text()();
  DateTimeColumn get timestamp => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
