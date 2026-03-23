import 'package:drift/drift.dart';

@DataClassName('HabitCompletion')
class HabitCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  DateTimeColumn get completedAt => dateTime()();
  TextColumn get completedByMemberId => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get wasFronting => boolean().withDefault(const Constant(false))();
  IntColumn get rating => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
