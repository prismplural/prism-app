import 'package:drift/drift.dart';

@DataClassName('FrontSessionCommentRow')
class FrontSessionComments extends Table {
  TextColumn get id => text()();
  // FK to fronting_sessions. In the per-member fronting model this points to
  // the specific per-member session the comment was written on. Period views
  // aggregate comments by filtering this column to the period's session ids.
  TextColumn get sessionId => text()();
  TextColumn get body => text()();
  // User-visible "what time is this comment about" field.
  DateTimeColumn get timestamp => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
