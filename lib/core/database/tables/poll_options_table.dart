import 'package:drift/drift.dart';

class PollOptions extends Table {
  TextColumn get id => text()();
  TextColumn get pollId => text()();
  TextColumn get optionText => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isOtherOption =>
      boolean().withDefault(const Constant(false))();
  TextColumn get colorHex => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
