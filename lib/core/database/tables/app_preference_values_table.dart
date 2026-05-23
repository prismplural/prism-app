import 'package:drift/drift.dart';

@DataClassName('AppPreferenceValueRow')
class AppPreferenceValues extends Table {
  @override
  String get tableName => 'app_preference_values';

  TextColumn get key => text()();
  TextColumn get valueType => text()();
  TextColumn get valueJson => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {key};
}
