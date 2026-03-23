import 'package:drift/drift.dart';

class PollVotes extends Table {
  TextColumn get id => text()();
  TextColumn get pollOptionId => text()();
  TextColumn get memberId => text()();
  DateTimeColumn get votedAt => dateTime()();
  TextColumn get responseText => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
