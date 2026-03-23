import 'package:drift/drift.dart';

@DataClassName('CustomFieldRow')
class CustomFields extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get fieldType => integer()();
  IntColumn get datePrecision => integer().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
