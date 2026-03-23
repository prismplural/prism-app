import 'package:drift/drift.dart';

class Polls extends Table {
  TextColumn get id => text()();
  TextColumn get question => text()();
  BoolColumn get isAnonymous =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allowsMultipleVotes =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
