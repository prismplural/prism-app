import 'package:drift/drift.dart';

@DataClassName('CustomFieldValueRow')
class CustomFieldValues extends Table {
  TextColumn get id => text()();
  TextColumn get customFieldId => text()();
  TextColumn get memberId => text()();
  TextColumn get value => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
