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
  TextColumn get fieldTypeId => text().nullable()();
  TextColumn get parentFieldId => text().nullable()();
  TextColumn get typeConfigJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
